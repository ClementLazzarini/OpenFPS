extends CharacterBody3D
signal killed(victim_node, killer_node)

# --- PARAMÈTRES EXPORTÉS ---
@export_category("Déplacements")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var acceleration: float = 12.0
@export var friction: float = 15.0
@export var air_control: float = 3.0
@export var jump_velocity: float = 10
@export var gravity: float = 24

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
var stand_head_y: float 
var health: int = 100
var team_id: int = 0

@export_category("Head Bobbing")
@export var bob_frequency: float = 2.0
@export var bob_amplitude: float = 0.08
var t_bob: float = 0.0 # chronomètre pour calculer le balancement

@export_category("Arme & Recul")
@export var recoil_rotation_x: float = 0.1 # L'arme se lève
@export var recoil_position_z: float = 0.1 # L'arme recule vers le joueur
@export var recoil_recovery_speed: float = 10.0 # Vitesse de retour à la normale
@export var max_ammo: int = 15 # Taille du chargeur du 9mm
@export var reload_time: float = 1.5 # Durée du rechargement en secondes

# Variables d'état des munitions
var current_ammo: int = max_ammo
var is_reloading: bool = false
var reload_timer: float = 0.0

@onready var weapon: Node3D = $Head/Camera3D/Weapon
@onready var shoot_sound: AudioStreamPlayer = $Head/Camera3D/ShootSound 
@onready var reload_sound: AudioStreamPlayer = $Head/Camera3D/ReloadSound

# Position et rotation initiales de l'arme (pour la ramener à sa place)
var weapon_default_pos: Vector3
var weapon_default_rot: Vector3

# --- RÉFÉRENCES AUX NŒUDS ---
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_raycast: RayCast3D = $Head/Camera3D/WeaponRayCast

# --- RÉFÉRENCES HUD ---
@onready var health_bar: ProgressBar = $HUD/Control/HealthBar
@onready var ammo_label: Label = $HUD/Control/AmmoLabel

# --- VARIABLES D'ÉTAT ---
var current_speed: float = walk_speed

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	add_to_group("player")
	add_to_group("combatants")
	weapon_default_pos = weapon.position
	weapon_default_rot = weapon.rotation
	stand_head_y = head.position.y
	health_bar.max_value = 100
	health_bar.value = health
	_update_ammo_display()

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
	
# --- GESTION DU RECHARGEMENT ---
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			current_ammo = max_ammo
			is_reloading = false
			_update_ammo_display()
			print("Arme rechargée !")

	# Lancement manuel du rechargement
	if Input.is_action_just_pressed("reload") and current_ammo < max_ammo and not is_reloading:
		_start_reload()

	# --- SYSTÈME DE TIR (9mm Semi-Auto) ---
	if Input.is_action_just_pressed("shoot") and not is_reloading:
		if current_ammo > 0:
			_shoot()
		else:
			# Essayer de tirer à vide déclenche un rechargement automatique
			_start_reload()

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
	# 1. Consommer la balle et mettre à jour l'UI
	current_ammo -= 1
	_update_ammo_display()

	# 2. Jouer le son
	if shoot_sound.stream:
		shoot_sound.play()
		
	# 3. Appliquer le recul visuel
	weapon.position.z += recoil_position_z
	weapon.rotation.x += recoil_rotation_x

	# 4. Logique Hitscan
	weapon_raycast.force_raycast_update()
	if weapon_raycast.is_colliding():
		var target = weapon_raycast.get_collider()
		var hit_point = weapon_raycast.get_collision_point()
		var hit_normal = weapon_raycast.get_collision_normal()
		# --- DÉTECTION DE LA CIBLE ---
		var is_enemy: bool = target.is_in_group("enemy")
		# --- APPEL DE L'EFFET ---
		_create_impact_particles(hit_point, hit_normal, is_enemy)
		
		if target.has_method("take_damage"):
			target.take_damage(20, self)

func _start_reload() -> void:
	is_reloading = true
	reload_timer = reload_time
	print("Rechargement en cours...")

	if reload_sound.stream:
		reload_sound.play()
		
	# Petite animation visuelle basique : on baisse l'arme
	weapon.rotation.x = deg_to_rad(-45)

func _update_ammo_display() -> void:
	ammo_label.text = str(current_ammo) + " / " + str(max_ammo)

func take_damage(amount: int, attacker: Node3D = null) -> void:
	if health <= 0: return 

	health -= amount
	health_bar.value = health

	if health <= 0:
		emit_signal("killed", self, attacker)
		_respawn()

func _create_impact_particles(hit_point: Vector3, hit_normal: Vector3, is_enemy: bool = false) -> void:
	var particles := GPUParticles3D.new()
	get_parent().add_child(particles)

	particles.global_position = hit_point
	if hit_normal != Vector3.UP and hit_normal != Vector3.DOWN:
		particles.look_at(hit_point + hit_normal, Vector3.UP)
		
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.FORWARD
	material.spread = 45.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 6.0
	material.gravity = Vector3(0, -9.8, 0)
	material.scale_min = 0.05
	material.scale_max = 0.15

	var box_mesh := BoxMesh.new()
	var particle_material := StandardMaterial3D.new()

	# --- VARIATION DE COULEUR SELON LA CIBLE ---
	if is_enemy:
		particle_material.albedo_color = Color(0.7, 0.0, 0.0) # Rouge sombre / Sang
		particle_material.emission_enabled = true
		particle_material.emission = Color(0.4, 0.0, 0.0) # Léger éclat rouge
		particles.amount = 12 # Un poil plus de particules pour marquer l'impact
	else:
		particle_material.albedo_color = Color(1.0, 0.8, 0.3) # Orange étincelle classique
		particle_material.emission_enabled = true
		particle_material.emission = Color(1.0, 0.6, 0.1)
		particles.amount = 8
		
	box_mesh.material = particle_material
	box_mesh.size = Vector3(0.1, 0.1, 0.1)

	particles.process_material = material
	particles.draw_pass_1 = box_mesh
	particles.one_shot = true
	particles.explosiveness = 1.0

	particles.emitting = true
	await get_tree().create_timer(1.0).timeout
	particles.queue_free()


func _respawn() -> void:
	print("Le joueur est mort ! Recherche d'un point de réapparition...")

	# 1. Reset des statistiques du joueur
	health = 100
	health_bar.value = health
	current_ammo = max_ammo
	_update_ammo_display()
	is_sliding = false

	# 2. Recherche d'un point de spawn aléatoire sur Shipment
	var spawn_points = get_tree().get_nodes_in_group("player_spawns")

	if spawn_points.size() > 0:
		var random_spawn = spawn_points.pick_random() as Marker3D
		# Téléportation instantanée du joueur au point choisi
		global_position = random_spawn.global_position
		# Optionnel : aligner la rotation du joueur sur celle du spawn
		global_rotation.y = random_spawn.global_rotation.y
		print("Réapparition réussie au point : ", random_spawn.name)
	else:
		# Sécurité si tu as oublié de configurer le groupe sur ta carte
		global_position = Vector3(0, 2, 0)
		print("ATTENTION : Aucun point dans le groupe 'player_spawns'. Retour au centre de la carte.")
