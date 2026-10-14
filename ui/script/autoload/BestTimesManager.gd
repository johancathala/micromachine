
extends Node

const SAVE_PATH := "user://best_times.json"

var records: Array[Dictionary] = []


func _ready() -> void:
	_load_records()


func get_records() -> Array[Dictionary]:
	return records.duplicate(true)


func save_race_results(
	race_results: Array,
	race_config: RaceConfig
) -> void:
	if race_config == null:
		push_warning("BestTimesManager : configuration de course absente.")
		return

	var track_id := int(race_config.track.id)
	var track_name := str(race_config.track.name)

	# Associe chaque participant à son car_id.
	var participants_by_id: Dictionary = {}

	for participant in race_config.participants:
		var participant_id := str(participant.get("participant_id", ""))
		participants_by_id[participant_id] = participant

	var changed := false

	for result in race_results:
		if not result is Dictionary:
			continue

		# Les IA ne doivent pas apparaître dans le classement personnel.
		if bool(result.get("is_ai", false)):
			continue

		var lap_time := float(result.get("best_lap_time", 0.0))
		if lap_time <= 0.0:
			continue

		var nickname := str(result.get("nickname", "")).strip_edges()
		if nickname.is_empty():
			continue

		var participant_id := str(result.get("participant_id", ""))

		var participant: Dictionary = participants_by_id.get(
			participant_id,
			{}
		)

		var car_id := str(result.get("car_id", participant.get("car_id", "")))

		if car_id.is_empty():
			push_warning(
				"BestTimesManager : car_id absent pour " + nickname
			)
			continue

		var car: CarDefinition = CarCatalog.get_car(car_id)
		if car == null:
			continue

		var record_index := _find_record_index(
			nickname,
			track_id,
			car_id
		)

		if record_index >= 0:
			var old_time := float(
				records[record_index].get("lap_time", 0.0)
			)

			# Ne remplace le record que si le temps est meilleur.
			if old_time > 0.0 and lap_time >= old_time:
				continue

			records[record_index] = _make_record(
				nickname,
				track_id,
				track_name,
				car_id,
				car.display_name,
				lap_time
			)
		else:
			records.append(
				_make_record(
					nickname,
					track_id,
					track_name,
					car_id,
					car.display_name,
					lap_time
				)
			)

		changed = true

	if changed:
		_save_records()


func _find_record_index(
	nickname: String,
	track_id: int,
	car_id: String
) -> int:
	for i in range(records.size()):
		var record := records[i]

		if (
			str(record.get("nickname", "")) == nickname
			and int(record.get("track_id", -1)) == track_id
			and str(record.get("car_id", "")) == car_id
		):
			return i

	return -1


func _make_record(
	nickname: String,
	track_id: int,
	track_name: String,
	car_id: String,
	car_name: String,
	lap_time: float
) -> Dictionary:
	return {
		"nickname": nickname,
		"track_id": track_id,
		"track_name": track_name,
		"car_id": car_id,
		"car_name": car_name,
		"lap_time": lap_time,
		"date": Time.get_datetime_string_from_system(false, true)
	}


func _load_records() -> void:
	records.clear()

	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("BestTimesManager : lecture impossible du fichier.")
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())

	if not parsed is Array:
		push_warning("BestTimesManager : format JSON invalide.")
		return

	for item in parsed:
		if item is Dictionary:
			records.append(item)


func _save_records() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("BestTimesManager : impossible d'enregistrer les records.")
		return

	file.store_string(JSON.stringify(records, "\t"))
