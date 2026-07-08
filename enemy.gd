extends CharacterBody3D

# --- MACHINE À ÉTATS ---
enum State { PATROL, SEARCH, CHASE, ATTACK }
var current_state: State = State.PATROL

@export_category("Patrouille & IA")
@export var patrol_radius: float = 15.0
@export var wait_time: float = 1.0 

var wait_timer: float = 0.0

@export_category("Statistiques")
@export var speed: float = 4.0
@export var acceleration: float = 10.0
@export var health: int = 100
@export var gravity: float = 9.8
@export var rotation_speed: float = 8.0

@export_category("Vision & Combat")
@export var fov_angle: float = 90.0 # Champ de vision de 90 degrés
@export var view_distance: float = 30.0 # Distance max pour te voir
@export var attack_range: float = 15.0 # Distance à laquelle il s'arrête pour tirer
@export var damage: int = 10
@export var fire_rate: float = 0.8 # Temps entre chaque tir

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var aim_raycast: RayCast3D = $AimRayCast

@onready var animation_player: AnimationPlayer = $Soldier/AnimationPlayer

var player: Node3D = null
var is_ready_to_navigate: bool = false
var fire_timer: float = 0.0

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 1.0
	if animation_player.has_animation("mixamo_com"):
		animation_player.play("mixamo_com")
	call_deferred("setup_navigation")

func setup_navigation() -> void:
	await get_tree().physics_frame
	is_ready_to_navigate = true

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	if not is_ready_to_navigate or not player or not is_instance_valid(player):
		move_and_slide()
		return

	# Gestion des timers
	if fire_timer > 0:
		fire_timer -= delta

	# 1. Analyse de l'environnement (A-t-il le joueur en visuel ?)
	var has_los = _has_line_of_sight()
	var distance_to_player = global_position.distance_to(player.global_position)

	# 2. Logique de décision (Changement d'état)
	if has_los:
		# Le joueur est en vue !
		nav_agent.target_position = player.global_position
		if distance_to_player <= attack_range:
			current_state = State.ATTACK
		else:
			current_state = State.CHASE
	else:
		# Le joueur n'est PLUS en vue.
		if current_state == State.CHASE or current_state == State.ATTACK:
			# On vient de le perdre : on bascule en recherche vers sa dernière position
			current_state = State.SEARCH
			wait_timer = wait_time # Prépare le timer pour quand on arrivera sur place

	# 3. Exécution de l'action selon l'état
	match current_state:
		State.PATROL, State.SEARCH:
			_handle_patrol_and_search(delta)
		State.CHASE:
			_move_towards_target(delta)
		State.ATTACK:
			_handle_attack(delta)

	move_and_slide()

# --- MOUVEMENTS ---
# --- DÉPLACEMENTS (TRAQUE) ---
func _move_towards_target(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		return # S'il a atteint la cible, il s'arrête
		
	var next_path_position = nav_agent.get_next_path_position()
	var direction = (next_path_position - global_position)
	direction.y = 0
	direction = direction.normalized()

	# On sprinte presque en mode CHASE
	velocity.x = lerp(velocity.x, direction.x * speed, delta * acceleration)
	velocity.z = lerp(velocity.z, direction.z * speed, delta * acceleration)
	_smooth_look_at(direction, delta)

# --- PATROUILLE & RECHERCHE ---
func _handle_patrol_and_search(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		# L'ennemi est arrivé à son point (point de patrouille ou dernière position du joueur)
		# 1. Il freine
		velocity.x = lerp(velocity.x, 0.0, delta * acceleration)
		velocity.z = lerp(velocity.z, 0.0, delta * acceleration)

		# 2. Il "regarde autour de lui" en attendant
		wait_timer -= delta
		if wait_timer <= 0.0:
			# 3. Fin de l'attente : on choisit un nouveau point et on repart en patrouille
			_set_random_patrol_point()
			current_state = State.PATROL
		return
		
	# S'il n'est pas encore arrivé, il marche calmement vers le point
	var next_path_position = nav_agent.get_next_path_position()
	var direction = (next_path_position - global_position)
	direction.y = 0
	direction = direction.normalized()

	# Vitesse légèrement réduite en patrouille pour plus de réalisme
	velocity.x = lerp(velocity.x, direction.x * (speed * 0.6), delta * acceleration)
	velocity.z = lerp(velocity.z, direction.z * (speed * 0.6), delta * acceleration)
	_smooth_look_at(direction, delta)

func _set_random_patrol_point() -> void:
	wait_timer = wait_time # On réarme le timer pour le prochain arrêt

	# Crée une direction aléatoire autour de l'ennemi
	var random_dir = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
	# Pousse ce point à une distance aléatoire
	var random_pos = global_position + (random_dir * randf_range(5.0, patrol_radius))

	# MAGIE GODOT 4 : On s'assure que le point aléatoire atterrit bien sur la surface navigable !
	var safe_point = NavigationServer3D.map_get_closest_point(nav_agent.get_navigation_map(), random_pos)

	nav_agent.target_position = safe_point

# --- COMBAT ---
func _handle_attack(delta: float) -> void:
	# L'ennemi s'arrête (ou ralentit) pour tirer
	velocity.x = lerp(velocity.x, 0.0, delta * (acceleration * 2))
	velocity.z = lerp(velocity.z, 0.0, delta * (acceleration * 2))
	
	# Il tourne la tête directement vers le joueur pour viser
	var dir_to_player = (player.global_position - global_position)
	dir_to_player.y = 0
	_smooth_look_at(dir_to_player.normalized(), delta)

	if fire_timer <= 0.0:
		_shoot()

func _shoot() -> void:
	fire_timer = fire_rate
	print(name, " tire sur le joueur !")
	
	# Hitscan : Si l'ennemi a la ligne de vue, on considère que son tir touche 
	# (Tu pourras ajouter une marge d'erreur/dispersion plus tard)
	if player.has_method("take_damage"):
		player.take_damage(damage)

# --- VISION TACTIQUE (Cône de vision + Raycast) ---
func _has_line_of_sight() -> bool:
	var dir_to_player = global_position.direction_to(player.global_position)
	var distance = global_position.distance_to(player.global_position)
	
	# 1. Le joueur est-il assez proche ?
	if distance > view_distance:
		return false
		
	# 2. Le joueur est-il dans l'angle de vision (FOV) devant l'ennemi ?
	var forward = -global_transform.basis.z # Vecteur "Avant" de l'ennemi
	# On utilise le produit scalaire (dot) pour vérifier l'angle
	if forward.dot(dir_to_player) < cos(deg_to_rad(fov_angle / 2.0)):
		return false # Le joueur est dans son dos
		
	# 3. Y a-t-il un mur entre l'ennemi et le joueur ? (Raycast)
	# On cible le centre/haut du corps du joueur, pas ses pieds
	var target_pos = player.global_position + Vector3(0, 1.0, 0)
	# Convertit la position globale en position locale pour le Raycast
	aim_raycast.target_position = aim_raycast.to_local(target_pos)
	aim_raycast.force_raycast_update()
	
	if aim_raycast.is_colliding():
		var collider = aim_raycast.get_collider()
		if collider.is_in_group("player"):
			return true
			
	return false

# --- OUTILS ---
func _smooth_look_at(direction: Vector3, delta: float) -> void:
	if direction.length() > 0.1:
		var target_angle = atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, delta * rotation_speed)

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		queue_free()
