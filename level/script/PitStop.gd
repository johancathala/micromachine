extends Area2D
class_name PitStop

# ============================================================
# ZONE DE STAND
# ============================================================
# À placer dans un circuit, sur la voie des stands (nœud « PitStop »
# à la racine du circuit). Une voiture qui s'y arrête (option
# « Usure des pneus ») déclenche le changement de pneus.
# Détecte les voitures (couche de collision 2 : Player).
# ============================================================


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2


func contains_car(car: Car) -> bool:
	return overlaps_body(car)
