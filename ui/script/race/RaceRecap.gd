extends Control
class_name RaceRecap


const RESULT_ROW_SCENE := preload(
	"res://ui/scene/RaceResultRow.tscn"
)


@onready var title_label: Label = (
	$MarginContainer/VBoxContainer/Title
)

@onready var track_name_label: Label = (
	$MarginContainer/VBoxContainer/TrackName
)

@onready var results_list: VBoxContainer = (
	$MarginContainer/VBoxContainer/ResultsPanel/MarginContainer/ResultsScroll/ResultsList
)

@onready var best_lap_name_label: Label = (
	$MarginContainer/VBoxContainer/BestLapPanel/BestLapNameLabel
)

@onready var best_lap_label: Label = (
	$MarginContainer/VBoxContainer/BestLapPanel/BestLapLabel
)

@onready var restart_button: Button = (
	$MarginContainer/VBoxContainer/Buttons/RestartButton
)

@onready var track_selection_button: Button = (
	$MarginContainer/VBoxContainer/Buttons/TrackSelectionButton
)

@onready var main_menu_button: Button = (
	$MarginContainer/VBoxContainer/Buttons/MainMenuButton
)


var results: Array[Dictionary] = []

var global_best_lap: float = 0.0
var global_best_lap_participant: String = ""

var global_best_sections: Array[float] = []


func _ready() -> void:

	restart_button.pressed.connect(
		_on_restart_pressed
	)

	track_selection_button.pressed.connect(
		_on_track_selection_pressed
	)

	main_menu_button.pressed.connect(
		_on_main_menu_pressed
	)

	results = GameManager.get_last_race_results()
	var race_config: RaceConfig = GameManager.get_active_race_config()
	track_name_label.text = "Circuit : " + race_config.track.name

	_build_results()


func _build_results() -> void:

	if results.is_empty():

		push_warning(
			"RaceRecap : aucun résultat disponible."
		)

		return

	_build_title()
	
	_find_global_bests()

	_build_result_rows()

	_update_global_best_label()


func _build_title() -> void:
	
	var nickname : String = results.get(0).get(
				"nickname",
				"?"
			)
	title_label.text = nickname + " GAGNE LA COURSE !"

func _find_global_bests() -> void:

	global_best_lap = 0.0
	global_best_lap_participant = ""

	global_best_sections.clear()

	var section_count := 0

	# --------------------------------------------------------
	# Déterminer le nombre de secteurs
	# --------------------------------------------------------
	for result in results:

		var best_sections: Array = (
			result.get(
				"best_section_times",
				[]
			)
		)

		section_count = max(
			section_count,
			best_sections.size()
		)


	for i in range(section_count):

		global_best_sections.append(
			0.0
		)

	# --------------------------------------------------------
	# Meilleur tour + meilleurs secteurs
	# --------------------------------------------------------
	for result in results:

		var nickname := String(
			result.get(
				"nickname",
				"?"
			)
		)

		var best_lap := float(
			result.get(
				"best_lap_time",
				0.0
			)
		)

		if (
			best_lap > 0.0
			and (
				global_best_lap <= 0.0
				or best_lap < global_best_lap
			)
		):

			global_best_lap = best_lap
			global_best_lap_participant = nickname


		var best_sections: Array = (
			result.get(
				"best_section_times",
				[]
			)
		)

		for i in range(
			min(
				best_sections.size(),
				global_best_sections.size()
			)
		):

			var value := float(
				best_sections[i]
			)

			if value <= 0.0:
				continue

			if (
				global_best_sections[i] <= 0.0
				or value < global_best_sections[i]
			):

				global_best_sections[i] = value


func _build_result_rows() -> void:

	for child in results_list.get_children():
		child.queue_free()

	var section_count := (
		global_best_sections.size()
	)

	for result in results:

		var row := RESULT_ROW_SCENE.instantiate()

		results_list.add_child(row)

		row.setup(
			result,
			global_best_lap,
			global_best_sections,
			section_count
		)


func _update_global_best_label() -> void:

	if global_best_lap <= 0.0:
		best_lap_name_label.text = (
			"DNF"
		)
		best_lap_label.text = (
			"--:--.---"
		)
		return
	
	best_lap_name_label.text = (
			global_best_lap_participant
		)
	
	best_lap_label.text = (
		"%s"
		% [
			_format_time(global_best_lap)
		]
	)


func _on_restart_pressed() -> void:

	if not GameManager.restart_active_race():
		return

	NavigationManager.go_to(
		"res://level/scene/Race.tscn"
	)


func _on_track_selection_pressed() -> void:

	GameManager.prepare_race_setup()

	NavigationManager.go_to(
		"res://ui/scene/RaceSetup.tscn"
	)


func _on_main_menu_pressed() -> void:

	GameManager.clear_active_race()

	NavigationManager.go_to(
		"res://ui/scene/MainMenu.tscn"
	)


func _format_time(time_seconds: float) -> String:

	if time_seconds <= 0.0:
		return "--:--.---"

	var minutes := int(
		time_seconds
	 / 60)

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
