extends RefCounted
class_name GhostDriver

# ============================================================
# PILOTE FANTÔME
# ============================================================
#
# Une IA « fantôme » rejoue un tour enregistré en contre-la-montre
# (GhostManager) : même circuit, même voiture, enregistré par un
# joueur. La voiture suit l'enregistrement sans physique :
#   - au départ, elle quitte sa place sur la grille et rejoint la ligne
#     en accélérant jusqu'à la vitesse du tour enregistré ;
#   - ensuite elle refait ce tour, encore et encore (le tour enregistré
#     se referme sur la ligne de départ) ;
#   - usure des pneus : comme une autre voiture, ses pneus s'usent avec
#     la distance ; passé le seuil de dégradation, le tour est rejoué
#     plus lentement. Quand l'usure l'impose, elle quitte
#     l'enregistrement à l'entrée du stand, suit la voie des stands
#     (vitesse limitée), s'arrête le temps du changement de pneus, puis
#     reprend l'enregistrement à la sortie ;
#   - elle ne touche personne et ne peut pas exploser ; les autres
#     voitures (et l'aspiration) l'ignorent.
# Elle franchit les portes des sections comme les autres : elle est
# classée et compte ses tours normalement.
# ============================================================

const STRIDE := GhostManager.STRIDE
const GHOST_ALPHA := 0.55

## Rythme (fraction de la vitesse enregistrée) avec des pneus
## complètement usés ; la chute commence à car.tire_degradation_start.
const WORN_PACE := 0.8
## Usure visée au plus tard : au-delà, le fantôme s'arrête au stand
## (s'il reste au moins un tour).
const PIT_WEAR := 0.65
## Arrêt au stand : durée du changement de pneus (s), accélération et
## freinage (px/s²), vitesse hors de la voie limitée.
const PIT_SERVICE_TIME := 3.5
const PIT_ACCEL := 700.0
const PIT_BRAKE := 1400.0
const PIT_FREE_SPEED := 900.0
## Écart (px) entre l'enregistrement et le trajet du stand au raccord.
const PIT_JOIN_SKIP := 3

enum Phase { LAUNCH, LAP, PIT }

var car: Car = null
var participant: RaceParticipantState = null
## Nombre de tours de la course (0 : illimité).
var lap_count := 0
## Tour enregistré (voir GhostManager).
var data: Dictionary = {}

var _samples := PackedFloat32Array()
var _count := 0
var _lap_time := 0.0

var _phase := Phase.LAUNCH

# Rejoindre la ligne depuis la grille (courbe de Bézier).
var _launch_points: Array[Vector2] = []
var _launch_time := 0.0
var _launch_length := 0.0
var _launch_elapsed := 0.0

# Temps dans le tour enregistré (s).
var _clock := 0.0

# Stand : trajet du fantôme, raccords dans l'enregistrement.
var _pit_path := PackedVector2Array()
var _pit_limits := PackedFloat32Array()
var _pit_stop_distance := 0.0
var _pit_length := 0.0
var _entry_time := -1.0
var _exit_time := -1.0
var _exit_speed := 0.0
var _pit_planned := false
var _pit_distance := 0.0
var _pit_speed := 0.0
var _service_left := 0.0
var _serviced := false


func _init(p_car: Car, p_data: Dictionary) -> void:
	car = p_car
	data = p_data
	_samples = data.get("samples", PackedFloat32Array())
	_count = _samples.size() / STRIDE
	_lap_time = maxf(float(data.get("lap_time", 0.0)), _samples[(_count - 1) * STRIDE] if _count > 0 else 0.0)


## Enregistrement utilisable (au moins une seconde de tour).
static func is_usable(p_data: Dictionary) -> bool:
	var samples: PackedFloat32Array = p_data.get("samples", PackedFloat32Array())
	return samples.size() >= STRIDE * 30 and float(p_data.get("lap_time", 0.0)) > 1.0


## À appeler une fois la voiture sur la grille.
func prepare() -> void:
	car.is_ghost = true

	# Semi-transparente, silencieuse.
	if car.model != null:
		var tint := car.model.modulate
		tint.a = GHOST_ALPHA
		car.model.modulate = tint

	for sound in car.find_children("*", "AudioStreamPlayer2D", true, false):
		(sound as AudioStreamPlayer2D).volume_db = -80.0

	# Les autres voitures la traversent.
	for node in car.get_parent().get_children():
		var other := node as Car

		if other != null and other != car:
			car.add_collision_exception_with(other)
			other.add_collision_exception_with(car)

	_build_launch()


# ------------------------------------------------------------
# Départ : de la grille à la ligne
# ------------------------------------------------------------

## Trajet de la grille jusqu'au début du tour enregistré : courbe
## tangente à la voiture au départ et à la trajectoire à l'arrivée,
## parcourue en accélérant de l'arrêt à la vitesse enregistrée.
func _build_launch() -> void:
	var start := car.global_position
	var heading := Vector2.RIGHT.rotated(car.global_rotation)
	var end := _sample_position(0)
	var end_direction := (_sample_position(mini(3, _count - 1)) - end).normalized()

	if end_direction == Vector2.ZERO:
		end_direction = heading

	var distance := start.distance_to(end)
	var handle := distance * 0.4
	var p1 := start + heading * handle
	var p2 := end - end_direction * handle
	_launch_points = []

	for k in range(41):
		var t := k / 40.0
		var u := 1.0 - t
		_launch_points.append(u * u * u * start + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * end)

	_launch_length = _polyline_length(PackedVector2Array(_launch_points))

	# Accélération constante : de 0 à la vitesse d'entrée du tour.
	var entry_speed := maxf(_speed_at(0), 200.0)
	_launch_time = 2.0 * _launch_length / entry_speed


# ------------------------------------------------------------
# Stand
# ------------------------------------------------------------

## Trajet vers le stand (TrackProgress.build_pit_route) : raccordé à
## l'enregistrement au plus près de son début et de sa fin.
func setup_pit(route: Dictionary) -> void:
	var points: PackedVector2Array = route.get("points", PackedVector2Array())

	if points.size() < PIT_JOIN_SKIP * 2 + 4 or _count < 4:
		return

	var limits: PackedFloat32Array = route.get("speed_limits", PackedFloat32Array())
	var first := PIT_JOIN_SKIP
	var last := points.size() - 1 - PIT_JOIN_SKIP
	var entry_sample := _closest_sample(points[first])
	var exit_sample := _closest_sample(points[last])

	_entry_time = _samples[entry_sample * STRIDE]
	_exit_time = _samples[exit_sample * STRIDE]
	_exit_speed = _speed_at(exit_sample)

	# Trajet : point de l'enregistrement, voie des stands, point de
	# l'enregistrement.
	_pit_path = PackedVector2Array([_sample_position(entry_sample)])
	_pit_limits = PackedFloat32Array([0.0])

	for i in range(first, last + 1):
		_pit_path.append(points[i])
		_pit_limits.append(limits[i] if i < limits.size() else 0.0)

	_pit_path.append(_sample_position(exit_sample))
	_pit_limits.append(0.0)

	var stop_index := clampi(int(route.get("stop_index", 0)) - first + 1, 1, _pit_path.size() - 2)
	_pit_length = _polyline_length(_pit_path)
	_pit_stop_distance = _polyline_length(_pit_path.slice(0, stop_index + 1))


func _closest_sample(point: Vector2) -> int:
	var best := 0

	for i in range(_count):
		if _sample_position(i).distance_squared_to(point) < _sample_position(best).distance_squared_to(point):
			best = i

	return best


## Nouveau tour : arrêt prévu si l'usure dépasserait PIT_WEAR avant la
## fin du tour et qu'il reste au moins un tour après celui-ci.
func _plan_pit() -> void:
	_pit_planned = false

	if _pit_path.is_empty() or not car.tire_wear_enabled:
		return

	var lap_wear := _recorded_length() / maxf(car.tire_wear_distance, 1.0)
	var laps_left := 99 if lap_count <= 0 or participant == null else lap_count - participant.current_lap

	_pit_planned = car.tire_wear + lap_wear > PIT_WEAR and laps_left >= 2


func _start_pit() -> void:
	_phase = Phase.PIT
	_pit_distance = 0.0
	_pit_speed = car.speed
	_service_left = PIT_SERVICE_TIME
	_serviced = false


func _update_pit(delta: float) -> void:
	# Arrêt : changement de pneus.
	if not _serviced and _pit_distance >= _pit_stop_distance - 2.0:
		_pit_speed = 0.0
		_service_left -= delta

		if _service_left <= 0.0:
			_serviced = true
			car.reset_tires()

		return

	var limit := _limit_at(_pit_distance)
	var target := limit if limit > 0.0 else (PIT_FREE_SPEED if not _serviced else maxf(_exit_speed, PIT_FREE_SPEED))

	# Freinage pour s'arrêter dans la zone.
	if not _serviced:
		target = minf(target, sqrt(2.0 * PIT_BRAKE * maxf(_pit_stop_distance - _pit_distance, 0.0)) + 20.0)

	if _pit_speed < target:
		_pit_speed = minf(target, _pit_speed + PIT_ACCEL * delta)
	else:
		_pit_speed = maxf(target, _pit_speed - PIT_BRAKE * delta)

	_pit_distance += _pit_speed * delta

	if not _serviced:
		_pit_distance = minf(_pit_distance, _pit_stop_distance)

	if _pit_distance >= _pit_length:
		# Sortie : l'enregistrement reprend là où le trajet le rejoint.
		_phase = Phase.LAP
		_pit_planned = false
		_clock = _exit_time
		_follow_lap(_clock)
		return

	_place_on(_pit_path, _pit_distance)


## Vitesse limitée au point du trajet du stand (0 : aucune).
func _limit_at(distance: float) -> float:
	var travelled := 0.0

	for k in range(1, _pit_path.size()):
		travelled += _pit_path[k - 1].distance_to(_pit_path[k])

		if travelled >= distance:
			return _pit_limits[k]

	return 0.0


# ------------------------------------------------------------
# Image par image
# ------------------------------------------------------------

## Appelé par la voiture à chaque image physique (une fois partie).
func update(delta: float) -> void:
	var previous := car.global_position

	match _phase:
		Phase.LAUNCH:
			_launch_elapsed += delta

			if _launch_elapsed < _launch_time:
				var fraction := _launch_elapsed / _launch_time
				_place_on(PackedVector2Array(_launch_points), _launch_length * fraction * fraction)
			else:
				_phase = Phase.LAP
				_clock = _launch_elapsed - _launch_time
				_plan_pit()
				_follow_lap(_clock)

		Phase.LAP:
			var before := _clock
			_clock += delta * _pace()

			if _clock >= _lap_time:
				_clock -= _lap_time
				before = -1.0
				_plan_pit()

			if _pit_planned and before < _entry_time and _clock >= _entry_time:
				_start_pit()
				_update_pit(delta)
			else:
				_follow_lap(_clock)

		Phase.PIT:
			_update_pit(delta)

	var moved := car.global_position.distance_to(previous)
	car.velocity = (car.global_position - previous) / maxf(delta, 0.0001)
	car.speed = car.velocity.length()

	# Usure des pneus : distance parcourue, comme sur la route.
	if car.tire_wear_enabled and _phase != Phase.LAUNCH:
		car.tire_wear = minf(car.tire_wear + moved / maxf(car.tire_wear_distance, 1.0), 1.0)


## Rythme selon l'usure (1 : pneus en état).
func _pace() -> float:
	if not car.tire_wear_enabled or car.tire_wear <= car.tire_degradation_start:
		return 1.0

	var degradation := (car.tire_wear - car.tire_degradation_start) / maxf(1.0 - car.tire_degradation_start, 0.001)
	return lerpf(1.0, WORN_PACE, clampf(degradation, 0.0, 1.0))


func _follow_lap(lap_time: float) -> void:
	var last_time := _samples[(_count - 1) * STRIDE]

	# Fin du tour : jonction entre le dernier échantillon et le premier
	# (le tour suivant commence sur la ligne).
	if lap_time >= last_time:
		var gap := maxf(_lap_time - last_time, 0.0001)
		var weight := clampf((lap_time - last_time) / gap, 0.0, 1.0)
		_place(_count - 1, 0, weight)
		return

	var low := 0
	var high := _count - 1

	while high - low > 1:
		var middle := (low + high) / 2

		if _samples[middle * STRIDE] <= lap_time:
			low = middle
		else:
			high = middle

	var t0 := _samples[low * STRIDE]
	var t1 := _samples[high * STRIDE]
	_place(low, high, clampf((lap_time - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0))


func _place(from: int, to: int, weight: float) -> void:
	car.global_position = _sample_position(from).lerp(_sample_position(to), weight)
	car.global_rotation = lerp_angle(_samples[from * STRIDE + 3], _samples[to * STRIDE + 3], weight)


## Place la voiture à `distance` le long d'un tracé, orientée selon lui.
func _place_on(points: PackedVector2Array, distance: float) -> void:
	var travelled := 0.0

	for k in range(1, points.size()):
		var a := points[k - 1]
		var b := points[k]
		var step := a.distance_to(b)

		if travelled + step >= distance or k == points.size() - 1:
			var weight := clampf((distance - travelled) / maxf(step, 0.001), 0.0, 1.0)
			car.global_position = a.lerp(b, weight)

			if step > 0.5:
				car.global_rotation = lerp_angle(car.global_rotation, (b - a).angle(), 0.35)

			return

		travelled += step


# ------------------------------------------------------------
# Outils
# ------------------------------------------------------------

func _sample_position(index: int) -> Vector2:
	return Vector2(_samples[index * STRIDE + 1], _samples[index * STRIDE + 2])


## Vitesse enregistrée autour d'un échantillon (px/s).
func _speed_at(index: int) -> float:
	var a := clampi(index - 2, 0, _count - 1)
	var b := clampi(index + 2, 0, _count - 1)
	var duration := _samples[b * STRIDE] - _samples[a * STRIDE]

	if duration <= 0.0:
		return 0.0

	return _sample_position(a).distance_to(_sample_position(b)) / duration


func _recorded_length() -> float:
	var length := 0.0

	for i in range(1, _count):
		length += _sample_position(i - 1).distance_to(_sample_position(i))

	return length


static func _polyline_length(points: PackedVector2Array) -> float:
	var length := 0.0

	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])

	return length
