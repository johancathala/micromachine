extends RefCounted
class_name AIDriver

# ============================================================
# PILOTE IA GÉNÉRIQUE
# ============================================================
#
# Le même code pour tous les circuits et toutes les voitures ; seule
# la trajectoire (RacingLine) dépend du circuit.
#
# - Direction : suit la courbure de la trajectoire et corrige son
#   écart (poursuite pure d'un point devant pour la rejoindre de loin).
# - Vitesse : profil calculé pour la voiture : vitesse max dans chaque
#   virage (braquage + dérive du modèle de voiture), puis anticipation
#   des freinages. Recalculé quand les pneus s'usent.
# - Pneus (course avec usure) : mêmes règles que les joueurs. L'IA
#   choisit le tour où s'arrêter (AIPitStrategy), prend la voie des
#   stands, s'arrête dans la zone et joue le QTE.
# - Adversaires : ralentit derrière une voiture plus lente et tente de
#   la dépasser en se décalant du côté libre.
# - Problèmes : marche arrière si bloquée, réapparition si elle
#   n'avance plus du tout.
# - Difficulté : marge prise dans les virages et en ligne droite,
#   rapidité et précision au QTE du stand.
# ============================================================

enum Difficulty { NOVICE, MEDIUM, EXPERT }

# Fraction de la vitesse « limite » visée, selon la difficulté.
const PACE := [0.82, 0.92, 1.0]

# Marge de braquage gardée pour corriger la trajectoire.
static var steer_margin := 1.3
# Effet de sous-virage du modèle de voiture sur asphalte (Car.gd).
const ASPHALT_UNDERSTEER := 0.85
# Dérive : dans le modèle de voiture, l'adhérence ne ramène la vitesse
# dans l'axe que progressivement ; la courbure de chemin possible vaut
# au plus ~ adhérence x sinβ cosβ / vitesse. L'IA vise
# vitesse <= glisse x adhérence / courbure (0,5 = limite théorique du
# régime établi). En pratique, chaque voiture tient davantage : glisse
# calibrée par voiture sur Brissac (plus haute valeur sans sortie, avec
# une marge), DEFAULT_CORNER_SLIP pour une voiture inconnue.
const DEFAULT_CORNER_SLIP := 0.5
# Dans le trafic : glisse prudente (une voiture bousculée en pleine
# dérive part dans le décor), à moins de TRAFFIC_RANGE px.
const TRAFFIC_SLIP := 0.5
const TRAFFIC_RANGE := 220.0
# Calibrage valable pour le circuit où il a été mesuré : ailleurs
# (virages plus serrés...), DEFAULT_CORNER_SLIP, affiné par
# l'apprentissage des virages.
const CALIBRATED_TRACK := "res://level/track/Track01.tscn"
const CAR_CORNER_SLIP := {
	"clio": 1.3,
	"dacia": 1.0,
	"laguna": 0.7,
	"police": 0.7,
	"ferrari": 0.6,
	"f1": 1.2
}
# Essais : glisse imposée à toutes les voitures (< 0 : calibrage).
static var max_slip := -1.0
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
# Rejoindre la trajectoire de loin (au-delà de REJOIN_DISTANCE px : sortie,
# réapparition) : point visé proche, vitesse modérée.
const REJOIN_DISTANCE := 300.0
# Réapparition replacée sur la trajectoire si elle est à moins de ça (px).
const RESPAWN_SNAP_DISTANCE := 350.0
# Points de trajectoire parcourus au plus pour trouver de la route.
const RESPAWN_ROAD_SEARCH := 30
const REJOIN_LOOKAHEAD := 200.0
const REJOIN_SPEED := 600.0
const TRACKING_MAX_ANGLE := 0.7

# Adversaires.
const AVOID_RANGE := 380.0
const AVOID_CONE := 0.75
const OVERTAKE_OFFSET := 120.0
# Distance gardée au bord de la chaussée en dépassant (px).
const OVERTAKE_EDGE_MARGIN := 50.0

# Blocage.
# Garde-fou anti-collision : la trajectoire réelle de la voiture
# (position, vitesse, rotation en cours) est projetée jusqu'à sa distance
# de freinage ; si elle mène dans un obstacle dur alors que la voiture
# s'écarte de sa trajectoire (glisse, sous-virage, bousculade) ou que
# l'obstacle est tout proche, l'IA freine pour l'éviter.
const GUARD_STEP := 24.0
const GUARD_MAX_DISTANCE := 1400.0
const GUARD_HALF_WIDTH := 30.0
# Distance gardée devant l'obstacle (px).
const GUARD_MARGIN := 70.0
# Écart à la trajectoire (px, rad) à partir duquel la voiture « dérive ».
const GUARD_OFF_LINE := 60.0
const GUARD_OFF_ANGLE := 0.3
# Obstacle « tout proche » (px) : on freine même sur la trajectoire.
const GUARD_NEAR := 160.0
# Vitesse d'impact visée au pire (sous le seuil d'explosion de 700).
const GUARD_IMPACT_SPEED := 250.0
# Style : distance gardée au bord de la chaussée par le décalage propre.
const STYLE_EDGE_MARGIN := 70.0
# Route étroite (px de large) et virage très serré (courbure) : le style
# ne décale plus la trajectoire.
const STYLE_NARROW_WIDTH := 300.0
const STYLE_TIGHT_CURVATURE := 0.006
# Erreurs : fenêtre (points) avant / après le virage visé, courbure d'un
# virage, écart d'une sortie large (px), rotation d'un tête-à-queue.
const MISTAKE_BEFORE := 30
const MISTAKE_AFTER := 25
const MISTAKE_MIN_CURVATURE := 0.0025
const MISTAKE_WIDE_OFFSET := 160.0
const MISTAKE_SPIN := 3.2
# Freinage manqué : la voiture continue d'accélérer (gain à gravité 1).
const MISTAKE_LATE_BRAKE_GAIN := 1.12
# Gravité des erreurs selon le niveau (Novice, Moyen, Expert).
const MISTAKE_SEVERITY := [1.5, 1.0, 0.35]
const STUCK_SPEED := 40.0
const STUCK_DELAY := 1.0
# Manœuvre de dégagement : recul de REVERSE_MIN_TIME à REVERSE_MAX_TIME s,
# jusqu'à pointer vers la trajectoire (RECOVERY_AIM px devant) à moins de
# RECOVERY_ALIGNED rad avec RECOVERY_CLEARANCE px libres devant ; puis
# RECOVERY_TIME s de reprise vers ce point.
const REVERSE_MIN_TIME := 0.5
const REVERSE_MAX_TIME := 3.0
const RECOVERY_AIM := 250.0
const RECOVERY_ALIGNED := 0.45
const RECOVERY_CLEARANCE := 220.0
const RECOVERY_TIME := 1.2
const NO_PROGRESS_RESPAWN := 6.0

# Pneus : écart d'adhérence qui fait recalculer le profil de vitesse.
const TIRE_PROFILE_STEP := 0.03
# Stand : vitesse visée dans la voie (px/s), décision prise ce nombre
# de points avant l'entrée, abandon si le passage dure trop (s).
const PIT_LANE_SPEED := 900.0
# Fraction de la limite de la voie des stands visée par l'IA.
const PIT_LIMIT_MARGIN := 0.92
# Trajet du stand (chemin A* lissé, moins fluide que la trajectoire) :
# marge sur les vitesses de virage, et vitesse visée = minimum des
# prochains points (pas de relance au milieu d'un S).
const PIT_CORNER_MARGIN := 0.75
const PIT_SPEED_WINDOW := 8
# (assez tôt pour freiner depuis la vitesse max des voitures rapides).
const PIT_DECISION_POINTS := 130
const PIT_ROUTE_TIMEOUT := 30.0
# Trop loin du trajet du stand pendant ce temps (mauvais côté d'un
# muret...) : on renonce à l'arrêt pour ce tour.
const PIT_OFF_ROUTE_DISTANCE := 160.0
const PIT_OFF_ROUTE_TIME := 1.5
# QTE : délai entre deux flèches (s, min / max) et taux d'erreur.
const QTE_DELAY := [[0.32, 0.55], [0.22, 0.40], [0.15, 0.27]]
const QTE_ERROR_RATE := [0.05, 0.03, 0.01]
const QTE_HOLD := 0.06

## Réglages globaux (essais).
static func set_tuning(slip: float, margin: float) -> void:
	max_slip = slip
	steer_margin = margin


var car: Car = null
var line: RacingLine = null
# Parcours du circuit (obstacles durs pour le garde-fou).
var progress: TrackProgress = null
# Garde-fou : actif (Expert toujours ; suspendu pendant une erreur de
# pilotage), et statistiques.
var guard_enabled := true

# Style de pilotage (AIStyle) et variations propres au pilote.
var style: Dictionary = AIStyle.get_style(AIStyle.DEFAULT_ID)
var _rng := RandomNumberGenerator.new()
# Décalage latéral propre au pilote en chaque point (px, côté « plus »).
var _style_offset := PackedFloat32Array()
# Variation du tour en cours en chaque point (vitesse de passage).
var _style_corner := PackedFloat32Array()
var _pace_mul := 1.0
var _brake_mul := 1.0
var _style_lap := -1
# Erreur de pilotage en cours : {type, corner, sign, done} (vide : aucune).
var _mistake: Dictionary = {}
var mistake_count := 0
# Points du tour où une erreur est prévue (indices de la trajectoire).
var _mistake_points: Array[int] = []
var _mistake_travelled := 0
var _surfaces_seen := 0
var guard_count := 0
var _last_heading := 0.0
var _yaw_rate := 0.0
var difficulty: int = Difficulty.MEDIUM

# Course : participant piloté et nombre de tours (0 = illimité).
var participant: RaceParticipantState = null
var lap_count := 0

# Profil de vitesse (px/s) en chaque point de la trajectoire.
var speed_profile := PackedFloat32Array()
# Limites de virage précalculées (adhérence pleine) : braquage, dérive.
var _kinematic_limit := PackedFloat32Array()
var _grip_limit := PackedFloat32Array()
# Adhérence (effet des pneus) utilisée pour le profil actuel.
var _profile_grip := 1.0

# Stand.
var pit_line: RacingLine = null
var pit_entry_index := -1
var pit_exit_index := -1
var pit_stop_index := -1
# Limite de vitesse en chaque point du trajet du stand (0 : aucune).
var pit_speed_limits := PackedFloat32Array()
var strategy: AIPitStrategy = null
var pit_planned := false
var _pit_profile_stop := PackedFloat32Array()
var _pit_profile_go := PackedFloat32Array()
var _on_pit_route := false
var _pit_done := false
var _pit_route_time := 0.0
var _qte_timer := 0.0
var _qte_pressed := -1

# Ligne suivie (trajectoire ou passage au stand) et index sur celle-ci.
var _line: RacingLine = null
var _index := -1
var _previous_index := -1
var _lateral_offset := 0.0
var _stuck_time := 0.0
var _reverse_elapsed := 0.0
var _recovery_time := 0.0
var _reverse_time := 0.0
var _no_progress_time := 0.0
var _last_progress_index := -1

# Apprentissage des virages (AILearning) : facteur de vitesse par
# point de la trajectoire, pour ce circuit et cette voiture.
var learning_key := ""
# Circuit couru (chemin de la scène) : réglages propres au circuit.
var track_path := ""
var _safe_profile := PackedFloat32Array()
var _slip_override := -1.0
# Dernier point où la voiture suivait encore la trajectoire (perte de
# contrôle) : c'est là qu'il faut ralentir, pas où elle finit sa course.
const ON_LINE_DISTANCE := 150.0
var _last_on_line_index := -1
# Dernière perte de la trajectoire (index, et temps écoulé depuis) : la
# voiture peut la rejoindre avant de s'écraser ou de manquer une porte,
# c'est quand même ce virage-là qu'il faut ralentir.
const LINE_LOSS_MEMORY := 8.0
var _line_loss_index := -1
var _line_loss_age := INF
var _learned := PackedFloat32Array()
var _learned_version := -1

# Statistiques (réglages / tests).
var crash_count := 0
var respawn_count := 0
var pit_count := 0


func _init(p_car: Car, p_line: RacingLine, p_difficulty: int, p_track_path: String = "") -> void:
	car = p_car
	line = p_line
	track_path = p_track_path
	_line = line
	difficulty = clampi(p_difficulty, 0, PACE.size() - 1)
	_build_safe_profile()
	_precompute_corner_limits()
	speed_profile = build_profile(line, 1.0, 1.0)


## Style de pilotage et graine aléatoire du pilote (variations propres).
func set_style(style_id: String, seed: int) -> void:
	style = AIStyle.get_style(style_id)
	_rng.seed = seed
	_build_style_offsets()
	_roll_lap_variation()


## Décalage latéral propre au pilote : préférence intérieur / extérieur
## dans les virages, plus une dérive lente ; borné par la chaussée.
func _build_style_offsets() -> void:
	var count := line.points.size()
	var raw := PackedFloat32Array()
	raw.resize(count)
	var wander := float(style["wander"])
	var bias := float(style["line_bias"])
	var periods := [_rng.randf_range(50.0, 140.0), _rng.randf_range(18.0, 45.0)]
	var phases := [_rng.randf() * TAU, _rng.randf() * TAU]

	for i in range(count):
		# Courbure lissée : sens et force du virage autour du point.
		var k := 0.0

		for j in range(-6, 7):
			k += line.signed_curvature_at(i + j)

		k /= 13.0
		var turn := signf(k) * clampf(absf(k) * 300.0, 0.0, 1.0)
		var room_side := 0.0

		if not line.room_plus.is_empty():
			# Côté extérieur du virage = côté « plus » si turn > 0.
			room_side = line.room_plus[i] if turn * bias > 0.0 else line.room_minus[i]

		var offset := turn * bias * maxf(room_side - STYLE_EDGE_MARGIN, 0.0) * 0.7
		offset += wander * (0.6 * sin(TAU * i / periods[0] + phases[0]) + 0.4 * sin(TAU * i / periods[1] + phases[1]))
		raw[i] = offset * _style_freedom(i)

	_style_offset.resize(count)

	for i in range(count):
		var sum := 0.0

		for j in range(-5, 6):
			sum += raw[line.wrap_index(i + j)]

		var offset := sum / 11.0

		if not line.room_plus.is_empty():
			offset = clampf(
				offset,
				-maxf(line.room_minus[i] - STYLE_EDGE_MARGIN, 0.0),
				maxf(line.room_plus[i] - STYLE_EDGE_MARGIN, 0.0)
			)

		_style_offset[i] = offset


## Liberté de trajectoire en un point (0 à 1) : réduite sur une route
## étroite, dans un virage très serré et hors asphalte (on n'improvise
## pas sa trajectoire dans une chicane ou sur l'herbe).
func _style_freedom(index: int) -> float:
	var freedom := 1.0

	if not line.room_plus.is_empty():
		var width := line.room_plus[index] + line.room_minus[index]
		freedom = clampf((width - STYLE_NARROW_WIDTH) / STYLE_NARROW_WIDTH, 0.0, 1.0)

	var tightest := 0.0

	for j in range(-8, 9):
		tightest = maxf(tightest, line.curvature_at(index + j))

	freedom *= clampf((STYLE_TIGHT_CURVATURE - tightest) / STYLE_TIGHT_CURVATURE * 2.0, 0.0, 1.0)

	if line.surface_grip.size() == line.points.size() and line.surface_grip[index] < 0.999:
		freedom *= 0.3

	return freedom


## Variation du tour : vitesses de passage et points de freinage changent
## un peu d'un tour à l'autre (selon la régularité du style), rythme
## d'ensemble selon le style et le moment de la course.
func _roll_lap_variation() -> void:
	var count := line.points.size()
	var noise := float(style["noise"])
	_style_corner.resize(count)
	var step := 20
	var knots := PackedFloat32Array()

	for k in range(count / step + 2):
		knots.append(float(style["corner"]) * (1.0 + noise * _rng.randf_range(-1.0, 1.0)))

	for i in range(count):
		var k := i / step
		_style_corner[i] = lerpf(knots[k], knots[k + 1], float(i % step) / step)

	_pace_mul = float(style["pace"]) * (1.0 + noise * 0.3 * _rng.randf_range(-1.0, 1.0))
	_brake_mul = float(style["braking"]) * (1.0 + noise * _rng.randf_range(-1.0, 1.0))
	var push := float(style["finish_push"])

	if push > 0.0 and lap_count > 0:
		_pace_mul *= (1.0 + push) if _laps_remaining() <= 2 else (1.0 - push * 0.5)

	_plan_mistakes()
	_rebuild_speed_profile()


func _rebuild_speed_profile() -> void:
	if car.tire_wear_enabled:
		_profile_grip = tire_effect(car.tire_wear, car.worn_tire_grip)
		speed_profile = build_profile(line, _profile_grip, tire_effect(car.tire_wear, car.worn_tire_brake))
	else:
		_profile_grip = 1.0
		speed_profile = build_profile(line, 1.0, 1.0)


func _style_offset_at(index: int) -> float:
	if _style_offset.size() != line.points.size() or _line != line:
		return 0.0

	return _style_offset[line.wrap_index(index)]


## Profil prudent (trafic) : glisse TRAFFIC_SLIP, sans apprentissage.
func _build_safe_profile() -> void:
	if corner_slip() <= TRAFFIC_SLIP:
		return

	_slip_override = TRAFFIC_SLIP
	_precompute_corner_limits()
	_safe_profile = build_profile(line, 1.0, 1.0)
	_slip_override = -1.0


## Passage au stand (course avec usure des pneus) : trajet calculé par
## TrackProgress.build_pit_route.
func setup_pit(route: Dictionary) -> void:
	if route.is_empty():
		return

	pit_line = RacingLine.open_path(route["points"], "passage au stand")
	pit_entry_index = int(route["entry_index"])
	pit_exit_index = int(route["exit_index"])
	pit_stop_index = int(route["stop_index"])
	pit_speed_limits = route.get("speed_limits", PackedFloat32Array())
	strategy = AIPitStrategy.new(self)


# ------------------------------------------------------------
# Profil de vitesse
# ------------------------------------------------------------

func _precompute_corner_limits() -> void:
	var count := line.points.size()
	_kinematic_limit.resize(count)
	_grip_limit.resize(count)

	var surfaces := line.surface_grip.size() == count

	for i in range(count):
		var k := line.curvature[i]
		# Hors piste (herbe...) : braquage moins efficace (le virage
		# nécessaire paraît plus serré) et adhérence bien plus faible.
		var steer := line.surface_steer[i] if surfaces else 1.0
		_kinematic_limit[i] = _kinematic_speed(k / maxf(steer, 0.1))
		_grip_limit[i] = _grip_speed(k) * (line.surface_grip[i] if surfaces else 1.0)


## Profil de vitesse d'une ligne avec une adhérence et un freinage
## réduits (pneus usés). Trajet ouvert : vitesse modérée dans la voie,
## arrêt complet à `stop_index` (si >= 0), vitesse de la trajectoire
## au point de sortie.
func build_profile(
	target: RacingLine,
	grip_scale: float,
	brake_scale: float,
	stop_index: int = -1
) -> PackedFloat32Array:
	var count := target.points.size()
	var profile := PackedFloat32Array()
	profile.resize(count)

	var pace: float = PACE[difficulty] * _pace_mul
	var top_speed := car.max_speed * pace
	var precomputed := target == line

	for i in range(count):
		var corner: float

		if precomputed:
			corner = minf(_kinematic_limit[i], _grip_limit[i] * grip_scale)

			if not _learned.is_empty():
				corner *= _learned[i]

			if _style_corner.size() == count:
				corner *= _style_corner[i]
		else:
			var k := target.curvature[i]
			corner = minf(_kinematic_speed(k), _grip_speed(k) * grip_scale)

		if not target.closed:
			corner *= PIT_CORNER_MARGIN

		profile[i] = minf(maxf(corner, MIN_CORNER_SPEED) * pace, top_speed)

	if not target.closed:
		for i in range(4, count - 4):
			profile[i] = minf(profile[i], PIT_LANE_SPEED)

		# Voie des stands limitée : un peu sous la limite (le freinage
		# anticipé ci-dessous ralentit avant d'y entrer).
		if target == pit_line and pit_speed_limits.size() == count:
			for i in range(count):
				if pit_speed_limits[i] > 0.0:
					profile[i] = minf(profile[i], pit_speed_limits[i] * PIT_LIMIT_MARGIN)

		# Arrêt : vitesse nulle à partir de ce point (si la voiture le
		# dépasse un peu, elle s'arrête quand même dans la zone).
		if stop_index >= 0:
			for i in range(stop_index, count):
				profile[i] = 0.0

		if stop_index < 0 and speed_profile.size() > 0 and pit_exit_index >= 0:
			profile[count - 1] = minf(profile[count - 1], speed_profile[pit_exit_index])

	# Anticipation des freinages (à rebours ; deux passes sur une boucle).
	var decel := car.brake_force * BRAKE_EFFICIENCY * brake_scale * _brake_mul

	for _pass in range(2 if target.closed else 1):
		for step in range(count):
			var i := count - 1 - step

			if not target.closed and i == count - 1:
				continue

			var next := profile[(i + 1) % count]
			# Freinage plus faible hors piste (point suivant sur l'herbe...).
			var surface_decel := decel

			if target.surface_brake.size() == count:
				surface_decel *= target.surface_brake[(i + 1) % count]

			var reachable := sqrt(next * next + 2.0 * surface_decel * RacingLine.SPACING)

			if profile[i] > reachable:
				profile[i] = reachable

	return profile


## Limite de braquage : le braquage efficace baisse avec la vitesse.
func _kinematic_speed(k: float) -> float:
	if k < 0.00005:
		return car.max_speed

	# Braquage nécessaire : tan(angle) = courbure * empattement.
	var needed_angle := atan(k * car.wheel_base)
	var needed_response := needed_angle / (car.max_steer_angle * ASPHALT_UNDERSTEER * steer_margin)

	if needed_response > car.steering_response_low_speed:
		return MIN_CORNER_SPEED

	if needed_response > car.steering_response_high_speed:
		var t := (car.steering_response_low_speed - needed_response) / maxf(
			car.steering_response_low_speed - car.steering_response_high_speed, 0.001
		)
		return lerpf(car.steering_high_speed_start, car.steering_high_speed_end, t)

	return car.max_speed


## Limite de dérive : v = glisse_max * adhérence(v) / courbure,
## l'adhérence baissant avec la vitesse (résolution itérative).
func _grip_speed(k: float) -> float:
	if k < 0.00005:
		return car.max_speed

	var speed := car.max_speed

	var slip := corner_slip()

	for _i in range(8):
		speed = slip * _grip_at(speed) / k

	return speed


## Glisse visée en virage pour cette voiture.
func corner_slip() -> float:
	if _slip_override > 0.0:
		return _slip_override

	if max_slip > 0.0:
		return max_slip

	if track_path != CALIBRATED_TRACK:
		return DEFAULT_CORNER_SLIP

	var car_id := car.definition.id if car.definition != null else ""
	return float(CAR_CORNER_SLIP.get(car_id, DEFAULT_CORNER_SLIP))


## Adhérence latérale de la voiture à une vitesse donnée (Car.gd).
func _grip_at(speed: float) -> float:
	var t := inverse_lerp(car.high_speed_grip_start, car.high_speed_grip_end, speed)
	return lerpf(car.lateral_grip, car.lateral_grip_at_high_speed, clampf(t, 0.0, 1.0))


## Effet des pneus (comme Car._tire_effect) pour une usure donnée.
func tire_effect(wear: float, worn_value: float) -> float:
	if wear <= car.tire_degradation_start:
		return 1.0

	var degradation := (wear - car.tire_degradation_start) / maxf(1.0 - car.tire_degradation_start, 0.001)
	return lerpf(1.0, worn_value, clampf(degradation, 0.0, 1.0))


## Pneus usés : le profil suit la perte d'adhérence et de freinage.
func _refresh_tire_profile() -> void:
	var learned_changed := _refresh_learning()

	if not car.tire_wear_enabled:
		if learned_changed:
			speed_profile = build_profile(line, 1.0, 1.0)
		return

	var grip := tire_effect(car.tire_wear, car.worn_tire_grip)

	if absf(grip - _profile_grip) < TIRE_PROFILE_STEP and not learned_changed:
		return

	_profile_grip = grip
	speed_profile = build_profile(line, grip, tire_effect(car.tire_wear, car.worn_tire_brake))


## Virages appris (par cette IA ou une autre de la même voiture) :
## true si les facteurs ont changé.
func _refresh_learning() -> bool:
	if learning_key.is_empty():
		return false

	var current := AILearning.version(learning_key)

	if current == _learned_version:
		return false

	_learned_version = current
	_learned = AILearning.factors(learning_key, line)
	return true


## Détruite seule contre un obstacle : ralentir la portion qui précède
## (sur la trajectoire, pas dans la voie des stands).
func on_crash() -> void:
	crash_count += 1

	# Sortie due à une erreur de pilotage voulue : rien à apprendre.
	if not _mistake.is_empty():
		_mistake.clear()
		return

	if learning_key.is_empty() or _on_pit_route:
		return

	var index := _line_loss_index if _line_loss_age < LINE_LOSS_MEMORY else _last_on_line_index

	if index < 0:
		return

	AILearning.record_crash(learning_key, line, index)
	_line_loss_age = INF


func _overtake() -> float:
	return float(style["overtake"])


## Erreurs de pilotage : au début de chaque tour, leur nombre est tiré
## (loi de Poisson calibrée sur AIStyle.CLEAN_LAPS, modulée par le style)
## et placé au hasard sur le tour ; chacune vise le virage qui suit. En
## Novice et Moyen, le garde-fou est suspendu pendant l'erreur (elle
## peut finir dans le décor) ; en Expert, elle reste légère.
func _plan_mistakes() -> void:
	_mistake_points.clear()
	var clean := clampf(float(AIStyle.CLEAN_LAPS[difficulty]), 0.01, 1.0)
	var mean := -log(clean) * float(style["mistakes"])

	# Tirage de Poisson (méthode de Knuth).
	var limit := exp(-mean)
	var product := _rng.randf()
	var count := 0

	while product > limit and count < 6:
		count += 1
		product *= _rng.randf()

	# Distances (en points de trajectoire) depuis le début du tour où
	# chaque erreur se déclenche ; elles sont toutes jouées dans le tour.
	_mistake_travelled = 0

	for _i in range(count):
		_mistake_points.append(_rng.randi_range(5, int(line.points.size() * 0.85)))

	_mistake_points.sort()


func _update_mistake() -> void:
	# Distance parcourue sur la trajectoire depuis le début du tour.
	if _previous_index >= 0:
		var advanced := posmod(_index - _previous_index, line.points.size())

		if advanced < 20:
			_mistake_travelled += advanced

	if not _mistake.is_empty():
		var relative := _relative_index(int(_mistake["corner"]))

		if relative > MISTAKE_AFTER or relative < -MISTAKE_BEFORE * 3:
			_mistake.clear()

		return

	if _mistake_points.is_empty() or not car.car_can_move:
		return

	# Erreur prévue atteinte (les suivantes attendent la fin de celle-ci) :
	# au prochain virage marqué.
	if _mistake_travelled < _mistake_points[0]:
		return

	_mistake_points.remove_at(0)

	for ahead in range(MISTAKE_BEFORE, MISTAKE_BEFORE + 200):
		var corner := line.wrap_index(_index + ahead)

		if line.curvature[corner] > MISTAKE_MIN_CURVATURE:
			var roll := _rng.randf()
			var type := "hesitation"

			if difficulty == Difficulty.EXPERT:
				# Expert : erreurs légères (hésitation, trajectoire imprécise).
				type = "hesitation" if roll < 0.5 else "wide"
			elif roll < 0.45:
				type = "late_brake"
			elif roll < 0.75:
				type = "wide"
			elif roll < 0.9 and difficulty == Difficulty.NOVICE:
				type = "spin"

			_mistake = {
				"type": type,
				"corner": corner,
				"sign": signf(line.signed_curvature_at(corner)),
				"done": false
			}
			mistake_count += 1
			return


## Indice relatif (signé) d'un point de la ligne par rapport à la voiture.
func _relative_index(index: int) -> int:
	var count := line.points.size()
	var relative := posmod(_index - index, count)
	return relative - count if relative > count / 2 else relative


## Effet de l'erreur en cours sur la conduite.
func _mistake_effect(speed: float) -> Dictionary:
	var effect := {"min_speed": 0.0, "speed_scale": 1.0, "offset": 0.0, "no_guard": false}

	if _mistake.is_empty() or _on_pit_route:
		return effect

	var relative := _relative_index(int(_mistake["corner"]))
	var severity: float = MISTAKE_SEVERITY[difficulty]
	var outward := float(_mistake["sign"]) * MISTAKE_WIDE_OFFSET * severity
	var guard_off := difficulty != Difficulty.EXPERT

	match String(_mistake["type"]):
		"late_brake":
			# Freine trop tard : garde sa vitesse jusqu'au virage.
			if relative >= -MISTAKE_BEFORE and relative < -4:
				effect["min_speed"] = speed * (1.0 + (MISTAKE_LATE_BRAKE_GAIN - 1.0) * severity)
			effect["no_guard"] = guard_off and relative >= -MISTAKE_BEFORE

		"wide":
			# Sort large du virage.
			if relative >= -6:
				effect["offset"] = outward
				effect["speed_scale"] = 1.0 + 0.1 * severity
				effect["no_guard"] = guard_off

		"spin":
			# Perd l'arrière à la corde : tête-à-queue.
			if relative >= -2 and not bool(_mistake["done"]):
				_mistake["done"] = true
				car._add_impact_spin(float(_mistake["sign"]) * MISTAKE_SPIN)
			effect["no_guard"] = guard_off and relative >= -2

		"hesitation":
			# Hésite : lève le pied.
			if relative >= -12:
				effect["speed_scale"] = 1.0 - 0.4 * minf(severity, 1.0)

	return effect


## Durée (s) pour parcourir un profil entre deux indices.
static func profile_time(profile: PackedFloat32Array, from_index: int, to_index: int, closed: bool) -> float:
	var count := profile.size()
	var total := 0.0
	var steps := posmod(to_index - from_index, count) if closed else to_index - from_index

	for step in range(steps):
		total += RacingLine.SPACING / maxf(profile[(from_index + step) % count], 80.0)

	return total


# ------------------------------------------------------------
# Pilotage (appelé à chaque image physique par la voiture)
# ------------------------------------------------------------

func update(delta: float) -> void:
	if line == null or not line.is_valid():
		return

	# Surfaces de la trajectoire : mesurées une fois la physique prête,
	# puis vitesses recalculées.
	if progress != null and line.surfaces_version == 0:
		line.measure_surfaces(progress)

	if line.surfaces_version != _surfaces_seen:
		_surfaces_seen = line.surfaces_version
		_build_safe_profile()
		_precompute_corner_limits()
		_build_style_offsets()
		_rebuild_speed_profile()

		if strategy != null:
			strategy = AIPitStrategy.new(self)

	var position := car.global_position
	var speed := car.velocity.length()

	_refresh_tire_profile()

	_previous_index = _index
	var heading := Vector2.RIGHT.rotated(car.global_rotation)
	_index = _line.closest_index(position, _index, 60, heading)

	# Loin de la ligne (réapparition, grosse sortie) : recherche sur
	# toute la ligne.
	if position.distance_to(_line.point(_index)) > 500.0:
		_index = _line.closest_index(position, -1, 60, heading)
		_previous_index = -1

	if participant != null and participant.current_lap != _style_lap:
		_style_lap = participant.current_lap
		_roll_lap_variation()

	if _on_pit_route:
		_update_pit_route(delta)
	else:
		_update_pit_plan()
		_update_mistake()

		_line_loss_age += delta

		if position.distance_to(line.point(_index)) < ON_LINE_DISTANCE:
			_last_on_line_index = _index
		elif _last_on_line_index >= 0 and _line_loss_age > 1.0:
			# Vient de quitter la trajectoire.
			_line_loss_index = _last_on_line_index
			_line_loss_age = 0.0

	var profile := speed_profile

	if _on_pit_route:
		profile = _pit_profile_go if _pit_done else _pit_profile_stop

	# ---- Point visé, décalé pour dépasser si besoin ----
	var lookahead := clampf(LOOKAHEAD_BASE + LOOKAHEAD_SPEED * speed, LOOKAHEAD_BASE, LOOKAHEAD_MAX)
	var target_speed := profile[_line.wrap_index(_index + 2)]

	# Loin de la trajectoire (sortie, réapparition) : la rejoindre par le
	# plus court et sans hâte, plutôt que viser loin devant à travers le
	# décor.
	var wanted_point := _line.point(_index) + _line.direction(_index).orthogonal() * _lateral_offset

	if not _on_pit_route and position.distance_to(wanted_point) > REJOIN_DISTANCE:
		lookahead = REJOIN_LOOKAHEAD
		target_speed = minf(target_speed, REJOIN_SPEED)

	var target_index := _index + int(lookahead / RacingLine.SPACING)

	if _on_pit_route:
		for ahead in range(PIT_SPEED_WINDOW):
			target_speed = minf(target_speed, profile[_line.wrap_index(_index + ahead)])

	# Arrêt prévu : freiner à temps pour la vitesse d'entrée des stands.
	if pit_planned and not _on_pit_route:
		target_speed = minf(target_speed, _pit_entry_speed_cap())

	var avoid := _avoid_cars(speed)
	target_speed = minf(target_speed, avoid["speed_cap"])

	# Dans le trafic (contacts possibles), vitesse de virage prudente
	# (sauf pilotes audacieux).
	if (
		bool(avoid["traffic"]) and not _on_pit_route and not _safe_profile.is_empty()
		and float(style["traffic_care"]) >= 0.5
	):
		target_speed = minf(target_speed, _safe_profile[_line.wrap_index(_index + 2)])

	var wanted_offset: float = 0.0 if _on_pit_route else float(avoid["offset"]) + _style_offset_at(target_index)

	# Erreur de pilotage en cours.
	var mistake := _mistake_effect(speed)
	target_speed = maxf(target_speed, mistake["min_speed"]) if mistake["min_speed"] > 0.0 else target_speed
	target_speed *= mistake["speed_scale"]

	# Pas de décalage au-delà de la chaussée (arbres, murs...).
	if not _on_pit_route and not line.room_plus.is_empty():
		var room_index := line.wrap_index(target_index)
		wanted_offset = clampf(
			wanted_offset,
			-maxf(line.room_minus[room_index] - OVERTAKE_EDGE_MARGIN, 0.0),
			maxf(line.room_plus[room_index] - OVERTAKE_EDGE_MARGIN, 0.0)
		)
	# Sortie large (erreur) : au-delà du bord de la chaussée.
	wanted_offset += mistake["offset"]
	_lateral_offset = move_toward(_lateral_offset, wanted_offset, 300.0 * delta)

	var target := _line.point(target_index)

	if absf(_lateral_offset) > 1.0:
		target += _line.direction(target_index).orthogonal() * _lateral_offset

	# ---- Direction ----
	var to_target := target - position
	var alpha := wrapf(to_target.angle() - car.global_rotation, -PI, PI)
	var distance := maxf(to_target.length(), 1.0)
	# Poursuite pure : sert loin de la trajectoire (rejoindre la ligne).
	var path_curvature := 2.0 * sin(alpha) / distance

	# Sur la ligne : sa courbure (anticipée du délai de braquage et du
	# retard d'adhérence) + correction de l'écart latéral et de l'angle.
	# Contrairement à la poursuite pure, ne coupe pas les virages.
	var grip_lag := 1.0 / maxf(_grip_at(speed), 0.5)
	var preview_index := _index + int(speed * (STEER_PREVIEW_TIME + GRIP_LAG_FACTOR * grip_lag) / RacingLine.SPACING)
	var line_direction := _line.direction(_index)
	var normal := line_direction.orthogonal()
	var lateral_error := (position - _line.point(_index)).dot(normal) - _lateral_offset
	var heading_error := wrapf(car.global_rotation - line_direction.angle(), -PI, PI)

	if absf(lateral_error) < TRACKING_MAX_ERROR and absf(heading_error) < TRACKING_MAX_ANGLE:
		var preview := clampf(TRACKING_BASE + TRACKING_SPEED * speed, TRACKING_BASE, TRACKING_MAX)
		path_curvature = (
			_line.signed_curvature_at(preview_index)
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
	elif speed > target_speed + 30.0 and speed > 120.0:
		# Freiner seulement en roulant (sinon c'est la marche arrière).
		brake = clampf((speed - target_speed) / 250.0, 0.25, 1.0)

	# Grosse erreur d'angle (après un tête-à-queue...) : on ralentit.
	if absf(alpha) > 1.2 and speed > 250.0:
		throttle = 0.0

	# ---- Blocage : marche arrière, puis réapparition ----
	if not _on_pit_route:
		_update_stuck(delta, speed)

	# Manœuvre de dégagement : recul en braquant pour pointer vers la
	# trajectoire, jusqu'à être orientée vers elle avec la voie libre
	# devant (épingle trop serrée, voiture plantée contre un obstacle).
	if _reverse_time > 0.0:
		_reverse_time -= delta
		_reverse_elapsed += delta
		var aim := _line.point(_index + int(RECOVERY_AIM / RacingLine.SPACING)) - position
		var aim_angle := wrapf(aim.angle() - car.global_rotation, -PI, PI)
		var forward := Vector2.RIGHT.rotated(car.global_rotation)
		var clear := progress == null or _hazard_distance(position, forward * 300.0, RECOVERY_CLEARANCE) == INF

		if _reverse_elapsed > REVERSE_MIN_TIME and absf(aim_angle) < RECOVERY_ALIGNED and clear:
			_reverse_time = 0.0
			_recovery_time = RECOVERY_TIME
		elif _reverse_elapsed > REVERSE_MIN_TIME and speed < STUCK_SPEED * 0.5 and _reverse_elapsed > 1.2:
			# Butée en reculant : on repart en avant.
			_reverse_time = 0.0
			_recovery_time = RECOVERY_TIME

		throttle = 0.0
		brake = 1.0
		# En marche arrière, braquer à l'opposé fait pivoter le nez vers
		# la cible.
		steer = -signf(aim_angle)

	# Juste après un dégagement : viser plus loin sur la trajectoire, à
	# vitesse modérée, le temps de s'y replacer.
	if _recovery_time > 0.0 and _reverse_time <= 0.0:
		_recovery_time -= delta
		var aim := _line.point(_index + int(RECOVERY_AIM / RacingLine.SPACING)) - position
		var aim_angle := wrapf(aim.angle() - car.global_rotation, -PI, PI)
		steer = clampf(aim_angle * 2.0, -1.0, 1.0)

		if speed > REJOIN_SPEED:
			throttle = 0.0

	# ---- Garde-fou anti-collision ----
	var heading_now := car.global_rotation
	_yaw_rate = wrapf(heading_now - _last_heading, -PI, PI) / maxf(delta, 0.001)
	_last_heading = heading_now

	if guard_enabled and not mistake["no_guard"] and progress != null and _reverse_time <= 0.0 and speed > 150.0:
		var drifting := absf(lateral_error) > GUARD_OFF_LINE or absf(
			wrapf(car.velocity.angle() - line_direction.angle(), -PI, PI)
		) > GUARD_OFF_ANGLE
		var decel := _effective_decel()
		var stopping := speed * speed / (2.0 * decel)
		var hazard := _hazard_distance(position, car.velocity, minf(stopping * 1.3 + 200.0, GUARD_MAX_DISTANCE))

		if hazard < INF and (drifting or hazard < GUARD_NEAR):
			var room := maxf(hazard - GUARD_MARGIN, 0.0)
			var allowed := sqrt(GUARD_IMPACT_SPEED * GUARD_IMPACT_SPEED + 2.0 * decel * room)

			if speed > allowed:
				throttle = 0.0
				brake = 1.0
				guard_count += 1

	car.throttle = throttle
	car.brake = brake
	car.steer_input = clampf(steer, -1.0, 1.0)
	car.handbrake = false


## Décélération réelle au freinage, selon la surface sous la voiture.
func _effective_decel() -> float:
	var surface_brake := car._surface.brake_mul if car._surface != null else 1.0
	return maxf(car.brake_force * BRAKE_EFFICIENCY * surface_brake, 100.0)


## Distance (px) jusqu'au premier obstacle dur sur la trajectoire réelle
## projetée (arc de la rotation en cours), INF si aucun avant `limit`.
func _hazard_distance(origin: Vector2, velocity: Vector2, limit: float) -> float:
	var speed := velocity.length()

	if speed < 1.0:
		return INF

	var direction := velocity / speed
	var curvature := clampf(_yaw_rate / speed, -0.01, 0.01)
	var point := origin
	var travelled := 0.0

	while travelled < limit:
		direction = direction.rotated(curvature * GUARD_STEP)
		point += direction * GUARD_STEP
		travelled += GUARD_STEP
		var side := direction.orthogonal() * GUARD_HALF_WIDTH

		for probe in [point, point + side, point - side]:
			if progress.hard_cells.has(progress.world_to_cell(probe)):
				return travelled

	return INF


func _steering_response(speed: float) -> float:
	var t := inverse_lerp(car.steering_high_speed_start, car.steering_high_speed_end, speed)
	return lerpf(car.steering_response_low_speed, car.steering_response_high_speed, clampf(t, 0.0, 1.0))


# ------------------------------------------------------------
# Stand
# ------------------------------------------------------------

## A-t-on franchi l'indice `target` de la trajectoire depuis l'image
## précédente ?
func _passed(target: int) -> bool:
	if _previous_index < 0:
		return false

	var count := line.points.size()
	var moved := posmod(_index - _previous_index, count)
	var to_target := posmod(target - _previous_index, count)
	return moved < count / 2 and to_target > 0 and to_target <= moved


func _update_pit_plan() -> void:
	if pit_line == null or strategy == null or not car.tire_wear_enabled:
		return

	var count := line.points.size()

	# Réarmée à l'opposé du circuit : une décision par tour, même après
	# une réapparition en arrière.
	if _passed((pit_entry_index + count / 2) % count):
		_decision_armed = true

	# Une fois par tour, avant l'entrée des stands : décision.
	if _decision_armed and _passed(posmod(pit_entry_index - PIT_DECISION_POINTS, count)):
		_decision_armed = false
		pit_planned = strategy.decide(car.tire_wear, _laps_remaining())

		if pit_planned:
			_prepare_pit_profiles()

	if pit_planned and _passed(pit_entry_index):
		_enter_pit_route()


func _laps_remaining() -> int:
	if lap_count <= 0 or participant == null:
		return 99

	return maxi(lap_count - participant.current_lap, 0)


func _prepare_pit_profiles() -> void:
	var grip := tire_effect(car.tire_wear, car.worn_tire_grip)
	_pit_brake_scale = tire_effect(car.tire_wear, car.worn_tire_brake)
	_pit_profile_stop = build_profile(pit_line, grip, _pit_brake_scale, pit_stop_index)
	_pit_profile_go = build_profile(pit_line, 1.0, 1.0)


var _pit_brake_scale := 1.0
var _decision_armed := true


## Vitesse max sur la trajectoire pour arriver à l'entrée des stands à
## la vitesse prévue par le trajet du stand.
func _pit_entry_speed_cap() -> float:
	if _pit_profile_stop.is_empty():
		return INF

	var count := line.points.size()
	var points_left := posmod(pit_entry_index - _index, count)

	if points_left > count / 2:
		return INF

	var entry_speed := _pit_profile_stop[0]
	var decel := car.brake_force * BRAKE_EFFICIENCY * _pit_brake_scale
	return sqrt(entry_speed * entry_speed + 2.0 * decel * points_left * RacingLine.SPACING)


func _enter_pit_route() -> void:
	if _pit_profile_stop.is_empty():
		_prepare_pit_profiles()

	_on_pit_route = true
	_pit_done = false
	_pit_route_time = 0.0
	_pit_off_route_time = 0.0
	_pit_missed_time = 0.0
	_line = pit_line
	_index = pit_line.closest_index(car.global_position, 0, 8)
	_previous_index = -1


func _update_pit_route(delta: float) -> void:
	_pit_route_time += delta

	# Passage interminable (bloquée...) : on renonce.
	if _pit_route_time > PIT_ROUTE_TIMEOUT:
		_leave_pit_route()
		return

	if car.global_position.distance_to(pit_line.point(_index)) > PIT_OFF_ROUTE_DISTANCE:
		_pit_off_route_time += delta

		if _pit_off_route_time > PIT_OFF_ROUTE_TIME:
			_leave_pit_route()
			return
	else:
		_pit_off_route_time = 0.0

	# Arrêtée sans changement de pneus (zone manquée) : on repart.
	if not _pit_done and _index >= pit_stop_index - 6 and car.velocity.length() < 30.0 and car.car_can_move:
		_pit_missed_time += delta

		if _pit_missed_time > 1.0:
			_pit_done = true
	else:
		_pit_missed_time = 0.0

	if _index >= pit_line.points.size() - 2:
		_leave_pit_route()


var _pit_missed_time := 0.0
var _pit_off_route_time := 0.0


func _leave_pit_route() -> void:
	_on_pit_route = false
	pit_planned = false
	_line = line
	_index = line.closest_index(car.global_position, pit_exit_index, 20)
	_previous_index = -1
	_last_progress_index = -1
	_no_progress_time = 0.0


## Appelé par PitStopManager : pneus changés.
func on_pit_finished() -> void:
	_pit_done = true
	pit_planned = false
	pit_count += 1
	_profile_grip = 1.0
	speed_profile = build_profile(line, 1.0, 1.0)

	if strategy != null:
		strategy.on_pit_finished()


## QTE du stand : « appuie » sur la flèche demandée après un délai de
## réaction (selon la difficulté), parfois sur une mauvaise.
func qte_direction(expected: int, delta: float) -> int:
	_qte_timer -= delta

	if _qte_timer > 0.0:
		return _qte_pressed

	if _qte_pressed >= 0:
		# Relâcher, puis attendre avant la flèche suivante.
		_qte_pressed = -1
		var delay: Array = QTE_DELAY[difficulty]
		_qte_timer = randf_range(float(delay[0]), float(delay[1]))
		return -1

	_qte_pressed = expected

	if randf() < float(QTE_ERROR_RATE[difficulty]):
		_qte_pressed = (expected + randi_range(1, 3)) % 4

	_qte_timer = QTE_HOLD
	return _qte_pressed


## Durée moyenne estimée du QTE (s), pour la stratégie.
func estimated_qte_time(length: int) -> float:
	var delay: Array = QTE_DELAY[difficulty]
	var per_arrow := (float(delay[0]) + float(delay[1])) / 2.0 + QTE_HOLD
	# Une erreur fait recommencer : en moyenne la moitié de la séquence.
	var error: float = QTE_ERROR_RATE[difficulty]
	return length * per_arrow * (1.0 + error * length / 2.0)


# ------------------------------------------------------------
# Adversaires
# ------------------------------------------------------------

## Voiture devant, dans l'axe : ralentir à sa vitesse si elle est
## proche, sinon se décaler du côté libre pour la dépasser.
func _avoid_cars(speed: float) -> Dictionary:
	var result := {"speed_cap": INF, "offset": 0.0, "traffic": false}
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

		# Voiture toute proche, devant ou à côté : prudence en virage.
		if gap < TRAFFIC_RANGE and forward.dot(to_other) > -TRAFFIC_RANGE * 0.3:
			result["traffic"] = true

		if gap > AVOID_RANGE * _overtake() or gap < 1.0:
			continue

		if forward.dot(to_other / gap) < AVOID_CONE:
			continue

		var other_speed := other.velocity.dot(forward)

		if other_speed >= speed - 20.0 or gap >= closest:
			continue

		closest = gap
		# Côté de l'adversaire par rapport à nous : on passe de l'autre.
		var side := signf(forward.orthogonal().dot(to_other))
		result["offset"] = (-side if side != 0.0 else 1.0) * OVERTAKE_OFFSET * clampf(_overtake(), 0.7, 1.4)

		# Trop près : on calque sa vitesse pour ne pas le percuter.
		if gap < AVOID_RANGE * 0.45 / clampf(_overtake(), 0.8, 1.5):
			result["speed_cap"] = maxf(other_speed * 0.95, 0.0)

	return result


# ------------------------------------------------------------
# Blocage
# ------------------------------------------------------------

func _update_stuck(delta: float, speed: float) -> void:
	if not car.car_can_move:
		_stuck_time = 0.0
		_no_progress_time = 0.0
		return

	# Bloquée (mur, voiture...) : marche arrière brève.
	if speed < STUCK_SPEED and _reverse_time <= 0.0:
		_stuck_time += delta

		if _stuck_time > STUCK_DELAY:
			_reverse_time = REVERSE_MAX_TIME
			_reverse_elapsed = 0.0
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0

	# N'avance plus sur la trajectoire : réapparition.
	var count := line.points.size()
	var advance := posmod(_index - _last_progress_index, count)

	if _last_progress_index < 0 or (advance > 3 and advance < count / 2):
		_last_progress_index = _index
		_no_progress_time = 0.0
	else:
		_no_progress_time += delta

	if _no_progress_time > NO_PROGRESS_RESPAWN:
		_no_progress_time = 0.0
		_last_progress_index = -1
		respawn_count += 1
		# Bloquée hors de sa trajectoire : comme une sortie de route, elle
		# apprend à ralentir là où elle l'a perdue.
		on_crash()
		car.explosion()


## Après une réapparition : reprendre la trajectoire au plus près.
## `on_line` (réapparition) : la voiture est replacée sur sa trajectoire,
## au point le plus proche du point de reprise et dans le sens de la
## course (un point de reprise mal orienté l'enverrait dans le décor).
func reset_tracking(on_line: bool = false) -> void:
	if _on_pit_route:
		_on_pit_route = false
		_line = line

	if on_line and line != null and line.is_valid():
		var nearest := line.closest_index(car.global_position)

		if car.global_position.distance_to(line.points[nearest]) <= RESPAWN_SNAP_DISTANCE:
			# Hors piste (herbe...), on braque mal à l'arrêt : départ sur
			# le premier point de route qui suit.
			if line.surface_grip.size() == line.points.size():
				for step in range(RESPAWN_ROAD_SEARCH):
					if line.surface_grip[line.wrap_index(nearest + step)] >= 0.999:
						nearest = line.wrap_index(nearest + step)
						break

			car.global_position = line.points[nearest]
			car.global_rotation = line.direction(nearest).angle()

	_index = -1
	_previous_index = -1
	_last_on_line_index = -1
	_line_loss_index = -1
	_line_loss_age = INF
	_lateral_offset = 0.0
	_reverse_time = 0.0
	_stuck_time = 0.0
	_last_progress_index = -1
	_no_progress_time = 0.0
