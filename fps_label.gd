extends Label

func _process(_delta: float) -> void:
	# On demande au moteur Godot le nombre de FPS actuel
	var current_fps = Engine.get_frames_per_second()
	
	# On met à jour le texte du Label
	text = "FPS : " + str(current_fps)
