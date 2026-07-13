extends Area3D
class_name CaptureZone

@export var zone_name: String = "A"
@export var capture_time: float = 5.0 # Temps en secondes pour capturer la zone

var current_owner: int = 0 # 0 = Neutre, 1 = Équipe 1 (Alliés), 2 = Équipe 2 (Ennemis)
var capture_progress: float = 0.0
var capturing_team: int = 0

# Compteurs de présence
var occupants_team_1: int = 0
var occupants_team_2: int = 0

@onready var label: Label3D = $Label3D
@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	add_to_group("capture_zones")
	# On connecte automatiquement les signaux d'entrée/sortie de zone
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# On configure l'apparence de base (Neutre)
	_update_visuals()

# --- DÉTECTION DES JOUEURS / BOTS ---
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("combatants") and body.get("team_id") != null:
		if body.team_id == 1: occupants_team_1 += 1
		elif body.team_id == 2: occupants_team_2 += 1

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("combatants") and body.get("team_id") != null:
		if body.team_id == 1: occupants_team_1 -= 1
		elif body.team_id == 2: occupants_team_2 -= 1

# --- LOGIQUE DE CAPTURE ---
# --- LOGIQUE DE CAPTURE ---
func _process(delta: float) -> void:
	# 1. Déterminer qui a la supériorité numérique
	var majority_team = 0
	if occupants_team_1 > occupants_team_2:
		majority_team = 1
	elif occupants_team_2 > occupants_team_1:
		majority_team = 2

	# 2. Gestion précise de la jauge
	if majority_team != 0:
		if current_owner == majority_team:
			# L'équipe possède déjà la zone : on verrouille à 100%
			capture_progress = capture_time 
		else:
			# La majorité est différente de l'équipe qui est en train de capturer
			if capturing_team == majority_team:
				# L'équipe pousse sa propre jauge
				capture_progress += delta
				if capture_progress >= capture_time:
					capture_progress = capture_time
					current_owner = capturing_team
					_update_visuals()
			else:
				# L'équipe vide la jauge de l'autre équipe
				capture_progress -= delta
				if capture_progress <= 0:
					# La jauge est vide : la zone redevient NEUTRE !
					capture_progress = 0.0
					capturing_team = majority_team
					current_owner = 0
					_update_visuals()

	# 3. Mise à jour propre de l'interface texte
	var percent = int((capture_progress / capture_time) * 100)
	label.text = "ZONE " + zone_name + "\n" + str(percent) + "%"

# --- MISE À JOUR DES COULEURS ---
func _update_visuals() -> void:
	var color = Color(0.8, 0.8, 0.8) # Gris (Neutre par défaut)
	
	if current_owner == 1:
		color = Color(0.0, 1.0, 0.0) # Vert (Alliés)
	elif current_owner == 2:
		color = Color(1.0, 0.0, 0.0) # Rouge (Ennemis)
		
	label.modulate = color
	
	# On change la couleur du disque au sol s'il a un material
	if mesh.mesh and mesh.mesh.surface_get_material(0):
		var mat = mesh.mesh.surface_get_material(0)
		if mat is StandardMaterial3D:
			mat.albedo_color = color
			mat.albedo_color.a = 0.3 # Garde la transparence
