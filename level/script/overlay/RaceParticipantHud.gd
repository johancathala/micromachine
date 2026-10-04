extends HBoxContainer
class_name RaceParticipantHUD

@onready var name_label: Label = $Name
@onready var position_label: Label = $Position
@onready var lap_label: Label = $Lap
@onready var lap_time_label: Label = $LapTime
@onready var delta_label: Label = $Delta
@onready var best_lap_label: Label = $BestLap
@onready var speed_label: Label = $Speed

var participant: RaceParticipantState = null

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

func setup(
	p_participant: RaceParticipantState
) -> void:

	participant = p_participant

	name_label.text = participant.nickname
	speed_label.text = ""

	refresh()


func refresh() -> void:

	if participant == null:
		return
	# ----------------------------
	# Vitesse
	# ----------------------------
	#speed_label.text = "%d km/h" % (int(_speed_to_kmh(participant.car.speed)))

	# ----------------------------
	# Position
	# ----------------------------
	position_label.text = " | "+PLACE[participant.race_position]
	
	# ----------------------------
	# Tour en cours
	# ----------------------------
	lap_label.text = " | TOUR "+str(participant.current_lap)
	# ----------------------------
	# Temps tour en cours
	# ----------------------------
	lap_time_label.text = " | En cours : "+_format_time(participant.lap_start_time)
	# ----------------------------
	# Delta
	# ----------------------------	
	delta_label.text = " | "+get_delta()
	# ----------------------------
	# Meilleur tour
	# ----------------------------
	best_lap_label.text = " | Meilleur : "+_format_time(participant.best_lap_time)

func get_delta(
) -> String:

	var txt = "Écart : --"
	if participant.best_lap_time <= 0.0:
		return txt
		
	
	var num_section = participant.next_section-1
	if num_section == 0:
		return txt
		
	var previous_time := participant.lap_start_time
	var current_section = participant.section_times[num_section] - previous_time

	var delta : float = current_section - participant.best_section_times[num_section-1]

	txt = (
		"Écart : %s%s"
		% [
			"+" if delta >= 0.0 else "",
			delta
		]
	)
	return txt

func _speed_to_kmh(speed: float) -> float:
	return speed * 0.1


func _format_time(time_seconds: float) -> String:

	if time_seconds <= 0.0:
		return "--:--.---"

	var minutes := int(time_seconds) / 60
	var seconds := int(time_seconds) % 60

	var milliseconds := int(
		(time_seconds - floor(time_seconds)) * 1000.0
	)

	return "%02d:%02d.%03d" % [
		minutes,
		seconds,
		milliseconds
	]
