extends Node
class_name MatchManager

enum GameMode { FREE_FOR_ALL, TEAM_DEATHMATCH, DOMINATION }

@export_category("Configuration du Match")
@export var current_mode: GameMode = GameMode.FREE_FOR_ALL
@export var score_to_win: int = 15
@export var enemy_scene: PackedScene # <--- GLISSE TON ENEMY.TSCN ICI

# Dictionnaires pour les scores
var individual_scores: Dictionary = {}
var team_scores: Dictionary = {1: 0, 2: 0}

# UI autogénérée
var score_label: Label
var killfeed_label: Label

var player: CharacterBody3D = null

func _ready() -> void:
	_create_match_ui()
	
	# 1. Trouver le joueur présent sur la map
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if not player:
		print("ATTENTION : Aucun joueur trouvé sur la scène !")
		return
		
	# 2. Configurer la partie et spawner les bots
	_setup_game_mode()
	
	# 3. Initialiser l'affichage des scores
	_update_score_display()

func _setup_game_mode() -> void:
	# Récupération de TOUS les points de spawn disponibles sur la carte
	var spawn_points = get_tree().get_nodes_in_group("player_spawns") + get_tree().get_nodes_in_group("enemy_spawns")
	if spawn_points.is_empty():
		print("ATTENTION : Aucun SpawnPoint trouvé sur la map !")
		return
		
	# On mélange les points de spawn pour que les positions soient aléatoires à chaque lancement
	spawn_points.shuffle()
	
	# Positionner le joueur sur le premier point de spawn de la liste
	player.global_position = spawn_points[0].global_position
	player.global_rotation.y = spawn_points[0].global_rotation.y
	
	match current_mode:
		GameMode.FREE_FOR_ALL:
			# --- CONFIGURATION MÊLÉE GÉNÉRALE (10 Joueurs : Toi + 9 Bots) ---
			player.team_id = 0
			_register_combatant(player)
			
			# Faire apparaître 9 Bots (du point index 1 au point index 9)
			for i in range(1, 10):
				var spawn_pos = _get_safe_spawn_position(spawn_points, i)
				_spawn_bot("Bot_" + str(i), 0, spawn_pos)
				
		GameMode.TEAM_DEATHMATCH:
			# --- CONFIGURATION MATCH À MORT (2 Équipes de 5) ---
			# Équipe 1 : Toi + 4 Bots Alliés
			player.team_id = 1
			player.name = "Joueur (T1)"
			_register_combatant(player)
			
			# 4 Bots Alliés (Team 1)
			for i in range(1, 5):
				var spawn_pos = _get_safe_spawn_position(spawn_points, i)
				_spawn_bot("Allié_" + str(i), 1, spawn_pos)
				
			# 5 Bots Ennemis (Team 2)
			for i in range(5, 10):
				var spawn_pos = _get_safe_spawn_position(spawn_points, i)
				_spawn_bot("Ennemi_" + str(i - 4), 2, spawn_pos)

func _get_safe_spawn_position(spawn_points: Array, index: int) -> Transform3D:
	# On boucle sur la liste des points dispos
	var point = spawn_points[index % spawn_points.size()]
	var safe_transform = point.global_transform

	# FIX ANTI-EXPLOSION : 
	# On décale la position d'apparition de 1.5m sur les côtés et 1m en hauteur
	# pour que les bots tombent sur le sol sans se coincer dans le sol ni fusionner
	safe_transform.origin += Vector3(randf_range(-1.5, 1.5), 1.0, randf_range(-1.5, 1.5))

	return safe_transform

func _spawn_bot(bot_name: String, bot_team: int, spawn_transform: Transform3D) -> void:
	if not enemy_scene:
		print("Erreur : enemy_scene n'est pas assignée dans l'inspecteur du MatchManager")
		return
		
	var bot = enemy_scene.instantiate() as CharacterBody3D
	bot.name = bot_name
	bot.team_id = bot_team
	
	# 1. On configure sa position AVANT de l'ajouter à la scène (c'est plus propre)
	bot.global_transform = spawn_transform
	
	# 2. FIX : On demande à Godot de l'ajouter en différé (dès que l'arbre est déverrouillé)
	get_parent().call_deferred("add_child", bot)
	
	# 3. Enregistrement immédiat dans le système de score et de signaux
	_register_combatant(bot)

func _register_combatant(combatant: Node) -> void:
	individual_scores[combatant.name] = 0
	if not combatant.is_connected("killed", Callable(self, "_on_combatant_killed")):
		combatant.connect("killed", Callable(self, "_on_combatant_killed"))

func _on_combatant_killed(victim: Node, killer: Node) -> void:
	if not killer or victim == killer: return
	
	killfeed_label.text = killer.name + " a éliminé " + victim.name
	var t = get_tree().create_timer(3.0)
	t.connect("timeout", Callable(self, "_clear_killfeed"))
	
	match current_mode:
		GameMode.FREE_FOR_ALL:
			individual_scores[killer.name] += 1
			if individual_scores[killer.name] >= score_to_win:
				_end_match(killer.name + " GANHE LA MÊLÉE GÉNÉRALE !")
				
		GameMode.TEAM_DEATHMATCH:
			if killer.get("team_id") != null:
				var t_id = killer.team_id
				if team_scores.has(t_id):
					team_scores[t_id] += 1
					if team_scores[t_id] >= score_to_win:
						var win_team = "L'ÉQUIPE ALLIÉE (T1)" if t_id == 1 else "L'ÉQUIPE ENNEMIE (T2)"
						_end_match(win_team + " REMPORTE LE MATCH !")
						
	_update_score_display()

func _create_match_ui() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	score_label = Label.new()
	score_label.position = Vector2(20, 20)
	score_label.add_theme_font_size_override("font_size", 18)
	canvas.add_child(score_label)
	
	killfeed_label = Label.new()
	killfeed_label.position = Vector2(20, 260)
	killfeed_label.add_theme_font_size_override("font_size", 16)
	killfeed_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	canvas.add_child(killfeed_label)

func _clear_killfeed() -> void:
	killfeed_label.text = ""

func _update_score_display() -> void:
	if current_mode == GameMode.FREE_FOR_ALL:
		var txt = "--- TABLEAU DES SCORES (Mêlée Générale) ---\n"
		for p in individual_scores:
			txt += p + " : " + str(individual_scores[p]) + " kills\n"
		score_label.text = txt
		
	elif current_mode == GameMode.TEAM_DEATHMATCH:
		score_label.text = "--- SCORES D'ÉQUIPE (Match à Mort) ---\nAlliés (Équipe 1) : " + str(team_scores[1]) + " / " + str(score_to_win) + "\nEnnemis (Équipe 2) : " + str(team_scores[2]) + " / " + str(score_to_win)

func _end_match(winner_text: String) -> void:
	score_label.text = "!!! FIN DE LA PARTIE !!!\n" + winner_text
	score_label.add_theme_color_override("font_color", Color(0, 1, 0))
