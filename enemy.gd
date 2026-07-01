extends CharacterBody3D

@export_category("Statistiques")
@export var speed: float = 4.0
@export var acceleration: float = 10.0
@export var health: int = 100
@export var gravity: float = 9.8
@export var rotation_speed: float = 10.0 # Vitesse à laquelle l'ennemi pivote

@export_category("Combat")
@export var attack_range: float = 1.5

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var player: Node3D = null
var is_ready_to_navigate: bool = false

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	
	# Configuration cruciale pour éviter les blocages près des obstacles
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = attack_range
	
	# Sécurité Godot 4 : On attend une frame physique pour que le NavMesh soit prêt
	call_deferred("setup_navigation")

func setup_navigation() -> void:
	await get_tree().physics_frame
	is_ready_to_navigate = true

func _physics_process(delta: float) -> void:
	# --- GRAVITÉ ---
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0 # Évite d'accumuler de la gravité négative au sol

	# Si le serveur de navigation n'est pas prêt ou le joueur absent, on ne fait rien
	if not is_ready_to_navigate or not player or not is_instance_valid(player):
		move_and_slide()
		return

	# --- MISE À JOUR DE LA CIBLE ---
	nav_agent.target_position = player.global_position
	
	# --- CALCUL DU MOUVEMENT ---
	if not nav_agent.is_navigation_finished():
		var next_path_position = nav_agent.get_next_path_position()
		# Calcul de la direction uniquement sur le plan horizontal (X et Z)
		var direction = (next_path_position - global_position)
		direction.y = 0
		direction = direction.normalized()
		
		# Application fluide de la vitesse
		velocity.x = lerp(velocity.x, direction.x * speed, delta * acceleration)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * acceleration)
		
		# --- ORIENTATION FLUIDE (Correction du bug de rotation) ---
		if direction.length() > 0.1:
			# Calcule l'angle cible vers lequel l'ennemi doit regarder
			var target_angle = atan2(-direction.x, -direction.z)
			# Aligne progressivement la rotation de l'ennemi
			rotation.y = lerp_angle(rotation.y, target_angle, delta * rotation_speed)
			
	else:
		# Arrivé à portée d'attaque : on freine
		velocity.x = lerp(velocity.x, 0.0, delta * acceleration)
		velocity.z = lerp(velocity.z, 0.0, delta * acceleration)
		_attack()

	# --- EXÉCUTION DE LA PHYSIQUE ---
	move_and_slide()

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		queue_free()

func _attack() -> void:
	# Logique d'attaque à venir
	pass
