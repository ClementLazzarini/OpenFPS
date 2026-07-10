extends Camera3D

@export var height: float = 25.0 # Hauteur de la vue du dessus

var target: Node3D = null

func _ready() -> void:
	await get_tree().process_frame
	# 1. On force le SubViewport à partager le même monde 3D
	var main_viewport = get_tree().root.get_viewport()
	get_parent().world_3d = main_viewport.world_3d
	
	# 2. FIX : Le groupe est "player" avec un 'p' minuscule !
	target = get_tree().get_first_node_in_group("player")

	# Petit message d'alerte au cas où il ne le trouve pas
	if not target:
		print("ERREUR MINIMAP : Impossible de trouver le joueur. Vérifie les groupes !")

	# 3. On force la caméra à regarder pile vers le sol
	rotation_degrees = Vector3(-90, 0, 0)

func _physics_process(_delta: float) -> void:
	if target and is_instance_valid(target):
		# On copie la position X et Z du joueur en temps réel
		global_position.x = target.global_position.x
		global_position.z = target.global_position.z
		global_position.y = target.global_position.y + height
