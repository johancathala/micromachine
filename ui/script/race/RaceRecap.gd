extends Control
class_name RaceRecap


const RESULT_ROW_SCENE := preload(
	"res://ui/scene/RaceResultRow.tscn"
)


@onready var title_label: Label = $MarginContainer/VBoxContainer/Title

@onready var track_name_label: Label = $MarginContainer/VBoxContainer/TrackName

@onready var results_list: VBoxContainer = $MarginContainer/VBoxContainer/ResultsPanel/MarginContainer/ResultsScroll/ResultsList

@onready var best_lap_name_label: Label = $MarginContainer/VBoxContainer/BestLapPanel/BestLapNameLabel

@onready var best_lap_label: Label = $MarginContainer/VBoxContainer/BestLapPanel/BestLapLabel

@onready var restart_button: Button = $MarginContainer/VBoxContainer/Buttons/RestartButton

@onready var track_selection_button: Button = $MarginContainer/VBoxContainer/Buttons/TrackSelectionButton

@onready var main_menu_button: Button = $MarginContainer/VBoxContainer/Buttons/MainMenuButton

@onready var focus_manager: MenuFocusManager = $MenuFocusManager

var results: Array[Dictionary] = []

var global_best_lap: float = 0.0
var global_best_lap_participant: String = ""

var global_best_sections: Array[float] = []


func _ready() -> void:
	AudioManager.play_results_music()
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
	if race_config != null:
		track_name_label.text = "Circuit : " + race_config.track.name

		BestTimesManager.save_race_results(
			results,
			race_config
		)

	_build_results()
	AudioManager.bind_sound_btt()
	set_focus()


func set_focus() -> void:
	focus_manager.set_vertical_navigation([
		results_list,
		main_menu_button
	])
	
	focus_manager.set_neighbors(main_menu_button,null,null,restart_button,track_selection_button)
	focus_manager.set_neighbors(track_selection_button,null,null,main_menu_button,restart_button)
	focus_manager.set_neighbors(restart_button,null,null,track_selection_button,main_menu_button)


func _build_results() -> void:

	# Contre-la-montre : classement des tours de la session.
	var race_config: RaceConfig = GameManager.get_active_race_config()

	if race_config != null and race_config.is_time_trial() and not GameManager.last_ghost_laps.is_empty():
		_build_time_trial()
		return

	if results.is_empty():

		push_warning(
			"RaceRecap : aucun résultat disponible."
		)

		return

	_build_title()
	
	_find_global_bests()

	_build_result_rows()

	_update_global_best_label()


# ============================================================
# CONTRE-LA-MONTRE : classement des tours et médailles
# ============================================================
# Chaque tour valide de la session est une ligne, comme un pilote dans
# un classement, du plus rapide au plus lent. Le meilleur temps du
# joueur avec cette voiture sur ce circuit est enregistré d'office
# (fantôme Platine). Les boutons OR, ARGENT, BRONZE gardent un tour
# comme fantôme de cette médaille (un par médaille : si elle existe
# déjà, un second appui confirme le remplacement). Ces fantômes sont
# proposés sur l'écran des IA (« Flavien Or »).

const TT_FONT_SIZE := 28
const TT_SMALL_FONT_SIZE := 20
const TT_BUTTON_MEDALS := ["or", "argent", "bronze"]

var _tt_laps: Array[Dictionary] = []
var _tt_medals: Dictionary = {}
var _tt_medals_label: Label = null
# Bouton en attente de confirmation (remplacement d'une médaille).
var _tt_pending: Button = null


func _build_time_trial() -> void:
	_tt_laps.clear()
	_tt_laps.append_array(GameManager.last_ghost_laps)
	_tt_laps.sort_custom(func(a, b): return float(a["lap_time"]) < float(b["lap_time"]))

	var first: Dictionary = _tt_laps[0]
	title_label.text = "CONTRE-LA-MONTRE"
	best_lap_name_label.text = String(first.get("nickname", "?"))
	best_lap_label.text = _format_time(float(first["lap_time"]))

	for child in results_list.get_children():
		child.queue_free()

	_tt_medals_label = Label.new()
	_tt_medals_label.add_theme_font_size_override("font_size", TT_SMALL_FONT_SIZE)
	_tt_medals_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tt_medals_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	results_list.add_child(_tt_medals_label)
	_refresh_medals()

	var best := float(first["lap_time"])

	for i in range(_tt_laps.size()):
		results_list.add_child(_time_trial_row(i, _tt_laps[i], best))


func _time_trial_row(rank: int, lap: Dictionary, best: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var lap_time := float(lap["lap_time"])

	var cells := [
		[RaceParticipantHUD.PLACE.get(rank + 1, str(rank + 1)), 90, HORIZONTAL_ALIGNMENT_CENTER],
		["Tour %d" % int(lap.get("lap", 0)), 120, HORIZONTAL_ALIGNMENT_LEFT],
		[_format_time(lap_time), 150, HORIZONTAL_ALIGNMENT_RIGHT],
		["" if rank == 0 else "+%.3f" % (lap_time - best), 120, HORIZONTAL_ALIGNMENT_RIGHT],
	]

	for cell in cells:
		var label := Label.new()
		label.text = cell[0]
		label.custom_minimum_size = Vector2(cell[1], 0)
		label.horizontal_alignment = cell[2]
		label.add_theme_font_size_override("font_size", TT_FONT_SIZE)
		row.add_child(label)

	(row.get_child(0) as Label).modulate = RaceParticipantHUD.POSITION_COLORS.get(rank + 1, Color.WHITE)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(24, 0)
	row.add_child(spacer)

	for medal in TT_BUTTON_MEDALS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(170, 0)
		button.add_theme_font_size_override("font_size", TT_SMALL_FONT_SIZE)
		button.add_theme_color_override("font_color", GhostManager.MEDAL_COLORS[medal])
		button.set_meta("medal", medal)
		button.set_meta("label", "GARDER EN %s" % String(GhostManager.MEDAL_NAMES[medal]).to_upper())
		button.text = button.get_meta("label")
		button.pressed.connect(_on_medal_pressed.bind(button, lap, medal))
		row.add_child(button)

	return row


func _on_medal_pressed(button: Button, lap: Dictionary, medal: String) -> void:
	# Médaille déjà prise par un autre tour : confirmer le remplacement.
	var current: Dictionary = _tt_medals.get(medal, {})
	var same_lap := not current.is_empty() and is_equal_approx(float(current.get("lap_time", 0.0)), float(lap["lap_time"]))

	if not current.is_empty() and not same_lap and _tt_pending != button:
		_cancel_pending()
		_tt_pending = button
		button.text = "REMPLACER %s ?" % _format_time(float(current["lap_time"]))
		return

	_cancel_pending()

	if GhostManager.save_medal(lap, medal):
		_refresh_medals()
		button.text = "%s GARDÉ" % String(GhostManager.MEDAL_NAMES[medal]).to_upper()


func _cancel_pending() -> void:
	if _tt_pending != null and is_instance_valid(_tt_pending):
		_tt_pending.text = _tt_pending.get_meta("label")

	_tt_pending = null


## Fantômes du joueur pour ce circuit et cette voiture.
func _refresh_medals() -> void:
	var lap: Dictionary = _tt_laps[0]
	_tt_medals = GhostManager.load_medals(int(lap.get("track_id", -1)), String(lap.get("car_id", "")), String(lap.get("nickname", "")))

	var parts: PackedStringArray = []

	for medal in GhostManager.MEDALS:
		var data: Dictionary = _tt_medals.get(medal, {})
		parts.append("%s %s" % [
			GhostManager.MEDAL_NAMES[medal],
			_format_time(float(data["lap_time"])) if not data.is_empty() else "—"
		])

	_tt_medals_label.text = "Tes fantômes avec cette voiture : " + "   ·   ".join(parts) + "\n(Platine : ton meilleur temps, enregistré d'office.)"


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

	AudioManager.play_start_event()
	await get_tree().create_timer(1.0).timeout
	NavigationManager.go("Race",true,true)


func _on_track_selection_pressed() -> void:

	GameManager.prepare_race_setup()

	NavigationManager.go("RaceSetup")


func _on_main_menu_pressed() -> void:

	GameManager.clear_active_race()

	NavigationManager.go("MainMenu")


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
