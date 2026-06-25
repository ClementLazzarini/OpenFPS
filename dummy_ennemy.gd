extends RigidBody3D

var health: int = 100

# Notre fameuse fonction Plug & Play appelée par le joueur
func take_damage(amount: int) -> void:
	health -= amount
	print("Aïe ! Le mannequin perd ", amount, " PV. Reste : ", health)
	
	# Petit effet visuel : le mannequin saute légèrement quand il est touché
	apply_central_impulse(Vector3.UP * 5.0)
	
	if health <= 0:
		die()

func die() -> void:
	print("Le mannequin est détruit !")
	queue_free() # Détruit le nœud proprement
