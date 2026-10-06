extends Node

enum GameMode {
	SINGLE_RACE,
	CHAMPIONSHIP,
	TIME_TRIAL
}


var pending_race_config: RaceConfig = null
var active_race_config: RaceConfig = null
var last_race_results: Array[Dictionary] = []

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

	if not pending_race_config.is_car_selection_valid():
		push_error("GameManager : sélection des voitures invalide.")
		return false

	active_race_config = pending_race_config.duplicate_config()
	pending_race_config = null

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

	if active_race_config == null:
		return false

	pending_race_config = (
		active_race_config.duplicate_config()
	)

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
	last_race_results.clear()

func get_last_race_results() -> Array[Dictionary]:
	return last_race_results
