extends Marker3D
class_name SpawnPoint # Permet à Godot de reconnaître ce type de nœud partout

# On définit les différents types de spawn possibles pour tes futurs modes de jeu
enum SpawnType { PLAYER_SOLO, ENEMY, TEAM_A, TEAM_B }

@export_category("Configuration du Spawn")
@export var type: SpawnType = SpawnType.PLAYER_SOLO

func _ready() -> void:
	# L'avantage absolu : le nœud gère lui-même son enregistrement
	# Plus aucun risque d'oublier de configurer un groupe dans l'éditeur !
	match type:
		SpawnType.PLAYER_SOLO:
			add_to_group("player_spawns")
		SpawnType.ENEMY:
			add_to_group("enemy_spawns")
		SpawnType.TEAM_A:
			add_to_group("team_a_spawns")
		SpawnType.TEAM_B:
			add_to_group("team_b_spawns")
