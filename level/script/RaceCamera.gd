extends Camera2D
class_name RaceCamera


@export_category("Position")

@export_range(0.1, 20.0, 0.1)
var follow_smoothing_speed: float = 12.0

@export_category("Zoom")

@export_range(0.05, 2.0, 0.01)
var min_zoom: float = 0.07

@export_range(0.1, 3.0, 0.01)
var max_zoom: float = 1.1

@export_range(1.0, 2.0, 0.01)
var zoom_margin: float = 1.50

@export_range(0.1, 20.0, 0.1)
var zoom_smoothing_speed: float = 12.0


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

	var target_position: Vector2 = bounds.get_center()
	var target_zoom: float = _calculate_zoom(bounds)

	# Au premier calcul, on place immédiatement la caméra.
	# Cela évite qu'elle parte de (0, 0) pour rejoindre les voitures.
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
		var car := child as Node2D

		if car != null:
			cars.append(car)

	return cars


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
