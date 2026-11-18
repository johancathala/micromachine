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
#   - elle ne touche personne, ne peut pas exploser, ne s'arrête pas au
#     stand ; les autres voitures (et l'aspiration) l'ignorent.
# Elle franchit les portes des sections comme les autres : elle est
# classée et compte ses tours normalement.
# ============================================================

const STRIDE := GhostManager.STRIDE
const GHOST_ALPHA := 0.55

var car: Car = null
## Tour enregistré (voir GhostManager).
var data: Dictionary = {}

var _samples := PackedFloat32Array()
var _count := 0
var _lap_time := 0.0

# Rejoindre la ligne depuis la grille (courbe de Bézier).
var _launch_points: Array[Vector2] = []
var _launch_time := 0.0
var _launch_length := 0.0

# Temps écoulé depuis le départ (s).
var _time := 0.0
var _started := false


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

	_launch_length = 0.0

	for k in range(1, _launch_points.size()):
		_launch_length += _launch_points[k - 1].distance_to(_launch_points[k])

	# Accélération constante : de 0 à la vitesse d'entrée du tour.
	var entry_speed := maxf(_entry_speed(), 200.0)
	_launch_time = 2.0 * _launch_length / entry_speed


func _entry_speed() -> float:
	var last := mini(4, _count - 1)
	var duration := _samples[last * STRIDE] - _samples[0]

	if duration <= 0.0:
		return 0.0

	return _sample_position(0).distance_to(_sample_position(last)) / duration


func _sample_position(index: int) -> Vector2:
	return Vector2(_samples[index * STRIDE + 1], _samples[index * STRIDE + 2])


## Appelé par la voiture à chaque image physique (une fois partie).
func update(delta: float) -> void:
	var previous := car.global_position
	_time += delta

	if _time < _launch_time:
		_follow_launch(_time / _launch_time)
	else:
		_follow_lap(fmod(_time - _launch_time, _lap_time))

	car.velocity = (car.global_position - previous) / maxf(delta, 0.0001)
	car.speed = car.velocity.length()


func _follow_launch(fraction: float) -> void:
	# Accélération constante : distance ∝ t².
	var target := _launch_length * fraction * fraction
	var travelled := 0.0

	for k in range(1, _launch_points.size()):
		var a := _launch_points[k - 1]
		var b := _launch_points[k]
		var step := a.distance_to(b)

		if travelled + step >= target or k == _launch_points.size() - 1:
			var weight := clampf((target - travelled) / maxf(step, 0.001), 0.0, 1.0)
			car.global_position = a.lerp(b, weight)

			if step > 0.5:
				car.global_rotation = (b - a).angle()

			return

		travelled += step


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
