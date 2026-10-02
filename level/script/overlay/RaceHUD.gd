extends Control
class_name RaceHUD

@onready var lap_label: Label = $MarginContainer/HBoxContainer/LeftPanel/Lap
@onready var race_time_label: Label = $MarginContainer/HBoxContainer/LeftPanel/RaceTime
@onready var lap_time_label: Label = $MarginContainer/HBoxContainer/LeftPanel/LapTime
@onready var last_lap_label: Label = $MarginContainer/HBoxContainer/LeftPanel/LastLapTime
@onready var delta_label: Label = $MarginContainer/HBoxContainer/LeftPanel/Delta

@onready var light_start: Node2D = $MarginContainer/HBoxContainer/CenterPanel/FeuDepart

@onready var speed_label: Label = $MarginContainer/HBoxContainer/RightPanel/Speed
@onready var position_label: Label = $MarginContainer/HBoxContainer/RightPanel/Position
@onready var best_lap_label: Label = $MarginContainer/HBoxContainer/RightPanel/BestLap

@onready var race_status_label: Label = $RaceStatus

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


func _process(_delta: float) -> void:
	if race_controller == null:
		return

	_update_race_time()
	_update_displayed_car()
	_update_speed()
	_update_participant_values()


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


# ------------------------------------------------------------------
# COUNTDOWN
# ------------------------------------------------------------------

func _prepare_countdown_display() -> void:
	race_started = false

	race_status_label.text = ""

	_set_lights_red()
	light_start.visible = true


func _on_countdown_started() -> void:
	race_started = false

	_set_lights_red()

	light_start.visible = true
	race_status_label.text = "PRÊT"


func _on_race_started() -> void:
	race_started = true

	_set_lights_green()

	race_status_label.text = "PARTEZ !"


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


func _update_participant_values() -> void:
	if race_controller == null:
		return

	var state : RaceParticipantState = race_controller.get_participant_state(
		displayed_participant_id
	)

	if state == null:
		return

	var lap_count : int = race_controller.get_lap_count()

	lap_label.text = (
		"Tour %d/%d"
		% [
			state.current_lap,
			lap_count
		]
	)

	if state.has_started_lap and not state.finished:
		var current_lap_time := (
			race_controller.get_race_time()
			- state.lap_start_time
		)

		lap_time_label.text = (
			"Tour en cours : %s"
			% _format_time(current_lap_time)
		)

	if state.last_lap_time > 0.0:
		last_lap_label.text = (
			"Dernier tour : %s"
			% _format_time(state.last_lap_time)
		)

	if state.best_lap_time > 0.0:
		best_lap_label.text = (
			"Meilleur tour : %s"
			% _format_time(state.best_lap_time)
		)

	if state.race_position > 0:
		var total : int = race_controller.get_participant_count()

		position_label.text = (
			"Position : %d/%d"
			% [
				state.race_position,
				total
			]
		)


func _update_speed() -> void:
	if displayed_car == null:
		speed_label.text = "0 km/h"
		return

	var speed := displayed_car.velocity.length()

	# Conversion adaptée à l'échelle actuelle du véhicule.
	# À ajuster une seule fois lorsque l'échelle physique définitive
	# du jeu sera figée.
	var kmh := roundi(speed * 140.0 / 2000.0)

	speed_label.text = "%d km/h" % kmh


# ------------------------------------------------------------------
# ÉVÉNEMENTS DE COURSE
# ------------------------------------------------------------------

func _on_participant_lap_completed(
	state: RaceParticipantState
) -> void:

	if state == null:
		return
		
	if state.participant_id != displayed_participant_id:
		return

	last_lap_label.text = (
		"Dernier tour : %s"
		% _format_time(state.last_lap_time)
	)

	if state.best_lap_time > 0.0:
		best_lap_label.text = (
			"Meilleur tour : %s"
			% _format_time(state.best_lap_time)
		)

	_update_delta(state, state.last_lap_time)


func _update_delta(
	state: RaceParticipantState,
	lap_time: float
) -> void:

	if state.best_lap_time <= 0.0:
		delta_label.text = "Écart : --"
		return

	var delta := lap_time - state.best_lap_time

	delta_label.text = (
		"Écart : %s%s"
		% [
			"+" if delta >= 0.0 else "",
			_format_time(delta)
		]
	)


func _on_participant_finished(
	participant_id: int,
	finish_position: int
) -> void:

	if participant_id != displayed_participant_id:
		return

	race_status_label.text = (
		"ARRIVÉ !  %dème"
		% finish_position
	)


func _on_positions_changed() -> void:
	_update_participant_values()


func _on_race_finished() -> void:
	race_started = false

	race_status_label.text = "COURSE TERMINÉE"

	_update_participant_values()


# ------------------------------------------------------------------
# INFORMATIONS STATIQUES
# ------------------------------------------------------------------

func _update_static_values() -> void:
	if race_controller == null:
		return

	var lap_count : int = race_controller.get_lap_count()

	lap_label.text = "Tour 0/%d" % lap_count
	race_time_label.text = "Temps de course : 0.00"
	lap_time_label.text = "Tour en cours : 0.00"
	last_lap_label.text = "Dernier tour : --"
	delta_label.text = "Écart : --"
	speed_label.text = "0 km/h"
	position_label.text = "Position : --/--"
	best_lap_label.text = "Meilleur tour : --"


func _format_time(time_seconds: float) -> String:
	if time_seconds < 0.0:
		return "-%s" % _format_time(absf(time_seconds))

	var minutes := int(time_seconds / 60.0)
	var seconds := fmod(time_seconds, 60.0)

	return "%02d:%05.2f" % [
		minutes,
		seconds
	]
