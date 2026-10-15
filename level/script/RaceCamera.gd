extends Camera2D
class_name RaceCamera


@export_category("Position")

@export_range(0.1, 20.0, 0.1)
var follow_smoothing_speed: float = 4.0

@export_category("Zoom dynamique solo")

# Zoom lorsque la voiture roule lentement ou est arrêtée.
@export_range(0.1, 2.0, 0.05)
var solo_zoom_at_low_speed: float = 0.8

# Zoom lorsque la voiture atteint la vitesse de référence.
# Plus cette valeur est petite, plus la caméra dézoome.
@export_range(0.05, 1.0, 0.05)
var solo_zoom_at_high_speed: float = 0.35

# Vitesse à laquelle le dézoom maximal est atteint.
@export_range(100.0, 3000.0, 50.0)
var solo_zoom_reference_speed: float = 1600.0

@export_category("Anticipation solo")

# Distance maximale de recul de la caméra à haute vitesse.
@export_range(0.0, 1000.0, 10.0)
var solo_lookahead_distance: float = 150.0

# Vitesse à laquelle le recul atteint sa valeur maximale.
# À cette vitesse, le décalage vaut 100 % de solo_lookahead_distance.
@export_range(100.0, 3000.0, 50.0)
var solo_lookahead_speed: float = 1200.0

@export_category("Zoom")

@export_range(0.05, 2.0, 0.01)
var min_zoom: float = 0.07

@export_range(0.1, 3.0, 0.01)
var max_zoom: float = 1.1

@export_range(1.0, 2.0, 0.01)
var zoom_margin: float = 1.50

@export_range(0.1, 20.0, 0.1)
var zoom_smoothing_speed: float = 4.0


@export_category("Activation")

@export var follow_cars: bool = true


var cars_root: Node2D = null
var camera_initialized: bool = false


func _ready() -> void:
	# Nous gérons nous-mêmes le lissage.
	position_smoothing_enabled = false

	cars_root = get_parent().get_node_or_null("Cars") as Node2D

	if cars_root == null:
		push_error(
            "RaceCamera : impossible de trouver le nœud Cars."
		)
		return

	enabled = true


func _process(delta: float) -> void:
	if not follow_cars:
		return

	if cars_root == null:
		return

	var cars: Array[Node2D] = _get_cars()

	if cars.is_empty():
		return

	var bounds: Rect2 = _calculate_bounds(cars)

	var target_position: Vector2
	var target_zoom: float

	if cars.size() == 1:
		var car := cars[0] as Car

		target_position = _calculate_solo_target(car)
		target_zoom = _calculate_solo_zoom(car)
	else:
		# En multijoueur, on conserve le cadrage collectif.
		target_position = bounds.get_center()
		target_zoom = _calculate_zoom(bounds)

	# Initialisation sans déplacement depuis (0, 0).
	if not camera_initialized:
		global_position = target_position
		zoom = Vector2.ONE * target_zoom
		camera_initialized = true
		return

	# Lissage de la position.
	var position_weight: float = (
		1.0 - exp(-follow_smoothing_speed * delta)
	)

	global_position = global_position.lerp(
		target_position,
		position_weight
	)

	# Lissage du zoom.
	var zoom_weight: float = (
		1.0 - exp(-zoom_smoothing_speed * delta)
	)

	zoom = zoom.lerp(
		Vector2.ONE * target_zoom,
		zoom_weight
	)


func _get_cars() -> Array[Node2D]:
	var cars: Array[Node2D] = []

	for child in cars_root.get_children():
		var car := child as Car

		if car == null:
			continue

		# On ne cadre que les joueurs humains actifs.
		if car.is_ai:
			continue

		if car._destruction_started:
			continue

		cars.append(car)

	return cars

func _calculate_solo_zoom(car: Car) -> float:
	var current_speed: float = car.velocity.length()

	var speed_ratio: float = clampf(
		current_speed / solo_zoom_reference_speed,
		0.0,
		1.0
	)

	return lerpf(
		solo_zoom_at_low_speed,
		solo_zoom_at_high_speed,
		speed_ratio
	)

func _calculate_solo_target(car: Car) -> Vector2:
	# Vitesse réelle de la voiture, en unités par seconde.
	var current_speed: float = car.speed

	# Ratio entre 0 et 1.
	var speed_ratio: float = clampf(
		current_speed / solo_lookahead_speed,
		0.0,
		1.0
	)

	# Direction avant de la voiture.
	var forward: Vector2 = Vector2.RIGHT.rotated(
		car.global_rotation
	)

	# La caméra se place derrière la voiture.
	var lookahead: float = (
		solo_lookahead_distance * speed_ratio
	)

	return car.global_position - forward * lookahead


func _calculate_bounds(cars: Array[Node2D]) -> Rect2:
	var bounds := Rect2(
		cars[0].global_position,
		Vector2.ZERO
	)

	for car in cars:
		bounds = bounds.expand(car.global_position)

	return bounds


func _calculate_zoom(bounds: Rect2) -> float:
	var viewport_size: Vector2 = get_viewport_rect().size

	var required_width: float = (
		maxf(bounds.size.x, 1.0)
		* zoom_margin
	)

	var required_height: float = (
		maxf(bounds.size.y, 1.0)
		* zoom_margin
	)

	var zoom_x: float = (
		viewport_size.x / required_width
	)

	var zoom_y: float = (
		viewport_size.y / required_height
	)

	var target_zoom: float = minf(zoom_x, zoom_y)

	return clampf(
		target_zoom,
		min_zoom,
		max_zoom
	)
