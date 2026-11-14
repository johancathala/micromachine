extends RefCounted
class_name AIPitStrategy

# ============================================================
# STRATÉGIE DE CHANGEMENT DE PNEUS (IA)
# ============================================================
#
# Une fois par tour, juste avant l'entrée des stands, l'IA compare :
#   - rester en piste : le tour suivant coûte d'autant plus de temps
#     que les pneus sont usés (adhérence et freinage réduits) ;
#   - s'arrêter maintenant : coût du passage au stand (détour par la
#     voie, arrêt, QTE), puis des pneus neufs.
# Le meilleur choix sur les tours restants est calculé par
# programmation dynamique (plusieurs arrêts possibles sur une longue
# course, aucun s'il ne reste qu'un tour ou deux).
#
# Temps au tour selon l'usure : profil de vitesse de l'IA recalculé
# avec l'effet des pneus (Car._tire_effect). Usure par tour : mesurée
# d'un tour à l'autre (estimée au départ).
# ============================================================

const WEAR_STEP := 0.05
# Course à tours illimités : horizon de calcul.
const MAX_HORIZON := 20
# Glisse moyenne en course (usure accélérée par la glisse).
const EXPECTED_SLIP_FACTOR := 1.3
# Temps perdu à l'arrêt et à la relance, au-delà du profil (s).
const STOP_OVERHEAD := 1.5

var driver: AIDriver = null

# Temps au tour perdu (s) selon l'usure en début de tour (pas WEAR_STEP).
var _lap_loss := PackedFloat32Array()
var lap_time_fresh := 0.0
var pit_cost := 0.0
var wear_per_lap := 0.0
var _wear_at_decision := -1.0

# Dernière décision (essais).
var last_plan := ""


func _init(p_driver: AIDriver) -> void:
	driver = p_driver
	var car := driver.car
	var line := driver.line

	wear_per_lap = line.length / maxf(car.tire_wear_distance, 1.0) * car.tire_wear_mul_asphalt * EXPECTED_SLIP_FACTOR

	# Temps au tour selon l'usure.
	var steps := int(round(1.0 / WEAR_STEP))
	var lap_times := PackedFloat32Array()
	lap_times.resize(steps + 1)

	for s in range(steps + 1):
		var wear := s * WEAR_STEP
		var grip := driver.tire_effect(wear, car.worn_tire_grip)

		if s > 0 and grip >= 0.999:
			lap_times[s] = lap_times[s - 1]
			continue

		var profile := driver.build_profile(line, grip, driver.tire_effect(wear, car.worn_tire_brake))
		# Motricité réduite : relances plus lentes (approximation).
		var traction := driver.tire_effect(wear, car.worn_tire_traction)
		lap_times[s] = _lap_time(profile) * (1.0 + 0.15 * (1.0 - traction))

	lap_time_fresh = lap_times[0]
	_lap_loss.resize(steps + 1)

	# Perte sur un tour commencé à cette usure (moyenne sur le tour).
	for s in range(steps + 1):
		var total := 0.0

		for sample in range(4):
			var wear := minf(s * WEAR_STEP + wear_per_lap * (sample + 0.5) / 4.0, 1.0)
			total += _interpolate(lap_times, wear) - lap_time_fresh

		_lap_loss[s] = total / 4.0

	# Coût du passage au stand par rapport à la trajectoire.
	var fresh := driver.build_profile(line, 1.0, 1.0)
	# Jusqu'à l'arrêt (freinage compris), puis relance pneus neufs.
	var stop_profile := driver.build_profile(driver.pit_line, 1.0, 1.0, driver.pit_stop_index)
	var go_profile := driver.build_profile(driver.pit_line, 1.0, 1.0)
	var pit_time := (
		AIDriver.profile_time(stop_profile, 0, driver.pit_stop_index - 1, false)
		+ AIDriver.profile_time(go_profile, driver.pit_stop_index, driver.pit_line.points.size() - 1, false)
	)
	var line_time := AIDriver.profile_time(fresh, driver.pit_entry_index, driver.pit_exit_index, true)
	pit_cost = (
		pit_time - line_time + STOP_OVERHEAD
		+ driver.estimated_qte_time(PitStopManager.QTE_LENGTH)
	)


static func _lap_time(profile: PackedFloat32Array) -> float:
	var total := 0.0

	for speed in profile:
		total += RacingLine.SPACING / maxf(speed, 80.0)

	return total


static func _interpolate(values: PackedFloat32Array, wear: float) -> float:
	var position := clampf(wear / WEAR_STEP, 0.0, values.size() - 1.0)
	var low := int(floor(position))
	var high := mini(low + 1, values.size() - 1)
	return lerpf(values[low], values[high], position - low)


func _loss(wear: float) -> float:
	return _interpolate(_lap_loss, wear)


## Faut-il s'arrêter à ce passage ? `wear` : usure actuelle,
## `laps_remaining` : tours restant à courir (celui-ci compris).
func decide(wear: float, laps_remaining: int) -> bool:
	# Usure réellement mesurée sur le dernier tour.
	if _wear_at_decision >= 0.0 and wear > _wear_at_decision:
		wear_per_lap = lerpf(wear_per_lap, wear - _wear_at_decision, 0.7)

	_wear_at_decision = wear

	var laps := mini(laps_remaining, MAX_HORIZON)

	if laps <= 0:
		last_plan = "dernier tour"
		return false

	# cost[n][w] : temps perdu minimal sur n tours, pneus à l'usure w.
	var steps := _lap_loss.size()
	var cost := PackedFloat32Array()
	cost.resize(steps)
	var stay_cost := 0.0
	var pit_now_cost := 0.0

	for n in range(1, laps + 1):
		var next := PackedFloat32Array()
		next.resize(steps)

		for s in range(steps):
			var w := s * WEAR_STEP
			var stay := _loss(w) + _cost_at(cost, w + wear_per_lap)
			var pit := pit_cost + _loss(0.0) + _cost_at(cost, wear_per_lap)
			next[s] = minf(stay, pit)

		if n == laps:
			stay_cost = _loss(wear) + _cost_at(cost, wear + wear_per_lap)
			pit_now_cost = pit_cost + _loss(0.0) + _cost_at(cost, wear_per_lap)

		cost = next

	last_plan = "usure %d %% (+%d %%/tour), %d tours : rester %.1f s, stand %.1f s" % [
		int(wear * 100.0), int(wear_per_lap * 100.0), laps, stay_cost, pit_now_cost
	]
	return pit_now_cost < stay_cost


func _cost_at(cost: PackedFloat32Array, wear: float) -> float:
	return _interpolate(cost, minf(wear, 1.0))


func on_pit_finished() -> void:
	_wear_at_decision = 0.0
