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
@export var view_distance: float = 30.0 # Distance max pour voir une cible
@export var attack_range: float = 15.0 # Distance à laquelle il s'arrête pour tirer
@export var damage: int = 10
@export var fire_rate: float = 0.8 # Temps entre chaque tir

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var aim_raycast: RayCast3D = $AimRayCast
@onready var animation_player: AnimationPlayer = $Soldier/AnimationPlayer

@export_category("Système d'Équipe")
@export var team_id: int = 0 # 0 = Mêlée générale, 1 = Équipe Joueur, 2 = Équipe Ennemi

# Ciblage dynamique & Optimisation
var current_target: CharacterBody3D = null
var scan_timer: float = 0.0
var scan_interval: float = 0.2 # Scan de l'arène 5 fois par seconde (économie CPU)
var is_ready_to_navigate: bool = false
var fire_timer: float = 0.0

func _ready() -> void:
	# --- INSCRIPTION AUTOMATIQUE (Zéro config manuelle dans l'éditeur) ---
	if not is_in_group("enemy"):
		add_to_group("enemy")
	if not is_in_group("combatants"):
		add_to_group("combatants")
		
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

	if not is_ready_to_navigate:
		move_and_slide()
		return

	# Gestion du rechargement du tir
	if fire_timer > 0:
		fire_timer -= delta

	# 1. RECHERCHE DE CIBLE DYNAMIQUE (Par intervalles pour optimiser)
	scan_timer -= delta
	if scan_timer <= 0.0:
		scan_timer = scan_interval
		current_target = _find_closest_valid_target()

	# 2. LOGIQUE DE DÉCISION (MACHINE À ÉTATS MODULAIRE)
	if current_target and is_instance_valid(current_target):
		var has_los = _has_line_of_sight(current_target)
		var distance_to_target = global_position.distance_to(current_target.global_position)

		if has_los:
			# La cible est visible : on met à jour le pathfinding
			nav_agent.target_position = current_target.global_position
			if distance_to_target <= attack_range:
				current_state = State.ATTACK
			else:
				current_state = State.CHASE
		else:
			# Perte de vue : si on la traquait, on bascule en recherche sur sa dernière position
			if current_state == State.CHASE or current_state == State.ATTACK:
				current_state = State.SEARCH
				wait_timer = wait_time
	else:
		# Plus aucune cible valide ou en vie sur la map -> Retour à la patrouille tranquille
		if current_state == State.CHASE or current_state == State.ATTACK:
			current_state = State.PATROL

	# 3. EXÉCUTION DE L'ACTION SELON L'ÉTAT ACTUEL
	match current_state:
		State.PATROL, State.SEARCH:
			_handle_patrol_and_search(delta)
		State.CHASE:
			_move_towards_target(delta)
		State.ATTACK:
			_handle_attack(delta)

	move_and_slide()

# --- MOUVEMENTS ---
func _move_towards_target(delta: float) -> void:
	if nav_agent.is_navigation_finished() or not current_target:
		return
		
	var next_path_position = nav_agent.get_next_path_position()
	var direction = (next_path_position - global_position)
	direction.y = 0
	direction = direction.normalized()

	velocity.x = lerp(velocity.x, direction.x * speed, delta * acceleration)
	velocity.z = lerp(velocity.z, direction.z * speed, delta * acceleration)
	_smooth_look_at(direction, delta)

func _handle_patrol_and_search(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		velocity.x = lerp(velocity.x, 0.0, delta * acceleration)
		velocity.z = lerp(velocity.z, 0.0, delta * acceleration)

		wait_timer -= delta
		if wait_timer <= 0.0:
			_set_random_patrol_point()
			current_state = State.PATROL
		return
		
	var next_path_position = nav_agent.get_next_path_position()
	var direction = (next_path_position - global_position)
	direction.y = 0
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

	if fire_timer <= 0.0:
		_shoot()

func _shoot() -> void:
	fire_timer = fire_rate
	if current_target and is_instance_valid(current_target):
		print(name, " tire sur ", current_target.name)
		if current_target.has_method("take_damage"):
			current_target.take_damage(damage)

# --- VISION TACTIQUE MULTI-CIBLES ---
func _has_line_of_sight(target: Node3D) -> bool:
	if not target or not is_instance_valid(target): return false
	
	var dir_to_target = global_position.direction_to(target.global_position)
	var distance = global_position.distance_to(target.global_position)
	
	if distance > view_distance:
		return false
		
	var forward = -global_transform.basis.z
	if forward.dot(dir_to_target) < cos(deg_to_rad(fov_angle / 2.0)):
		return false
		
	# Vise le torse de la cible (joueur ou autre bot)
	var target_pos = target.global_position + Vector3(0, 1.0, 0)
	aim_raycast.target_position = aim_raycast.to_local(target_pos)
	aim_raycast.force_raycast_update()
	
	if aim_raycast.is_colliding():
		var collider = aim_raycast.get_collider()
		if collider == target:
			return true
			
	return false

# --- SYSTÈME DE SÉLECTION D'ÉQUIPE (FFA / TDM) ---
func _find_closest_valid_target() -> CharacterBody3D:
	var all_combatants = get_tree().get_nodes_in_group("combatants")
	var closest_target: CharacterBody3D = null
	var min_distance: float = INF
	
	for c in all_combatants:
		# On ignore soi-même ou quelqu'un de déjà mort
		if c == self or c.health <= 0:
			continue
			
		# --- RÈGLE FILTRE ALLIANCES ---
		# Si team_id > 0 (Match à mort) : on ignore les coéquipiers
		# Si team_id == 0 (Mêlée générale) : on n'ignore personne
		if team_id > 0 and c.team_id == team_id:
			continue
			
		var dist = global_position.distance_to(c.global_position)
		if dist < min_distance:
			min_distance = dist
			closest_target = c
			
	return closest_target

# --- SYSTEME DE DEGATS & REACTION RE RETOURNEMENT ---
func take_damage(amount: int) -> void:
	if health <= 0: return 
	
	health -= amount
	print(name, " touché ! PV restants : ", health)
	
	# --- AGRÉSSIVITÉ ACCRUE (RIQUET DANS LE DOS) ---
	# Si on se fait tirer dessus en patrouille ou recherche, on force l'analyse
	if current_state == State.PATROL or current_state == State.SEARCH:
		current_state = State.SEARCH
		current_target = _find_closest_valid_target()
		if current_target:
			nav_agent.target_position = current_target.global_position
			wait_timer = wait_time

	if health <= 0:
		_respawn()

# --- SYSTEME DE RESPAWN STANDARDISÉ ---
func _respawn() -> void:
	print(name, " est mort ! Recherche d'un point de réapparition...")
	
	health = 100
	current_state = State.PATROL
	current_target = null
	
	var spawn_points = get_tree().get_nodes_in_group("enemy_spawns")
	
	if spawn_points.size() > 0:
		var random_spawn = spawn_points.pick_random() as Marker3D
		global_position = random_spawn.global_position
		global_rotation.y = random_spawn.global_rotation.y
		print(name, " a réapparu au point : ", random_spawn.name)
	else:
		global_position = Vector3(randf_range(-10.0, 10.0), 1.0, randf_range(-10.0, 10.0))
		print("ATTENTION : Aucun point 'enemy_spawns'. Spawn aléatoire d'urgence.")
		
	_set_random_patrol_point()

func _smooth_look_at(direction: Vector3, delta: float) -> void:
	if direction.length() > 0.1:
		var target_angle = atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, delta * rotation_speed)
