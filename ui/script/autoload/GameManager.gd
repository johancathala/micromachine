extends Node

enum GameMode {
	SINGLE_RACE,
	CHAMPIONSHIP,
	TIME_TRIAL
}


var pending_race_config: RaceConfig = null
var active_race_config: RaceConfig = null


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


# ================================================================
# LANCEMENT DE LA COURSE
# ================================================================

func start_race() -> bool:

	if pending_race_config == null:
		push_error(
			"GameManager: aucune configuration de course en attente."
		)
		return false


	if not pending_race_config.is_valid():
		push_error(
			"GameManager: configuration de course invalide."
		)
		return false


	active_race_config = pending_race_config
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


# ================================================================
# COURSE ACTIVE
# ================================================================

func has_active_race() -> bool:
	return active_race_config != null


func get_active_race_config() -> RaceConfig:
	return active_race_config


func clear_active_race() -> void:
	active_race_config = null
