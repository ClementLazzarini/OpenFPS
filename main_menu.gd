extends Control

@onready var map_selector: OptionButton = $VBoxContainer/MapSelector
@onready var mode_selector: OptionButton = $VBoxContainer/ModeSelector
@onready var play_button: Button = $VBoxContainer/PlayButton

func _ready() -> void:
	# 1. Remplir le choix des Modes
	mode_selector.add_item("Mêlée Générale", 0)
	mode_selector.add_item("Match à Mort", 1)
	mode_selector.add_item("Domination", 2)
	
	# 2. Remplir le choix des Cartes (Mets les VRAIS chemins de tes scènes ici !)
	map_selector.add_item("Shipment", 0)
	map_selector.set_item_metadata(0, "res://maps/shipment.tscn") # À adapter selon ton nom de fichier
	
	map_selector.add_item("Nouvelle Map", 1)
	map_selector.set_item_metadata(1, "res://TaNouvelleMap.tscn") # À adapter aussi
	
	# 3. Connecter le bouton Jouer
	play_button.pressed.connect(_on_play_button_pressed)

func _on_play_button_pressed() -> void:
	# On sauvegarde les choix dans notre Autoload "Global"
	Global.selected_mode = mode_selector.get_selected_id()
	
	var selected_map_index = map_selector.get_selected()
	Global.selected_map_path = map_selector.get_item_metadata(selected_map_index)
	
	# On lance la map choisie !
	get_tree().change_scene_to_file(Global.selected_map_path)
