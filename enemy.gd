extends CharacterBody3D
signal killed(victim_node, killer_node)

# --- MACHINE À ÉTATS ---
enum State { PATROL, SEARCH, CHASE, ATTACK }
var current_state: State = State.PATROL

@export_category("Patrouille & IA")
@export var patrol_radius: float = 15.0
@export var wait_time: float = 1.0 

var wait_timer: float = 0.0

@export_category("Statistiques")
@export var speed: float = 6.0
@export var acceleration: float = 12.0
@export var health: int = 100
@export var gravity: float = 9.8
@export var rotation_speed: float = 8.0

@export_category("Facteur Humain")
@export var reaction_time: float = 0.3 # Temps avant de tirer quand il voit un ennemi
@export var accuracy: float = 0.8 # 80% de chance de toucher
var reaction_timer: float = 0.0

@export_category("Vision & Combat")
@export var fov_angle: float = 120.0
@export var view_distance: float = 30.0
@export var attack_range: float = 15.0
@export var damage: int = 10
@export var fire_rate: float = 0.8 

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var aim_raycast: RayCast3D = $AimRayCast
@onready var animation_player: AnimationPlayer = $Soldier/AnimationPlayer

@export_category("Système d'Équipe")
@onready var team_indicator: Label3D = $TeamIndicator
@export var team_id: int = 0 # 0 = Mêlée générale, 1 = Équipe Joueur, 2 = Équipe Ennemi

var current_target: CharacterBody3D = null
var scan_timer: float = 0.0
var scan_interval: float = 0.2
var is_ready_to_navigate: bool = false
var fire_timer: float = 0.0

func _ready() -> void:
	if not is_in_group("enemy"):
		add_to_group("enemy")
	if not is_in_group("combatants"):
		add_to_group("combatants")
		
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 1.0
	
	if animation_player.has_animation("mixamo_com"):
		animation_player.play("mixamo_com")
	
	_setup_team_indicator()
	
	call_deferred("setup_navigation")

func setup_navigation() -> void:
	await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout
	is_ready_to_navigate = true
	_set_random_patrol_point()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	if not is_ready_to_navigate:
		move_and_slide()
		return

	if fire_timer > 0:
		fire_timer -= delta

	# 1. RECHERCHE DE CIBLE
	scan_timer -= delta
	if scan_timer <= 0.0:
		scan_timer = scan_interval
		# Ne cherche une nouvelle cible que s'il n'en a pas déjà une bonne
		if not current_target or not is_instance_valid(current_target) or current_target.health <= 0:
			current_target = _find_closest_valid_target()

	# 2. LOGIQUE DE DÉCISION
	if current_target and is_instance_valid(current_target):
		var has_los = _has_line_of_sight(current_target)
		var distance_to_target = global_position.distance_to(current_target.global_position)

		if has_los:
			nav_agent.target_position = current_target.global_position
			
			# Hystérésis pour solidifier l'état d'attaque
			var threshold = attack_range
			if current_state == State.ATTACK:
				threshold = attack_range + 2.0 
				
			if distance_to_target <= threshold:
				if current_state != State.ATTACK:
					reaction_timer = reaction_time
				current_state = State.ATTACK
			else:
				current_state = State.CHASE
		else:
			if current_state == State.CHASE or current_state == State.ATTACK:
				current_state = State.SEARCH
				wait_timer = wait_time
	else:
		if current_state == State.CHASE or current_state == State.ATTACK:
			current_state = State.PATROL

	# 3. EXÉCUTION DE L'ACTION
	match current_state:
		State.PATROL, State.SEARCH:
			_handle_patrol_and_search(delta)
		State.CHASE:
			_handle_chase(delta) # FIX : Nouvelle fonction dédiée à la traque
		State.ATTACK:
			_handle_attack(delta)

	move_and_slide()

# --- MOUVEMENTS ---
func _handle_chase(delta: float) -> void:
	# Le bot avance le long du chemin
	if not nav_agent.is_navigation_finished():
		var next_path_position = nav_agent.get_next_path_position()
		var direction = (next_path_position - global_position)
		direction.y = 0
		if direction != Vector3.ZERO:
			direction = direction.normalized()
			velocity.x = lerp(velocity.x, direction.x * speed, delta * acceleration)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * acceleration)
	else:
		velocity.x = lerp(velocity.x, 0.0, delta * acceleration)
		velocity.z = lerp(velocity.z, 0.0, delta * acceleration)

	# FIX TMBLEMENTS : En CHASE, le bot te regarde TOI en permanence, comme un joueur normal !
	if current_target and is_instance_valid(current_target):
		var look_dir = (current_target.global_position - global_position)
		look_dir.y = 0
		_smooth_look_at(look_dir.normalized(), delta)


func _handle_patrol_and_search(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		velocity.x = lerp(velocity.x, 0.0, delta * acceleration)
		velocity.z = lerp(velocity.z, 0.0, delta * acceleration)

		wait_timer -= delta
		if wait_timer <= 0.0:
			current_target = null 
			_set_random_patrol_point()
			current_state = State.PATROL
		return
		
	var next_path_position = nav_agent.get_next_path_position()
	var direction = (next_path_position - global_position)
	direction.y = 0

	if direction != Vector3.ZERO:
		direction = direction.normalized()
		velocity.x = lerp(velocity.x, direction.x * (speed * 0.6), delta * acceleration)
		velocity.z = lerp(velocity.z, direction.z * (speed * 0.6), delta * acceleration)
		_smooth_look_at(direction, delta)

func _set_random_patrol_point() -> void:
	wait_timer = wait_time
	var random_dir = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
	var random_pos = global_position + (random_dir * randf_range(5.0, patrol_radius))
	var safe_point = NavigationServer3D.map_get_closest_point(nav_agent.get_navigation_map(), random_pos)
	nav_agent.target_position = safe_point

# --- COMBAT ---
func _handle_attack(delta: float) -> void:
	if not current_target: return
	
	velocity.x = lerp(velocity.x, 0.0, delta * (acceleration * 2))
	velocity.z = lerp(velocity.z, 0.0, delta * (acceleration * 2))
	
	var dir_to_target = (current_target.global_position - global_position)
	dir_to_target.y = 0
	_smooth_look_at(dir_to_target.normalized(), delta)

	# On décrémente le temps de réaction humain avant de tirer
	if reaction_timer > 0:
		reaction_timer -= delta
		return # Il vise, mais ne tire pas encore !

	if fire_timer <= 0.0:
		_shoot()

func _shoot() -> void:
	fire_timer = fire_rate
	if current_target and is_instance_valid(current_target):
		# TODO : Jouer l'animation de tir et le son ici

		# Calcul de la précision (Miss chance)
		if randf() <= accuracy:
			if current_target.has_method("take_damage"):
				current_target.take_damage(damage, self)
		else:
			print(name, " a raté son tir !") # Tu pourras faire spawner un impact de balle à côté du joue

# --- VISION TACTIQUE ---
func _has_line_of_sight(target: Node3D) -> bool:
	if not target or not is_instance_valid(target): return false
	
	var dir_to_target = global_position.direction_to(target.global_position)
	var distance = global_position.distance_to(target.global_position)
	
	if distance > view_distance:
		return false
		
	var forward = -global_transform.basis.z
	if forward.dot(dir_to_target) < cos(deg_to_rad(fov_angle / 2.0)):
		return false
		
	var target_pos = target.global_position + Vector3(0, 1.0, 0)
	aim_raycast.target_position = aim_raycast.to_local(target_pos)
	aim_raycast.force_raycast_update()
	
	if aim_raycast.is_colliding():
		var collider = aim_raycast.get_collider()
		if collider == target:
			return true
			
	return false

# --- SYSTÈME DE SÉLECTION D'ÉQUIPE ---
func _find_closest_valid_target() -> CharacterBody3D:
	var all_combatants = get_tree().get_nodes_in_group("combatants")
	var closest_target: CharacterBody3D = null
	var min_distance: float = INF
	
	for c in all_combatants:
		if c == self or c.health <= 0:
			continue
			
		if team_id > 0 and c.team_id == team_id:
			continue
			
		var dist = global_position.distance_to(c.global_position)
		if dist < min_distance:
			min_distance = dist
			closest_target = c
			
	return closest_target

# --- SYSTEME DE DEGATS ---
func take_damage(amount: int, attacker: Node3D = null) -> void:
	if health <= 0: return 
	health -= amount

	if current_state == State.PATROL or current_state == State.SEARCH:
		current_state = State.SEARCH
		current_target = _find_closest_valid_target()
		if current_target:
			nav_agent.target_position = current_target.global_position
			wait_timer = wait_time

	if health <= 0:
		# TODO : Déclencher le ragdoll ou l'animation de mort
		emit_signal("killed", self, attacker)
		_respawn()

# --- SYSTEME DE RESPAWN ---
func _respawn() -> void:
	print(name, " est mort ! Recherche d'un point de réapparition...")
	
	# FIX : Les autres bots oublient immédiatement ce bot dès qu'il meurt
	for c in get_tree().get_nodes_in_group("combatants"):
		if c != self and c.get("current_target") == self:
			c.current_target = null
			c.current_state = State.SEARCH
			
	health = 100
	current_state = State.PATROL
	current_target = null
	velocity = Vector3.ZERO 
	
	var spawn_points = get_tree().get_nodes_in_group("enemy_spawns")
	
	if spawn_points.size() > 0:
		var random_spawn = spawn_points.pick_random() as Marker3D
		global_position = random_spawn.global_position
		global_rotation.y = random_spawn.global_rotation.y
		print(name, " a réapparu au point : ", random_spawn.name)
	else:
		global_position = Vector3(randf_range(-10.0, 10.0), 1.0, randf_range(-10.0, 10.0))
		print("ATTENTION : Aucun point 'enemy_spawns'. Spawn aléatoire d'urgence.")
		
	var safe_spawn = NavigationServer3D.map_get_closest_point(nav_agent.get_navigation_map(), global_position)
	global_position = safe_spawn
	
	nav_agent.target_position = global_position
	_set_random_patrol_point()

func _smooth_look_at(direction: Vector3, delta: float) -> void:
	if direction != Vector3.ZERO:
		var target_angle = atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, delta * rotation_speed)

func _setup_team_indicator() -> void:
	var player_node = get_tree().get_first_node_in_group("player")
	if not player_node:
		team_indicator.hide()
		return

	# Si on est en Mêlée Générale (0), tout le monde est une cible (Rouge)
	if team_id == 0:
		team_indicator.modulate = Color(1.0, 0.0, 0.0) # Rouge vif
		
	# S'il y a des équipes, on compare notre ID avec celui du joueur
	elif player_node.get("team_id") != null:
		if team_id == player_node.team_id:
			team_indicator.modulate = Color(0.0, 1.0, 0.0) # Vert vif (Allié)
		else:
			team_indicator.modulate = Color(1.0, 0.0, 0.0) # Rouge vif (Ennemi)
			
func _update_animations() -> void:
	# On calcule la vitesse de déplacement actuelle sur un plan 2D (sans la gravité)
	var horizontal_velocity = Vector2(velocity.x, velocity.z)
	var current_speed = horizontal_velocity.length()

	# On obtient un pourcentage entre 0.0 et 1.0 par rapport à la vitesse max
	var speed_percent = current_speed / speed

	# TODO quand tu auras un AnimationTree :
	# animation_tree.set("parameters/BlendSpace1D/blend_position", speed_percent)
