extends RefCounted
class_name AIDriver

# ============================================================
# PILOTE IA GÉNÉRIQUE
# ============================================================
#
# Le même code pour tous les circuits et toutes les voitures ; seule
# la trajectoire (RacingLine) dépend du circuit.
#
# - Direction : « poursuite pure » d'un point de la trajectoire situé
#   devant la voiture (plus loin à haute vitesse).
# - Vitesse : profil calculé une fois pour la voiture : vitesse max
#   dans chaque virage (limite de braquage de la voiture + adhérence),
#   puis anticipation des freinages.
# - Adversaires : ralentit derrière une voiture plus lente et tente de
#   la dépasser en se décalant du côté libre.
# - Problèmes : marche arrière si bloquée, réapparition si elle
#   n'avance plus du tout.
# - Difficulté : marge prise dans les virages et en ligne droite.
# ============================================================

enum Difficulty { NOVICE, MEDIUM, EXPERT }

# Fraction de la vitesse « limite » visée, selon la difficulté.
const PACE := [0.80, 0.90, 0.97]

# Marge de braquage gardée pour corriger la trajectoire.
static var steer_margin := 1.3
# Effet de sous-virage du modèle de voiture sur asphalte (Car.gd).
const ASPHALT_UNDERSTEER := 0.85
# Dérive : dans le modèle de voiture, l'adhérence ne corrige la vitesse
# latérale que progressivement ; l'angle de glisse en virage vaut
# environ vitesse x courbure / adhérence. L'IA limite sa vitesse pour
# le garder sous cette valeur (radians). Réglable pour les essais.
static var max_slip := 0.5
# Vitesse minimale visée, même dans un virage très serré.
const MIN_CORNER_SPEED := 220.0
# Freinage réellement disponible (fraction de brake_force).
const BRAKE_EFFICIENCY := 0.75

# Visée : distance du point suivi (px) = base + facteur * vitesse.
const LOOKAHEAD_BASE := 150.0
const LOOKAHEAD_SPEED := 0.33
const LOOKAHEAD_MAX := 650.0
# Suivi de trajectoire : distance de correction (px) = base + facteur
# * vitesse ; délai de braquage anticipé (s) ; au-delà de ces écarts
# (px, rad), retour à la poursuite pure pour rejoindre la ligne.
const TRACKING_BASE := 120.0
const TRACKING_SPEED := 0.25
const TRACKING_MAX := 450.0
const STEER_PREVIEW_TIME := 0.08
const GRIP_LAG_FACTOR := 0.4
const TRACKING_MAX_ERROR := 160.0
const TRACKING_MAX_ANGLE := 0.7

# Adversaires.
const AVOID_RANGE := 380.0
const AVOID_CONE := 0.75
const OVERTAKE_OFFSET := 120.0

# Blocage.
const STUCK_SPEED := 40.0
const STUCK_DELAY := 1.0
const REVERSE_TIME := 0.9
const NO_PROGRESS_RESPAWN := 6.0

## Réglages globaux (essais).
static func set_tuning(slip: float, margin: float) -> void:
	max_slip = slip
	steer_margin = margin


var car: Car = null
var line: RacingLine = null
var difficulty: int = Difficulty.MEDIUM

# Profil de vitesse (px/s) en chaque point de la trajectoire.
var speed_profile := PackedFloat32Array()

var _index := -1
var _lateral_offset := 0.0
var _stuck_time := 0.0
var _reverse_time := 0.0
var _no_progress_time := 0.0
var _last_progress_index := -1

# Statistiques (réglages / tests).
var respawn_count := 0


func _init(p_car: Car, p_line: RacingLine, p_difficulty: int) -> void:
	car = p_car
	line = p_line
	difficulty = clampi(p_difficulty, 0, PACE.size() - 1)
	_build_speed_profile()


# ------------------------------------------------------------
# Profil de vitesse
# ------------------------------------------------------------

func _build_speed_profile() -> void:
	var count := line.points.size()
	speed_profile.resize(count)

	var pace: float = PACE[difficulty]
	var top_speed := car.max_speed * pace

	for i in range(count):
		speed_profile[i] = minf(_corner_speed(line.curvature[i]) * pace, top_speed)

	# Anticipation des freinages (deux passes à rebours sur la boucle).
	var decel := car.brake_force * BRAKE_EFFICIENCY

	for _pass in range(2):
		for step in range(count):
			var i := count - 1 - step
			var next := speed_profile[(i + 1) % count]
			var reachable := sqrt(next * next + 2.0 * decel * RacingLine.SPACING)

			if speed_profile[i] > reachable:
				speed_profile[i] = reachable


## Vitesse max pour suivre une courbure : limite de braquage de la
## voiture (le braquage efficace baisse avec la vitesse) et adhérence.
func _corner_speed(k: float) -> float:
	if k < 0.00005:
		return car.max_speed

	# Braquage nécessaire : tan(angle) = courbure * empattement.
	var needed_angle := atan(k * car.wheel_base)
	var needed_response := needed_angle / (car.max_steer_angle * ASPHALT_UNDERSTEER * steer_margin)

	var kinematic := car.max_speed

	if needed_response > car.steering_response_low_speed:
		kinematic = MIN_CORNER_SPEED
	elif needed_response > car.steering_response_high_speed:
		# Le braquage efficace baisse linéairement entre deux vitesses.
		var t := (car.steering_response_low_speed - needed_response) / maxf(
			car.steering_response_low_speed - car.steering_response_high_speed, 0.001
		)
		kinematic = lerpf(car.steering_high_speed_start, car.steering_high_speed_end, t)

	# Limite de dérive : v = glisse_max * adhérence(v) / courbure,
	# l'adhérence baissant avec la vitesse (résolution itérative).
	var grip_limited := car.max_speed

	for _i in range(8):
		grip_limited = max_slip * _grip_at(grip_limited) / k

	return maxf(minf(kinematic, grip_limited), MIN_CORNER_SPEED)


## Adhérence latérale de la voiture à une vitesse donnée (Car.gd).
func _grip_at(speed: float) -> float:
	var t := inverse_lerp(car.high_speed_grip_start, car.high_speed_grip_end, speed)
	return lerpf(car.lateral_grip, car.lateral_grip_at_high_speed, clampf(t, 0.0, 1.0))


# ------------------------------------------------------------
# Pilotage (appelé à chaque image physique par la voiture)
# ------------------------------------------------------------

func update(delta: float) -> void:
	if line == null or not line.is_valid():
		return

	var position := car.global_position
	var speed := car.velocity.length()
	_index = line.closest_index(position, _index)

	# Loin de la trajectoire (réapparition, grosse sortie) : recherche
	# sur toute la ligne.
	if position.distance_to(line.point(_index)) > 500.0:
		_index = line.closest_index(position)

	# ---- Point visé, décalé pour dépasser si besoin ----
	var lookahead := clampf(LOOKAHEAD_BASE + LOOKAHEAD_SPEED * speed, LOOKAHEAD_BASE, LOOKAHEAD_MAX)
	var target_index := _index + int(lookahead / RacingLine.SPACING)
	var target_speed := speed_profile[posmod(_index + 2, speed_profile.size())]

	var avoid := _avoid_cars(speed)
	target_speed = minf(target_speed, avoid["speed_cap"])
	_lateral_offset = move_toward(_lateral_offset, avoid["offset"], 300.0 * delta)

	var target := line.point(target_index)

	if absf(_lateral_offset) > 1.0:
		target += line.direction(target_index).orthogonal() * _lateral_offset

	# ---- Direction ----
	var to_target := target - position
	var alpha := wrapf(to_target.angle() - car.global_rotation, -PI, PI)
	var distance := maxf(to_target.length(), 1.0)
	# Poursuite pure : sert loin de la trajectoire (rejoindre la ligne).
	var path_curvature := 2.0 * sin(alpha) / distance

	# Sur la trajectoire : courbure de la ligne (anticipée du délai de
	# braquage) + correction de l'écart latéral et de l'angle. Contrairement
	# à la poursuite pure, ne coupe pas les virages à haute vitesse.
	# Dans le modèle de voiture, la vitesse ne suit le cap qu'avec un
	# retard d'environ 1 / adhérence : on anticipe d'autant, et l'écart
	# d'angle est mesuré sur la direction de la vitesse (le vrai chemin).
	var grip_lag := 1.0 / maxf(_grip_at(speed), 0.5)
	var preview_index := _index + int(speed * (STEER_PREVIEW_TIME + GRIP_LAG_FACTOR * grip_lag) / RacingLine.SPACING)
	var line_direction := line.direction(_index)
	var normal := line_direction.orthogonal()
	var lateral_error := (position - line.point(_index)).dot(normal) - _lateral_offset
	var travel_angle := car.global_rotation
	var heading_error := wrapf(travel_angle - line_direction.angle(), -PI, PI)

	if absf(lateral_error) < TRACKING_MAX_ERROR and absf(heading_error) < TRACKING_MAX_ANGLE:
		var preview := clampf(TRACKING_BASE + TRACKING_SPEED * speed, TRACKING_BASE, TRACKING_MAX)
		path_curvature = (
			line.signed_curvature_at(preview_index)
			+ 2.0 * lateral_error / (preview * preview)
			- 2.0 * sin(heading_error) / preview
		)

	var steer_angle := atan(path_curvature * car.wheel_base)
	var response := _steering_response(speed) * ASPHALT_UNDERSTEER
	var steer := steer_angle / maxf(car.max_steer_angle * response, 0.01)

	var throttle := 0.0
	var brake := 0.0

	# ---- Vitesse ----
	if speed < target_speed:
		# Sous la vitesse visée : à fond (les voitures lentes en ont besoin).
		throttle = 1.0
	elif speed > target_speed + 30.0:
		# Freiner seulement en roulant (sinon c'est la marche arrière).
		if speed > 120.0:
			brake = clampf((speed - target_speed) / 250.0, 0.25, 1.0)

	# Grosse erreur d'angle (après un tête-à-queue...) : on ralentit.
	if absf(alpha) > 1.2 and speed > 250.0:
		throttle = 0.0

	# ---- Blocage : marche arrière, puis réapparition ----
	_update_stuck(delta, speed)

	if _reverse_time > 0.0:
		_reverse_time -= delta
		throttle = 0.0
		brake = 1.0
		steer = -signf(alpha)

	car.throttle = throttle
	car.brake = brake
	car.steer_input = clampf(steer, -1.0, 1.0)
	car.handbrake = false


func _steering_response(speed: float) -> float:
	var t := inverse_lerp(car.steering_high_speed_start, car.steering_high_speed_end, speed)
	return lerpf(car.steering_response_low_speed, car.steering_response_high_speed, clampf(t, 0.0, 1.0))


## Voiture devant, dans l'axe : ralentir à sa vitesse si elle est
## proche, sinon se décaler du côté libre pour la dépasser.
func _avoid_cars(speed: float) -> Dictionary:
	var result := {"speed_cap": INF, "offset": 0.0}
	var parent := car.get_parent()

	if parent == null:
		return result

	var forward := Vector2.RIGHT.rotated(car.global_rotation)
	var closest := INF

	for node in parent.get_children():
		var other := node as Car

		if other == null or other == car or not other.visible or other._destruction_started:
			continue

		var to_other := other.global_position - car.global_position
		var gap := to_other.length()

		if gap > AVOID_RANGE or gap < 1.0:
			continue

		if forward.dot(to_other / gap) < AVOID_CONE:
			continue

		var other_speed := other.velocity.dot(forward)

		if other_speed >= speed - 20.0 or gap >= closest:
			continue

		closest = gap
		# Côté de l'adversaire par rapport à nous : on passe de l'autre.
		var side := signf(forward.orthogonal().dot(to_other))
		result["offset"] = -side * OVERTAKE_OFFSET if side != 0.0 else OVERTAKE_OFFSET

		# Trop près : on calque sa vitesse pour ne pas le percuter.
		if gap < AVOID_RANGE * 0.45:
			result["speed_cap"] = maxf(other_speed * 0.95, 0.0)

	return result


func _update_stuck(delta: float, speed: float) -> void:
	if not car.car_can_move:
		_stuck_time = 0.0
		_no_progress_time = 0.0
		return

	# Bloquée (mur, voiture...) : marche arrière brève.
	if speed < STUCK_SPEED and _reverse_time <= 0.0:
		_stuck_time += delta

		if _stuck_time > STUCK_DELAY:
			_reverse_time = REVERSE_TIME
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0

	# N'avance plus sur la trajectoire : réapparition.
	if _last_progress_index < 0 or posmod(_index - _last_progress_index, line.points.size()) > 3 and posmod(_index - _last_progress_index, line.points.size()) < line.points.size() / 2:
		_last_progress_index = _index
		_no_progress_time = 0.0
	else:
		_no_progress_time += delta

	if _no_progress_time > NO_PROGRESS_RESPAWN:
		_no_progress_time = 0.0
		_last_progress_index = -1
		respawn_count += 1
		car.explosion()


## Après une réapparition : reprendre la trajectoire au plus près.
func reset_tracking() -> void:
	_index = -1
	_lateral_offset = 0.0
	_reverse_time = 0.0
	_stuck_time = 0.0
	_last_progress_index = -1
	_no_progress_time = 0.0
