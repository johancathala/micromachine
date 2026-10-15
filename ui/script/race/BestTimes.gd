
extends Control
class_name BestTimes

const MAX_VISIBLE_RECORDS := 30

@onready var track_tabs: HBoxContainer = $MarginContainer/VBoxContainer/TrackTabs
@onready var car_tabs: HBoxContainer = $MarginContainer/VBoxContainer/CarTabs
@onready var records_list: VBoxContainer = $MarginContainer/VBoxContainer/RecordsPanel/ScrollContainer/RecordsList
@onready var back_button: Button = $MarginContainer/VBoxContainer/Buttons/BackButton

var selected_track_id: int = -1
var selected_car_id: String = ""


func _ready() -> void:
	AudioManager.bind_sound_btt()

	back_button.pressed.connect(_on_back_pressed)

	_build_track_tabs()
	_build_car_tabs()
	_refresh_records()


func _build_track_tabs() -> void:
	for child in track_tabs.get_children():
		child.queue_free()

	var tracks: Array = TrackCatalog.get_tracks()

	if tracks.is_empty():
		return

	selected_track_id = int(tracks[0].get("id", 0))

	for track in tracks:
		var track_id := int(track.get("id", -1))
		var button := Button.new()

		button.text = String(track.get("name", "Circuit"))
		button.toggle_mode = true
		button.button_pressed = track_id == selected_track_id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		button.pressed.connect(
			_on_track_selected.bind(track_id, button)
		)

		track_tabs.add_child(button)


func _build_car_tabs() -> void:
	for child in car_tabs.get_children():
		child.queue_free()

	# Identifiant vide = toutes les voitures.
	var all_button := Button.new()
	all_button.text = "Toutes"
	all_button.toggle_mode = true
	all_button.button_pressed = true
	all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_button.pressed.connect(
		_on_car_selected.bind("", all_button)
	)
	car_tabs.add_child(all_button)

	for car: CarDefinition in CarCatalog.get_cars():
		var button := Button.new()

		button.text = car.display_name
		button.toggle_mode = true
		button.button_pressed = false
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		button.pressed.connect(
			_on_car_selected.bind(car.id, button)
		)

		car_tabs.add_child(button)


func _on_track_selected(track_id: int, source: Button) -> void:
	selected_track_id = track_id
	_set_selected_button(track_tabs, source)
	_refresh_records()


func _on_car_selected(car_id: String, source: Button) -> void:
	selected_car_id = car_id
	_set_selected_button(car_tabs, source)
	_refresh_records()


func _set_selected_button(container: HBoxContainer, selected: Button) -> void:
	for child in container.get_children():
		if child is Button:
			child.button_pressed = child == selected


func _refresh_records() -> void:
	for child in records_list.get_children():
		child.queue_free()

	var filtered: Array[Dictionary] = []

	for record in BestTimesManager.get_records():
		if int(record.get("track_id", -1)) != selected_track_id:
			continue

		if (
			not selected_car_id.is_empty()
			and String(record.get("car_id", "")) != selected_car_id
		):
			continue

		filtered.append(record)

	filtered.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("lap_time", 0.0)) < float(b.get("lap_time", 0.0))
	)

	if filtered.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Aucun record pour cette sélection."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		records_list.add_child(empty_label)
		return

	var count := mini(filtered.size(), MAX_VISIBLE_RECORDS)

	for i in range(count):
		_add_record_row(filtered[i], i + 1)


func _add_record_row(record: Dictionary, rank: int) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var rank_label := _make_cell(str(rank), 55)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var nickname_label := _make_cell(
		String(record.get("nickname", "?")),
		180
	)
	var car_label := _make_cell(
		String(record.get("car_name", "?")),
		150
	)
	var time_label := _make_cell(
		_format_time(float(record.get("lap_time", 0.0))),
		120
	)
	var date_label := _make_cell(
		_format_date(String(record.get("date", ""))),
		130
	)

	row.add_child(rank_label)
	row.add_child(nickname_label)
	row.add_child(car_label)
	row.add_child(time_label)
	row.add_child(date_label)

	records_list.add_child(row)


func _make_cell(value: String, minimum_width: float) -> Label:
	var label := Label.new()
	label.text = value
	label.custom_minimum_size.x = minimum_width
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _format_date(value: String) -> String:
	if value.length() >= 10:
		return value.substr(0, 10)
	return value if not value.is_empty() else "-"


func _format_time(time_seconds: float) -> String:
	if time_seconds <= 0.0:
		return "--:--.---"

	var minutes := int(time_seconds / 60.0)
	var seconds := int(time_seconds) % 60
	var milliseconds := int(
		(time_seconds - floor(time_seconds)) * 1000.0
	)

	if minutes == 0:
		return "%02d.%03d" % [seconds, milliseconds]

	return "%02d:%02d.%03d" % [
		minutes,
		seconds,
		milliseconds
	]


func _on_back_pressed() -> void:
	NavigationManager.go("MainMenu")
