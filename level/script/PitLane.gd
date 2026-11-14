extends Area2D
class_name PitLane

# ============================================================
# VOIE DES STANDS : VITESSE LIMITÉE
# ============================================================
# À placer dans un circuit (nœud « PitLane » à la racine), couvrant la
# voie des stands hors zones d'arrêt (PitStop). Toute voiture qui s'y
# trouve est bridée à `speed_limit`, la même pour tous les véhicules.
# Les formes (CollisionShape2D) se modifient dans l'éditeur.
# Détecte les voitures (couche de collision 2 : Player).
# ============================================================

## Vitesse maximum dans la voie des stands (px/s), tous véhicules.
const DEFAULT_SPEED_LIMIT := 600.0

@export_range(100.0, 2000.0, 10.0) var speed_limit: float = DEFAULT_SPEED_LIMIT


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2


func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		var car := body as Car

		if car != null:
			car.apply_speed_limit(speed_limit)


## Le point est-il dans la voie (calcul du trajet de l'IA) ?
func contains_point(point: Vector2) -> bool:
	for child in get_children():
		var shape := child as CollisionShape2D

		if shape == null or not shape.shape is RectangleShape2D or shape.disabled:
			continue

		var local := shape.global_transform.affine_inverse() * point
		var half := (shape.shape as RectangleShape2D).size / 2.0

		if absf(local.x) <= half.x and absf(local.y) <= half.y:
			return true

	return false
