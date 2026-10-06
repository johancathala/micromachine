extends VBoxContainer
class_name RaceResultRow


const PERSONAL_BEST_COLOR := Color("#FFD84D")
const GLOBAL_BEST_COLOR := Color("#55FF88")
const NORMAL_COLOR := Color.WHITE
const DNF_COLOR := Color("#FF6666")

const OR_COLOR := Color("#FFD84D")
const ARGENT_COLOR := Color("#C0C0C0")
const BRONZE_COLOR := Color("#CD7F32")


@onready var position_label: Label = $Header/Position
@onready var name_label: Label = $Header/Name
@onready var car_label: Label = $Header/CarName
@onready var total_time_label: Label = $Header/TotalTime

@onready var lap_list: VBoxContainer = $LapList


func setup(
	result: Dictionary,
	global_best_lap: float,
	global_best_sections: Array[float],
	section_count: int
) -> void:

	position_label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	position_label.text = _format_position(
		int(result.get("position", 0))
	)
	
	position_label.modulate = _color_position(
		int(result.get("position", 0))
	)

	name_label.text = String(
		result.get("nickname", "?")
	)
	
	name_label.modulate = _color_position(
		int(result.get("position", 0))
	)
	
	car_label.text = String(
		result.get("car_name", "?")
	)

	var finished := bool(
		result.get("finished", false)
	)

	if finished:
		total_time_label.text = _format_time(
			float(result.get("finish_time", 0.0))
		)

	else:
		total_time_label.text = "DNF"
		total_time_label.modulate = DNF_COLOR

	_build_laps(
		result,
		global_best_lap,
		global_best_sections,
		section_count
	)


func _build_laps(
	result: Dictionary,
	global_best_lap: float,
	global_best_sections: Array[float],
	section_count: int
) -> void:

	for child in lap_list.get_children():
		child.queue_free()

	var records: Array = result.get(
		"lap_records",
		[]
	)

	var personal_best_lap := float(
		result.get("best_lap_time", 0.0)
	)

	var personal_best_sections: Array = (
		result.get(
			"best_section_times",
			[]
		)
	)

	# --------------------------------------------------------
	# En-tête des secteurs
	# --------------------------------------------------------

	var header := HBoxContainer.new()

	var lap_header := Label.new()
	lap_header.text = "Tour"
	lap_header.custom_minimum_size.x = 90
	lap_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	header.add_child(lap_header)

	var time_header := Label.new()
	time_header.text = "Temps"
	time_header.custom_minimum_size.x = 100
	time_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	header.add_child(time_header)

	for section_index in range(section_count):

		var section_header := Label.new()

		section_header.text = (
			"S%d"
			% (section_index + 1)
		)

		section_header.custom_minimum_size.x = 100
		section_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		header.add_child(section_header)

	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lap_list.add_child(header)


	# --------------------------------------------------------
	# Tours
	# --------------------------------------------------------

	for record in records:

		var lap_row := HBoxContainer.new()

		var lap_number := int(
			record.get("lap", 0)
		)

		var lap_label := Label.new()

		lap_label.text = (
			"Tour %d"
			% lap_number
		)

		lap_label.custom_minimum_size.x = 90
		lap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		lap_row.add_child(lap_label)


		# ----------------------------------------------------
		# Temps du tour
		# ----------------------------------------------------

		var lap_time := float(
			record.get("lap_time", 0.0)
		)

		var lap_time_label := Label.new()

		lap_time_label.text = _format_time(
			lap_time
		)

		lap_time_label.custom_minimum_size.x = 100

		if (
			global_best_lap > 0.0
			and is_equal_approx(
				lap_time,
				global_best_lap
			)
		):

			lap_time_label.modulate = (
				GLOBAL_BEST_COLOR
			)

		elif (
			personal_best_lap > 0.0
			and is_equal_approx(
				lap_time,
				personal_best_lap
			)
		):

			lap_time_label.modulate = (
				PERSONAL_BEST_COLOR
			)

		lap_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lap_row.add_child(
			lap_time_label
		)


		# ----------------------------------------------------
		# Temps intermédiaires
		# ----------------------------------------------------

		var section_times: Array = (
			record.get(
				"section_times",
				[]
			)
		)

		for section_index in range(section_count):

			var section_label := Label.new()

			if section_index < section_times.size():

				var section_time := float(
					section_times[section_index]
				)

				section_label.text = (
					_format_time(section_time)
				)

				# Meilleur temps absolu de la course
				if (
					section_index
					< global_best_sections.size()
					and global_best_sections[
						section_index
					] > 0.0
					and is_equal_approx(
						section_time,
						global_best_sections[
							section_index
						]
					)
				):

					section_label.modulate = (
						GLOBAL_BEST_COLOR
					)

				# Meilleur temps personnel
				elif (
					section_index
					< personal_best_sections.size()
					and personal_best_sections[
						section_index
					] > 0.0
					and is_equal_approx(
						section_time,
						personal_best_sections[
							section_index
						]
					)
				):

					section_label.modulate = (
						PERSONAL_BEST_COLOR
					)

			else:

				section_label.text = "--"

			section_label.custom_minimum_size.x = 100

			section_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lap_row.add_child(
				section_label
			)
		
		lap_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lap_list.add_child(lap_row)
	
	var spacer := HSeparator.new()
	spacer.custom_minimum_size.y = 30
	lap_list.add_child(spacer)


func _format_position(position: int) -> String:

	match position:

		1:
			return "1er"

		2:
			return "2ème"

		3:
			return "3ème"

		_:
			return "%dème" % position

func _color_position(position: int) -> Color:

	match position:

		1:
			return OR_COLOR

		2:
			return ARGENT_COLOR

		3:
			return BRONZE_COLOR

		_:
			return NORMAL_COLOR


func _format_time(time_seconds: float) -> String:

	if time_seconds <= 0.0:
		return "--:--.---"

	var minutes := int(time_seconds/60)

	var seconds := int(
		time_seconds
	) % 60

	var milliseconds := int(
		(time_seconds - floor(time_seconds))
		* 1000.0
	)
	
	if minutes == 0:
		return "%02d.%03d" % [
		seconds,
		milliseconds
	]

	return "%02d:%02d.%03d" % [
		minutes,
		seconds,
		milliseconds
	]
