extends Control
class_name RaceHUD

const PARTICIPANT_ROW_SCENE := preload(
    "res://level/scene/RaceParticipantHUD.tscn"
)

@onready var lap_label: Label = $MarginContainer/HBoxContainer/LeftPanel/Top/Lap
@onready var first_participant_label: Label = $MarginContainer/HBoxContainer/LeftPanel/Top/FirstParticipant
@onready var best_lap_label: Label = $MarginContainer/HBoxContainer/LeftPanel/Top/BestLap
@onready var race_time_label: Label = $MarginContainer/HBoxContainer/LeftPanel/Top/RaceTime

@onready var light_start: Node2D = $MarginContainer/HBoxContainer/CenterPanel/Center/FeuDepart

@onready var participant_list: VBoxContainer = $MarginContainer/HBoxContainer/RightPanel

var participant_rows: Dictionary = {}

var race_controller: RaceController = null
var race_world: RaceWorld = null

var displayed_participant_id: int = -1
var displayed_car: Car = null

var race_started: bool = false


func initialize(
	controller: RaceController,
	world: RaceWorld
) -> void:

	race_controller = controller
	race_world = world

	_select_displayed_participant()
	_connect_controller_signals()

	_prepare_countdown_display()
	_update_static_values()
	
	_build_participant_rows()


func _process(_delta: float) -> void:
	if race_controller == null:
		return

	_update_race_time()
	_update_displayed_car()
	
	for state in race_controller.get_participant_states():

		var row = participant_rows.get(
			state.participant_id
		)

		if row == null:
			continue
		
		row.refresh()


func _connect_controller_signals() -> void:
	if not race_controller.countdown_started.is_connected(
		_on_countdown_started
	):
		race_controller.countdown_started.connect(
			_on_countdown_started
		)

	if not race_controller.race_started.is_connected(
		_on_race_started
	):
		race_controller.race_started.connect(
			_on_race_started
		)

	if not race_controller.participant_lap_completed.is_connected(
		_on_participant_lap_completed
	):
		race_controller.participant_lap_completed.connect(
			_on_participant_lap_completed
		)

	if not race_controller.participant_finished.is_connected(
		_on_participant_finished
	):
		race_controller.participant_finished.connect(
			_on_participant_finished
		)

	if not race_controller.positions_changed.is_connected(
		_on_positions_changed
	):
		race_controller.positions_changed.connect(
			_on_positions_changed
	)

	if not race_controller.race_finished.is_connected(
		_on_race_finished
	):
		race_controller.race_finished.connect(
			_on_race_finished
	)


# ------------------------------------------------------------------
# INITIALISATION
# ------------------------------------------------------------------

func _select_displayed_participant() -> void:
	if race_controller == null:
		return

	var states: Array[RaceParticipantState] = (
		race_controller.get_participant_states()
	)

	if states.is_empty():
		return

	# 1. Priorité au clavier.
	for state in states:
		if state.device_type == "keyboard":
			displayed_participant_id = state.participant_id
			return

	# 2. Premier joueur humain.
	for state in states:
		if not state.is_ai:
			displayed_participant_id = state.participant_id
			return

	# 3. Cas de secours : premier participant.
	displayed_participant_id = states[0].participant_id


func _update_displayed_car() -> void:
	if race_world == null:
		return

	var cars_root := race_world.get_cars_root()

	if cars_root == null:
		return

	for child in cars_root.get_children():
		var car := child as Car

		if car == null:
			continue

		if car.participant_id == displayed_participant_id:
			displayed_car = car
			return

func _build_participant_rows() -> void:

	# Nettoyage éventuel
	for child in participant_list.get_children():
		child.queue_free()

	participant_rows.clear()

	for state in race_controller.get_participant_states():

		var row := PARTICIPANT_ROW_SCENE.instantiate()

		participant_list.add_child(row)

		row.setup(state,race_controller)

		participant_rows[state.participant_id] = row

# ------------------------------------------------------------------
# COUNTDOWN
# ------------------------------------------------------------------

func _prepare_countdown_display() -> void:
	race_started = false

	_set_lights_red()
	light_start.visible = true


func _on_countdown_started() -> void:
	race_started = false

	_set_lights_red()

	light_start.visible = true


func _on_race_started() -> void:
	race_started = true

	_set_lights_green()


func _set_lights_red() -> void:
	if light_start == null:
		return

	for child in light_start.get_children():
		var light := child as AnimatedSprite2D

		if light == null:
			continue

		light.visible = true
		light.set_frame(0)


func _set_lights_green() -> void:
	if light_start == null:
		return

	for child in light_start.get_children():
		var light := child as AnimatedSprite2D

		if light == null:
			continue

		light.visible = true
		light.set_frame(1)

	# Les feux restent visibles brièvement après le départ.
	await get_tree().create_timer(2.0).timeout

	if race_started:
		light_start.visible = false


# ------------------------------------------------------------------
# COURSE
# ------------------------------------------------------------------

func _update_race_time() -> void:
	if race_controller == null:
		return

	if not race_started:
		return

	var race_time := race_controller.get_race_time()

	race_time_label.text = (
		"Temps de course : %s"
		% _format_time(race_time)
	)


func _update_first_participant_values(state: RaceParticipantState) -> void:
	if race_controller == null:
		return
	
	var current_lap = state.current_lap

	var lap_count : int = race_controller.get_lap_count()

	lap_label.text = (
		"Tour %d/%d"
		% [
			current_lap,
			lap_count
		]
	)
	
	first_participant_label.text = "Leader de la course : "+state.nickname

func _update_best_lap(state: RaceParticipantState) -> void:
	if race_controller == null:
		return

	var best_lap : float = state.best_lap_time

	best_lap_label.text = (
		"Meilleur temps (à modif) : %s"
		% _format_time(best_lap)
	)

# ------------------------------------------------------------------
# ÉVÉNEMENTS DE COURSE
# ------------------------------------------------------------------


func _on_participant_finished(
	state: RaceParticipantState
) -> void:

	if state.participant_id != displayed_participant_id:
		return


func _on_positions_changed(state: RaceParticipantState) -> void:
	_update_first_participant_values(state)

func _on_participant_lap_completed(state: RaceParticipantState) -> void:
	_update_best_lap(state)


func _on_race_finished() -> void:
	race_started = false


# ------------------------------------------------------------------
# INFORMATIONS STATIQUES
# ------------------------------------------------------------------

func _update_static_values() -> void:
	if race_controller == null:
		return

	var lap_count : int = race_controller.get_lap_count()

	lap_label.text = "Tour 0/%d" % lap_count
	race_time_label.text = "Temps de course : 0.00"


func _format_time(time_seconds: float) -> String:
	if time_seconds < 0.0:
		return "-%s" % _format_time(absf(time_seconds))

	var minutes := int(time_seconds / 60.0)
	var seconds := fmod(time_seconds, 60.0)

	return "%02d:%05.2f" % [
		minutes,
		seconds
	]
