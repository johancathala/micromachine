extends HBoxContainer
class_name RaceParticipantHUD


@onready var name_label: Label = $Name
@onready var position_label: Label = $Position
@onready var lap_label: Label = $Lap
@onready var lap_time_label: Label = $LapTime
@onready var delta_label: Label = $Delta
@onready var best_lap_label: Label = $BestLap


var participant: RaceParticipantState = null
var race_controller: RaceController = null


const PLACE := {
	0: "--",
	1: "1er",
	2: "2ème",
	3: "3ème",
	4: "4ème",
	5: "5ème",
	6: "6ème",
	7: "7ème",
	8: "8ème",
}


const POSITION_COLORS := {
	1: Color("#FFD700"),
	2: Color("#C0C0C0"),
	3: Color("#CD7F32"),
}


func setup(
	p_participant: RaceParticipantState,
	p_race_controller: RaceController
) -> void:

	participant = p_participant
	race_controller = p_race_controller

	name_label.text = " | " + participant.nickname

	refresh()


func refresh() -> void:

	if participant == null:
		return

	if race_controller == null:
		return

	# ============================================================
	# POSITION
	# ============================================================
	position_label.text = PLACE.get(
		participant.race_position,
		"--"
	)

	_update_position_color()


	# ============================================================
	# TOUR
	# ============================================================
	lap_label.text = (
		" | TOUR %d"
		% participant.current_lap
	)


	# ============================================================
	# TEMPS DU TOUR EN COURS
	# ============================================================
	if participant.has_started_lap:

		var current_lap_time := (
			race_controller.get_race_time()
			- participant.lap_start_time
		)

		lap_time_label.text = (
			" | En cours : %s"
			% _format_time(current_lap_time)
		)

	else:

		lap_time_label.text = " | En cours : --:--.---"


	# ============================================================
	# DELTA DERNIER SECTEUR
	# ============================================================
	delta_label.text = (
		" | "
		+ get_delta()
	)
	
	_update_delta_color()

	# ============================================================
	# MEILLEUR TOUR
	# ============================================================
	best_lap_label.text = (
		" | Meilleur : %s"
		% _format_time(participant.best_lap_time)
	)


func get_delta() -> String:

	if participant.last_section_index < 0:
		return "Écart : --"

	if (
		participant.last_section_index
		>= participant.best_section_times.size()
	):
		return "Écart : --"

	var best_section_time := (
		participant.best_section_times[
			participant.last_section_index
		]
	)

	if best_section_time <= 0.0:
		return "Écart : --"

	return (
		"Écart : %+.3f"
		% participant.last_section_delta
	)

func _update_delta_color() -> void:

	var delta: float = participant.last_section_delta

	if participant.last_section_index < 0:
		delta_label.modulate = Color.WHITE
	elif delta < 0.0:
		delta_label.modulate = Color("#55DD55")
	elif delta > 0.0:
		delta_label.modulate = Color("#FF6666")
	else:
		delta_label.modulate = Color.WHITE

func _update_position_color() -> void:

	var race_position := participant.race_position

	if POSITION_COLORS.has(race_position):

		position_label.modulate = (
			POSITION_COLORS[race_position]
		)

	else:

		position_label.modulate = Color.WHITE


func _speed_to_kmh(speed: float) -> float:

	return speed * 0.1


func _format_time(time_seconds: float) -> String:

	if time_seconds <= 0.0:
		return "--:--.---"

	var minutes := int(time_seconds / 60)
	var seconds := int(time_seconds) % 60

	var milliseconds := int(
		(time_seconds - floor(time_seconds)) * 1000.0
	)

	return "%02d:%02d.%03d" % [
		minutes,
		seconds,
		milliseconds
	]
