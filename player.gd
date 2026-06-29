extends CharacterBody3D

# --- PARAMÈTRES EXPORTÉS ---
@export_category("Déplacements")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var acceleration: float = 12.0
@export var friction: float = 15.0
@export var air_control: float = 3.0
@export var jump_velocity: float = 6
@export var gravity: float = 9.8

@export_category("Caméra & Vue")
@export var mouse_sensitivity: float = 0.002
@export var camera_tilt_limit: float = 89.0 

@export_category("Game Feel")
@export var normal_fov: float = 80.0
@export var sprint_fov: float = 90.0
@export var fov_transition_speed: float = 8.0

@export_category("Glissade (Slide)")
@export var slide_initial_speed: float = 18.0 # Le "boost" au moment où on lance la glissade
@export var slide_friction: float = 3.0 # Ralentissement pendant la glissade
@export var slide_duration: float = 0.8 # Temps max de la glissade
@export var crouch_head_y: float = 0.8 # Hauteur de la caméra accroupi/en glissade

# Variables d'état interne
var is_sliding: bool = false
var slide_timer: float = 0.0
var slide_dir: Vector3 = Vector3.ZERO
var stand_head_y: float # Pour mémoriser la hauteur normale de la tête

@export_category("Head Bobbing")
@export var bob_frequency: float = 2.0
@export var bob_amplitude: float = 0.08
var t_bob: float = 0.0 # chronomètre pour calculer le balancement

@export_category("Arme & Recul")
@export var recoil_rotation_x: float = 0.1 # L'arme se lève
@export var recoil_position_z: float = 0.1 # L'arme recule vers le joueur
@export var recoil_recovery_speed: float = 10.0 # Vitesse de retour à la normale

@onready var weapon: Node3D = $Head/Camera3D/Weapon
@onready var shoot_sound: AudioStreamPlayer = $Head/Camera3D/ShootSound 

# Position et rotation initiales de l'arme (pour la ramener à sa place)
var weapon_default_pos: Vector3
var weapon_default_rot: Vector3

# --- RÉFÉRENCES AUX NŒUDS ---
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_raycast: RayCast3D = $Head/Camera3D/WeaponRayCast

# --- VARIABLES D'ÉTAT ---
var current_speed: float = walk_speed

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	weapon_default_pos = weapon.position
	weapon_default_rot = weapon.rotation
	stand_head_y = head.position.y

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

	# --- GESTION DE LA HAUTEUR (ACCROUPISSEMENT & GLISSADE) ---
	# Baisse la caméra doucement si on maintient crouch OU si on est en pleine glissade
	var target_head_y = crouch_head_y if (Input.is_action_pressed("crouch") or is_sliding) else stand_head_y
	head.position.y = lerp(head.position.y, target_head_y, delta * 10.0)

	# --- SAUT ---
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		is_sliding = false # Le saut annule (cut) immédiatement la glissade

	# --- SPRINT ---
	# On ne peut sprinter que si on ne glisse pas
	if Input.is_action_pressed("sprint") and is_on_floor() and not is_sliding:
		current_speed = sprint_speed
	else:
		current_speed = walk_speed

	# --- SYSTÈME DE TIR (9mm Semi-Auto) ---
	if Input.is_action_just_pressed("shoot"):
		_shoot()

	# --- VECTEURS DE DIRECTION ---
	# 1. Récupérer le vecteur directionnel basé sur les touches pressées
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	# 2. Convertir ce vecteur 2D en une direction 3D en fonction d'où regarde le joueur
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# --- DÉCLENCHEMENT DE LA GLISSADE ---
	# Conditions : Appui sur crouch + Vitesse de sprint + Au sol + En mouvement + Pas déjà en glissade
	if Input.is_action_just_pressed("crouch") and current_speed == sprint_speed and is_on_floor() and direction != Vector3.ZERO and not is_sliding:
		is_sliding = true
		slide_timer = slide_duration
		slide_dir = direction # On verrouille la direction de l'élan initial

		# Le gros boost de vitesse percutant (façon MW2019)
		velocity.x = slide_dir.x * slide_initial_speed
		velocity.z = slide_dir.z * slide_initial_speed

	# --- DÉPLACEMENTS (GAME FEEL) ---
	if is_sliding:
		slide_timer -= delta

		# Ralentissement progressif avec la friction de glissade
		velocity.x = lerp(velocity.x, 0.0, delta * slide_friction)
		velocity.z = lerp(velocity.z, 0.0, delta * slide_friction)

		# CONDITIONS D'ANNULATION (CUT) : 
		# Temps écoulé, touche relâchée, ou vitesse trop faible
		if slide_timer <= 0 or not Input.is_action_pressed("crouch") or velocity.length() < walk_speed:
			is_sliding = false
	else:
		# Déplacements normaux
		if is_on_floor():
			if direction != Vector3.ZERO:
				# En mouvement : Accélération progressive
				velocity.x = lerp(velocity.x, direction.x * current_speed, delta * acceleration)
				velocity.z = lerp(velocity.z, direction.z * current_speed, delta * acceleration)
			else:
				# À l'arrêt : Friction
				velocity.x = lerp(velocity.x, 0.0, delta * friction)
				velocity.z = lerp(velocity.z, 0.0, delta * friction)
		else:
			# En l'air : Élan conservé avec contrôle réduit
			if direction != Vector3.ZERO:
				velocity.x = lerp(velocity.x, direction.x * current_speed, delta * air_control)
				velocity.z = lerp(velocity.z, direction.z * current_speed, delta * air_control)

	# --- FOV DYNAMIQUE (SENSATION DE VITESSE) ---
	var target_fov: float
	# J'ai ajouté 'or is_sliding' ici pour que le FOV reste large pendant la glissade !
	if (Input.is_action_pressed("sprint") or is_sliding) and direction != Vector3.ZERO and is_on_floor():
		target_fov = sprint_fov
	else:
		target_fov = normal_fov
		
	camera.fov = lerp(camera.fov, target_fov, delta * fov_transition_speed)

	# --- HEAD BOBBING ---
	# Désactivé pendant la glissade pour un effet "sur des rails"
	if is_on_floor() and velocity.length() > 0.5 and not is_sliding:
		t_bob += delta * velocity.length() * float(is_on_floor())
		camera.position = _headbob(t_bob)
	else:
		camera.position = camera.position.lerp(Vector3.ZERO, delta * 5.0)

	# --- RÉCUPÉRATION DU RECUL ---
	weapon.position = weapon.position.lerp(weapon_default_pos, delta * recoil_recovery_speed)
	weapon.rotation = weapon.rotation.lerp(weapon_default_rot, delta * recoil_recovery_speed)

	# --- EXÉCUTION MOTEUR PHYSIQUE ---
	move_and_slide()

func _headbob(time: float) -> Vector3:
		var pos = Vector3.ZERO
		pos.y = sin(time * bob_frequency) * bob_amplitude
		pos.x = cos(time * bob_frequency / 2.0) * bob_amplitude
		return pos
		
func _shoot() -> void:
	# 1. Jouer le son
	if shoot_sound.stream:
		shoot_sound.play()
		
	# 2. Appliquer le recul visuel (on ajoute un à-coup brutal)
	weapon.position.z += recoil_position_z
	weapon.rotation.x += recoil_rotation_x

	# 3. Logique Hitscan
	weapon_raycast.force_raycast_update()

	if weapon_raycast.is_colliding():
		var target = weapon_raycast.get_collider()
		var hit_point = weapon_raycast.get_collision_point()

		print("Tir réussi ! Cible touchée : ", target.name)

		if target.has_method("take_damage"):
			target.take_damage(20)
