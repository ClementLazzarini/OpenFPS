extends CharacterBody3D

# --- PARAMÈTRES EXPORTÉS ---
# Le @export_category permet d'organiser proprement l'inspecteur Godot
@export_category("Déplacements")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var acceleration: float = 12.0
@export var friction: float = 15.0
@export var air_control: float = 3.0 # Moins de contrôle en l'air pour plus de réalisme
@export var jump_velocity: float = 4.5
@export var gravity: float = 9.8

@export_category("Caméra & Vue")
@export var mouse_sensitivity: float = 0.002
@export var camera_tilt_limit: float = 89.0 # Empêche de faire un 360 avec le cou

@export_category("Game Feel")
@export var normal_fov: float = 75.0
@export var sprint_fov: float = 90.0
@export var fov_transition_speed: float = 8.0

@export_category("Head Bobbing")
@export var bob_frequency: float = 2.0
@export var bob_amplitude: float = 0.08
var t_bob: float = 0.0 # Un chronomètre interne pour calculer le balancement

# --- RÉFÉRENCES AUX NŒUDS ---
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
# @onready var weapon_raycast: RayCast3D = $Head/Camera3D/WeaponRayCast # Décommenter plus tard

# --- VARIABLES D'ÉTAT ---
var current_speed: float = walk_speed

func _ready() -> void:
	# Capture la souris au lancement du jeu pour contrôler la caméra
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	# --- GESTION DE LA SOURIS (ROTATION CAMÉRA) ---
	if event is InputEventMouseMotion:
		# Rotation horizontale du joueur entier (gauche/droite)
		rotate_y(-event.relative.x * mouse_sensitivity)
		
		# Rotation verticale de la tête uniquement (haut/bas)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		
		# Blocage de la caméra pour ne pas regarder à l'envers
		head.rotation.x = clamp(
			head.rotation.x, 
			deg_to_rad(-camera_tilt_limit), 
			deg_to_rad(camera_tilt_limit)
		)
	
	# Échap pour libérer la souris (très pratique pour tester dans l'éditeur)
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	# --- GRAVITÉ ---
	if not is_on_floor():
		velocity.y -= gravity * delta

	# --- SAUT ---
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# --- SPRINT ---
	if Input.is_action_pressed("sprint") and is_on_floor():
		current_speed = sprint_speed
	else:
		current_speed = walk_speed

	# --- DÉPLACEMENTS (GAME FEEL) ---
	# 1. Récupérer le vecteur directionnel basé sur les touches pressées
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	# 2. Convertir ce vecteur 2D en une direction 3D en fonction d'où regarde le joueur
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# 3. Appliquer la vitesse avec interpolation (lerp) pour l'accélération et la friction
	if is_on_floor():
		if direction != Vector3.ZERO:
			# En mouvement : Accélération progressive (très rapide mais pas instantanée)
			velocity.x = lerp(velocity.x, direction.x * current_speed, delta * acceleration)
			velocity.z = lerp(velocity.z, direction.z * current_speed, delta * acceleration)
		else:
			# À l'arrêt : Friction (glissement léger avant l'arrêt complet)
			velocity.x = lerp(velocity.x, 0.0, delta * friction)
			velocity.z = lerp(velocity.z, 0.0, delta * friction)
	else:
		# En l'air : Le joueur garde son élan, avec un contrôle directionnel fortement réduit
		if direction != Vector3.ZERO:
			velocity.x = lerp(velocity.x, direction.x * current_speed, delta * air_control)
			velocity.z = lerp(velocity.z, direction.z * current_speed, delta * air_control)

	# --- FOV DYNAMIQUE (SENSATION DE VITESSE) ---
	# Si on sprinte ET qu'on bouge, on cible le FOV de sprint, sinon on revient au FOV normal
	var target_fov: float
	if Input.is_action_pressed("sprint") and direction != Vector3.ZERO and is_on_floor():
		target_fov = sprint_fov
	else:
		target_fov = normal_fov
		
	# Interpolation douce de la caméra vers le FOV ciblé
	camera.fov = lerp(camera.fov, target_fov, delta * fov_transition_speed)
	# --- HEAD BOBBING ---
	# Si le joueur touche le sol et qu'il bouge significativement
	if is_on_floor() and velocity.length() > 0.5:
		# On ajoute le temps écoulé, multiplié par la vitesse (pour accélérer le bobbing en sprint)
		t_bob += delta * velocity.length() * float(is_on_floor())
		# On applique la position calculée à la caméra
		camera.position = _headbob(t_bob)
	else:
		# Si on est à l'arrêt ou en l'air, on ramène la caméra à sa position centrale (0, 0, 0)
		camera.position = camera.position.lerp(Vector3.ZERO, delta * 5.0)

	move_and_slide()

func _headbob(time: float) -> Vector3:
		var pos = Vector3.ZERO
		pos.y = sin(time * bob_frequency) * bob_amplitude
		pos.x = cos(time * bob_frequency / 2.0) * bob_amplitude
		return pos
		
