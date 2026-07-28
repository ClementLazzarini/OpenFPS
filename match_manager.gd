extends Node
class_name MatchManager

enum GameMode { FREE_FOR_ALL, TEAM_DEATHMATCH, DOMINATION }

@export_category("Configuration du Match")
@export var current_mode: GameMode = GameMode.FREE_FOR_ALL
@export var score_to_win: int = 15 # (Tu pourras monter ça à 100 pour la Domination !)
@export var enemy_scene: PackedScene 

@export var end_screen_scene: PackedScene
var ui_canvas: CanvasLayer

# Dictionnaires pour les scores
var individual_scores: Dictionary = {}
var team_scores: Dictionary = {1: 0, 2: 0}

# UI autogénérée
var score_label: Label
var killfeed_label: Label

var player: CharacterBody3D = null
var domination_timer: float = 0.0 # Chrono pour compter les points des zones

func _ready() -> void:
	await get_tree().process_frame
	_create_match_ui()
	
	current_mode = Global.selected_mode as GameMode
	
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if not player:
		print("ATTENTION : Aucun joueur trouvé sur la scène !")
		return
		
	_setup_game_mode()
	_update_score_display()

# --- BOUCLE POUR LA DOMINATION ---
func _process(delta: float) -> void:
	if current_mode == GameMode.DOMINATION:
		domination_timer += delta
		if domination_timer >= 1.0: # Toutes les 1 seconde
			domination_timer = 0.0
			_tick_domination_scores()

func _tick_domination_scores() -> void:
	# On récupère toutes les zones de la carte
	var zones = get_tree().get_nodes_in_group("capture_zones")
	
	for zone in zones:
		# Si la zone appartient à l'équipe 1 ou 2, on lui donne +1 point
		if zone.get("current_owner") != null and zone.current_owner > 0:
			team_scores[zone.current_owner] += 1
			
	# Vérification de la victoire
	if team_scores[1] >= score_to_win:
		_end_match("L'ÉQUIPE ALLIÉE REMPORTE LA DOMINATION !")
	elif team_scores[2] >= score_to_win:
		_end_match("L'ÉQUIPE ENNEMIE REMPORTE LA DOMINATION !")
		
	_update_score_display()

func _setup_game_mode() -> void:
	if current_mode != GameMode.DOMINATION:
		var zones = get_tree().get_nodes_in_group("capture_zones")
		for zone in zones:
			zone.queue_free()
	var spawn_points = get_tree().get_nodes_in_group("player_spawns") + get_tree().get_nodes_in_group("enemy_spawns")
	if spawn_points.is_empty():
		print("ATTENTION : Aucun SpawnPoint trouvé sur la map !")
		return
		
	spawn_points.shuffle()
	
	player.global_position = spawn_points[0].global_position
	player.global_rotation.y = spawn_points[0].global_rotation.y
	
	match current_mode:
		GameMode.FREE_FOR_ALL:
			player.team_id = 0
			_register_combatant(player)
			for i in range(1, 10):
				var spawn_pos = _get_safe_spawn_position(spawn_points, i)
				_spawn_bot("Bot_" + str(i), 0, spawn_pos)
				
		# FIX : On regroupe TDM et Domination car les équipes sont les mêmes !
		GameMode.TEAM_DEATHMATCH, GameMode.DOMINATION:
			player.team_id = 1
			player.name = "Joueur (T1)"
			_register_combatant(player)
			
			for i in range(1, 5):
				var spawn_pos = _get_safe_spawn_position(spawn_points, i)
				_spawn_bot("Allié_" + str(i), 1, spawn_pos)
				
			for i in range(5, 10):
				var spawn_pos = _get_safe_spawn_position(spawn_points, i)
				_spawn_bot("Ennemi_" + str(i - 4), 2, spawn_pos)

func _get_safe_spawn_position(spawn_points: Array, index: int) -> Transform3D:
	var point = spawn_points[index % spawn_points.size()]
	var safe_transform = point.global_transform
	safe_transform.origin += Vector3(randf_range(-1.5, 1.5), 1.0, randf_range(-1.5, 1.5))
	return safe_transform

func _spawn_bot(bot_name: String, bot_team: int, spawn_transform: Transform3D) -> void:
	if not enemy_scene:
		print("Erreur : enemy_scene n'est pas assignée dans l'inspecteur du MatchManager")
		return
		
	var bot = enemy_scene.instantiate() as CharacterBody3D
	bot.name = bot_name
	bot.team_id = bot_team
	bot.global_transform = spawn_transform
	get_parent().call_deferred("add_child", bot)
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
				_end_match(killer.name + " GAGNE LA MÊLÉE GÉNÉRALE !")
				
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
	ui_canvas = CanvasLayer.new()
	add_child(ui_canvas)
	
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
		
	# FIX : On affiche la même interface d'équipes pour TDM et Domination
	elif current_mode == GameMode.TEAM_DEATHMATCH or current_mode == GameMode.DOMINATION:
		var mode_name = "Match à Mort" if current_mode == GameMode.TEAM_DEATHMATCH else "Domination"
		score_label.text = "--- SCORES (" + mode_name + ") ---\nAlliés (Équipe 1) : " + str(team_scores[1]) + " / " + str(score_to_win) + "\nEnnemis (Équipe 2) : " + str(team_scores[2]) + " / " + str(score_to_win)

func _end_match(winner_text: String) -> void:
	# 1. On fige l'action de tous les bots et joueurs
	get_tree().paused = true

	# 2. On cache l'interface de combat (Optionnel mais plus propre)
	score_label.hide()
	killfeed_label.hide()

	# 3. On prépare le texte des scores
	var final_scores = ""
	if current_mode == GameMode.FREE_FOR_ALL:
		for p in individual_scores:
			final_scores += p + " : " + str(individual_scores[p]) + " kills\n"
	else:
		final_scores = "Alliés (Équipe 1) : " + str(team_scores[1]) + "\nEnnemis (Équipe 2) : " + str(team_scores[2])

	# 4. On fait apparaître notre bel écran de fin
	if end_screen_scene:
		var end_screen = end_screen_scene.instantiate()
		ui_canvas.add_child(end_screen)
		end_screen.setup_screen(winner_text, final_scores)
	else:
		print("ERREUR : end_screen_scene n'est pas assignée dans le MatchManager !")
