extends Node

enum GameMode {
	SINGLE_RACE,
	CHAMPIONSHIP,
	TIME_TRIAL
}

const CHAMPIONSHIP_POINTS := [10, 8, 6, 5, 4, 3, 2, 1]

var pending_race_config: RaceConfig = null
var active_race_config: RaceConfig = null
var last_race_results: Array[Dictionary] = []
# Contre-la-montre : tours valides de la session, avec leur
# enregistrement (GhostManager), à garder en médailles.
var last_ghost_laps: Array[Dictionary] = []

# ================================================================
# CONFIGURATION DE COURSE
# ================================================================

func set_pending_race_config(config: RaceConfig) -> void:
	if config == null:
		push_error("GameManager: RaceConfig null.")
		return

	pending_race_config = config


func get_pending_race_config() -> RaceConfig:
	return pending_race_config


func has_pending_race_config() -> bool:
	return pending_race_config != null


func clear_pending_race_config() -> void:
	pending_race_config = null

func get_tracks() -> Array:
	return TrackCatalog.get_tracks()
	
func get_track(id: int) -> Dictionary:
	return TrackCatalog.get_track(id)

# ================================================================
# LANCEMENT DE LA COURSE
# ================================================================

func start_race() -> bool:
	if pending_race_config == null:
		push_error("GameManager : aucune course en attente.")
		return false

	if not pending_race_config.is_valid():
		push_error("GameManager : la configuration de course est invalide.")
		return false

	if not pending_race_config.is_car_selection_valid():
		push_error("GameManager : sélection des voitures invalide.")
		return false

	active_race_config = pending_race_config.duplicate_config()
	pending_race_config = null

	return true


func record_championship_race_results() -> bool:
	if active_race_config == null or not active_race_config.is_championship():
		push_error("GameManager : aucun championnat actif.")
		return false

	if active_race_config.championship_race_recorded:
		return true

	if last_race_results.is_empty():
		push_error("GameManager : aucun résultat pour cette course du championnat.")
		return false

	var results_by_id: Dictionary = {}

	for result in last_race_results:
		var participant_id := int(result.get("participant_id", -1))

		if participant_id < 0 or results_by_id.has(participant_id):
			push_error("GameManager : identifiant de participant invalide ou dupliqué.")
			return false

		results_by_id[participant_id] = result

	var standings: Array[Dictionary] = active_race_config.championship_standings.duplicate(true)

	if standings.is_empty():
		for result in last_race_results:
			standings.append({
				"participant_id": int(result["participant_id"]),
				"nickname": String(result.get("nickname", "?")),
				"car_name": String(result.get("car_name", "")),
				"is_ai": bool(result.get("is_ai", false)),
				"points": 0,
				"last_race_points": 0,
				"last_race_position": 0,
				"wins": 0,
				"second_places": 0,
				"best_position": 999,
				"race_points": [],
				"race_positions": []
			})

	if results_by_id.size() != standings.size():
		push_error("GameManager : les participants ont changé pendant le championnat.")
		return false

	for standing in standings:
		var participant_id := int(standing.get("participant_id", -1))

		if not results_by_id.has(participant_id):
			push_error("GameManager : résultat manquant pour un participant du championnat.")
			return false

		var result: Dictionary = results_by_id[participant_id]
		var position := int(result.get("position", 0))
		var points := 0

		if position > 0 and position <= CHAMPIONSHIP_POINTS.size():
			points = CHAMPIONSHIP_POINTS[position - 1]

		standing["nickname"] = String(result.get("nickname", standing.get("nickname", "?")))
		standing["car_name"] = String(result.get("car_name", standing.get("car_name", "")))
		standing["last_race_points"] = points
		standing["last_race_position"] = position
		standing["points"] = int(standing.get("points", 0)) + points
		standing["wins"] = int(standing.get("wins", 0)) + (1 if position == 1 else 0)
		standing["second_places"] = int(standing.get("second_places", 0)) + (1 if position == 2 else 0)
		standing["best_position"] = mini(int(standing.get("best_position", 999)), position if position > 0 else 999)

		var race_points: Array = standing.get("race_points", [])
		race_points.append(points)
		standing["race_points"] = race_points

		var race_positions: Array = standing.get("race_positions", [])
		race_positions.append(position)
		standing["race_positions"] = race_positions

	active_race_config.championship_standings = standings
	active_race_config.championship_race_recorded = true
	return true


func get_championship_standings() -> Array[Dictionary]:
	if active_race_config == null:
		return []

	var standings: Array[Dictionary] = active_race_config.championship_standings.duplicate(true)
	standings.sort_custom(_compare_championship_standings)
	return standings


func _compare_championship_standings(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("points", 0)) != int(b.get("points", 0)):
		return int(a.get("points", 0)) > int(b.get("points", 0))

	if int(a.get("wins", 0)) != int(b.get("wins", 0)):
		return int(a.get("wins", 0)) > int(b.get("wins", 0))

	if int(a.get("second_places", 0)) != int(b.get("second_places", 0)):
		return int(a.get("second_places", 0)) > int(b.get("second_places", 0))

	if int(a.get("best_position", 999)) != int(b.get("best_position", 999)):
		return int(a.get("best_position", 999)) < int(b.get("best_position", 999))

	return int(a.get("participant_id", -1)) < int(b.get("participant_id", -1))


func start_next_championship_race() -> bool:
	if active_race_config == null or not active_race_config.is_championship():
		push_error("GameManager : aucun championnat actif.")
		return false

	if not active_race_config.championship_race_recorded:
		push_error("GameManager : la course actuelle n'est pas encore comptabilisée.")
		return false

	var next_index: int = active_race_config.championship_race_index + 1

	if next_index >= active_race_config.championship_tracks.size():
		push_warning("GameManager : le championnat est terminé.")
		return false

	var next_config := active_race_config.duplicate_config()
	next_config.championship_race_index = next_index
	next_config.track = next_config.championship_tracks[next_index].duplicate(true)
	next_config.lap_count = int(
		next_config.championship_tracks[next_index].get("lap_count", next_config.lap_count)
	)
	next_config.championship_race_recorded = false
	set_pending_race_config(next_config)

	if not start_race():
		clear_pending_race_config()
		return false

	return true


func start_single_race(config: RaceConfig) -> bool:

	if config == null:
		return false

	if not config.is_valid():
		return false

	config.mode = GameMode.SINGLE_RACE

	active_race_config = config
	pending_race_config = null

	return true

func restart_active_race() -> bool:

	prepare_race_setup()

	return start_race()

func prepare_race_setup() -> void:

	if active_race_config == null:
		return

	pending_race_config = (
		active_race_config.duplicate_config()
	)
# ================================================================
# COURSE ACTIVE
# ================================================================
func has_active_race() -> bool:
	return active_race_config != null


func set_active_race_config(config: RaceConfig) -> void:
	if config == null:
		push_error("GameManager : configuration active invalide.")
		return

	active_race_config = config


func get_active_race_config() -> RaceConfig:
	return active_race_config


func clear_active_race_config() -> void:
	active_race_config = null


# ================================================================
# FIN DE COURSE
# ================================================================
func store_race_results(
	results: Array[Dictionary]
) -> void:
	last_race_results = results.duplicate(true)

func clear_active_race() -> void:
	pending_race_config = null
	active_race_config = null
	clear_result_race()
	
func clear_result_race() -> void:
	last_race_results.clear()
	last_ghost_laps.clear()

func get_last_race_results() -> Array[Dictionary]:
	return last_race_results
