extends Control

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var score_label: Label = $VBoxContainer/ScoreLabel
@onready var menu_button: Button = $VBoxContainer/MenuButton

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu_button.pressed.connect(_on_menu_button_pressed)

# Fonction appelée par le MatchManager quand la partie se termine
func setup_screen(title: String, final_scores: String) -> void:
	title_label.text = title
	score_label.text = final_scores

func _on_menu_button_pressed() -> void:
	# 1. On enlève la pause du moteur de jeu AVANT de changer de scène !
	get_tree().paused = false 
	
	# 2. On retourne au menu principal (Vérifie bien le nom exact de ta scène menu)
	get_tree().change_scene_to_file("res://main_menu.tscn")
