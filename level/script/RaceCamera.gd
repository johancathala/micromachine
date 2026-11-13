extends Camera2D
class_name RaceCamera


@export_category("Position")

@export_range(0.1, 20.0, 0.1)
var follow_smoothing_speed: float = 10.0

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

@export_category("Anticipation du joueur en tête (multijoueur)")

# Échelle du jeu : une voiture (~4,2 m) mesure ~141 px de long.
@export_range(1.0, 200.0, 0.5)
var pixels_per_meter: float = 34.0

# Distance minimale visible devant le joueur humain en tête,
# pour voir arriver les virages.
@export_range(0.0, 60.0, 0.5)
var leader_lookahead_meters: float = 15.0

# En dessous de cette vitesse (px/s), on utilise l'orientation
# de la voiture plutôt que sa direction de déplacement.
@export_range(0.0, 500.0, 10.0)
var leader_direction_min_speed: float = 120.0

# Lissage du point d'anticipation (évite les à-coups quand
# la voiture tourne ou que le joueur en tête change).
@export_range(0.1, 20.0, 0.1)
var leader_lookahead_smoothing_speed: float = 4.0

@export_category("Mode élimination")

# Zoom fixe : la caméra suit le leader sans dézoomer pour cadrer
# les autres (sinon personne ne sortirait de l'écran).
# À 0.5, l'écran couvre ~113 m x 64 m.
@export_range(0.1, 2.0, 0.01)
var elimination_zoom: float = 0.5

# Le centre de l'écran est placé devant le leader : il voit loin
# devant lui, les poursuivants disparaissent par l'arrière.
@export_range(0.0, 40.0, 0.5)
var elimination_center_ahead_meters: float = 10.0

@export_category("Zoom")

@export_range(0.05, 2.0, 0.01)
var min_zoom: float = 0.07

@export_range(0.1, 3.0, 0.01)
var max_zoom: float = 1.1

@export_range(1.0, 2.0, 0.01)
var zoom_margin: float = 1.50

@export_range(0.1, 20.0, 0.1)
var zoom_smoothing_speed: float = 10.0


@export_category("Activation")

@export var follow_cars: bool = true


var cars_root: Node2D = null
var camera_initialized: bool = false

# Fourni par Race : donne le classement des participants.
var race_controller: RaceController = null

# Décalage lissé entre le joueur en tête et le point à garder visible.
var _leader_lookahead_offset: Vector2 = Vector2.ZERO
var _lookahead_initialized: bool = false


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

	if _is_elimination_mode():
		var leader_state := race_controller.elimination_rules.get_leader_state()

		# Leader en cours d'explosion / réapparition : on ne bouge pas.
		if leader_state == null:
			return

		target_position = _get_smoothed_lookahead_point(
			leader_state.car,
			elimination_center_ahead_meters,
			delta
		)
		target_zoom = elimination_zoom

	elif cars.size() == 1:
		var car := cars[0] as Car

		target_position = _calculate_solo_target(car)
		target_zoom = _calculate_solo_zoom(car)
	else:
		# En multijoueur, on conserve le cadrage collectif,
		# en gardant visible la route devant le joueur en tête.
		var lookahead_point: Variant = _get_leader_lookahead_point(
			cars,
			delta
		)

		if lookahead_point != null:
			bounds = bounds.expand(lookahead_point)

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


# ------------------------------------------------------------------
# Joueur en tête
# ------------------------------------------------------------------

## Point situé leader_lookahead_meters devant le joueur humain en tête,
## ou null s'il n'y a pas de joueur en tête identifiable.
func _get_leader_lookahead_point(
	cars: Array[Node2D],
	delta: float
) -> Variant:

	var leader := _find_leader_car(cars)

	if leader == null:
		_lookahead_initialized = false
		return null

	return _get_smoothed_lookahead_point(
		leader,
		leader_lookahead_meters,
		delta
	)


## Point situé `meters` devant la voiture, dans sa direction de
## déplacement, avec un décalage lissé.
func _get_smoothed_lookahead_point(
	leader: Car,
	meters: float,
	delta: float
) -> Vector2:

	var target_offset: Vector2 = (
		_get_travel_direction(leader)
		* meters
		* pixels_per_meter
	)

	if not _lookahead_initialized:
		_leader_lookahead_offset = target_offset
		_lookahead_initialized = true
	else:
		var weight: float = (
			1.0 - exp(-leader_lookahead_smoothing_speed * delta)
		)

		_leader_lookahead_offset = _leader_lookahead_offset.lerp(
			target_offset,
			weight
		)

	return leader.global_position + _leader_lookahead_offset


## Joueur humain le mieux classé parmi les voitures cadrées.
## Les joueurs ayant terminé passent après ceux encore en course.
func _find_leader_car(cars: Array[Node2D]) -> Car:
	if race_controller == null:
		return null

	var leader: Car = null
	var best_rank := INF

	for state in race_controller.get_participant_states():
		if state.is_ai or state.car == null:
			continue

		if not cars.has(state.car):
			continue

		# race_position vaut 0 tant que le classement n'est pas calculé.
		var rank: float = (
			float(state.race_position)
			if state.race_position > 0
			else 1000.0
		)

		if state.finished:
			rank += 10000.0

		if rank < best_rank:
			best_rank = rank
			leader = state.car

	return leader


## Direction de déplacement (ou orientation à basse vitesse).
func _get_travel_direction(car: Car) -> Vector2:
	if car.velocity.length() >= leader_direction_min_speed:
		return car.velocity.normalized()

	return Vector2.RIGHT.rotated(car.global_rotation)


func _is_elimination_mode() -> bool:
	return (
		race_controller != null
		and race_controller.is_elimination_mode()
	)


## Zone du monde actuellement visible à l'écran.
func get_visible_world_rect() -> Rect2:
	var size: Vector2 = get_viewport_rect().size / zoom

	return Rect2(
		get_screen_center_position() - size / 2.0,
		size
	)


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
