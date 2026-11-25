extends Control

const ROW_FONT_SIZE := 30

@onready var title_label: Label = $MarginContainer/VBoxContainer/Title
@onready var subtitle_label: Label = $MarginContainer/VBoxContainer/Subtitle
@onready var champion_label: Label = $MarginContainer/VBoxContainer/Champion
@onready var standings_list: VBoxContainer = $MarginContainer/VBoxContainer/StandingsPanel/MarginContainer/StandingsScroll/StandingsList
@onready var continue_button: Button = $MarginContainer/VBoxContainer/Buttons/ContinueButton
@onready var main_menu_button: Button = $MarginContainer/VBoxContainer/Buttons/MainMenuButton
@onready var focus_manager: MenuFocusManager = $MenuFocusManager


func _ready() -> void:
	AudioManager.play_results_music()
	continue_button.pressed.connect(_on_continue_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	AudioManager.bind_sound_btt()

	var race_config: RaceConfig = GameManager.get_active_race_config()

	if race_config == null or not race_config.is_championship():
		push_error("ChampionshipStandings : aucun championnat actif.")
		continue_button.disabled = true
		return

	var standings: Array[Dictionary] = GameManager.get_championship_standings()

	if standings.is_empty():
		push_error("ChampionshipStandings : classement du championnat vide.")
		continue_button.disabled = true
		return

	var race_number: int = race_config.championship_race_index + 1
	var race_count: int = race_config.championship_tracks.size()
	var track_name := String(race_config.track.get("name", "?"))
	var is_final: bool = race_number >= race_count

	title_label.text = "RÉSULTAT DU CHAMPIONNAT" if is_final else "CLASSEMENT DU CHAMPIONNAT"
	subtitle_label.text = "Après la course %d/%d — %s" % [
		race_number,
		race_count,
		track_name
	]
	champion_label.visible = is_final
	continue_button.visible = not is_final
	main_menu_button.text = "TERMINER LE CHAMPIONNAT" if is_final else "QUITTER LE CHAMPIONNAT"

	if is_final:
		var champion: Dictionary = standings[0]
		champion_label.text = "%s remporte le championnat avec %d points !" % [
			String(champion.get("nickname", "?")),
			int(champion.get("points", 0))
		]

	_build_standings(standings)
	_set_focus()


func _build_standings(standings: Array[Dictionary]) -> void:
	for child in standings_list.get_children():
		child.queue_free()

	var header := HBoxContainer.new()
	_add_cell(header, "POS.", 100, HORIZONTAL_ALIGNMENT_CENTER)
	_add_cell(header, "PARTICIPANT", 0, HORIZONTAL_ALIGNMENT_LEFT, true)
	_add_cell(header, "POINTS COURSE", 180, HORIZONTAL_ALIGNMENT_CENTER)
	_add_cell(header, "TOTAL", 180, HORIZONTAL_ALIGNMENT_CENTER)
	standings_list.add_child(header)

	for i in range(standings.size()):
		var standing := standings[i]
		var row := HBoxContainer.new()
		var position_label := _add_cell(row, str(i + 1), 100, HORIZONTAL_ALIGNMENT_CENTER)
		position_label.add_theme_color_override(
			"font_color",
			RaceParticipantHUD.POSITION_COLORS.get(i + 1, Color.WHITE)
		)
		_add_cell(row, String(standing.get("nickname", "?")), 0, HORIZONTAL_ALIGNMENT_LEFT, true)
		_add_cell(
			row,
			"%d pts" % int(standing.get("last_race_points", 0)),
			180,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		_add_cell(
			row,
			"%d pts" % int(standing.get("points", 0)),
			180,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		standings_list.add_child(row)


func _add_cell(
	row: HBoxContainer,
	text: String,
	width: float,
	alignment: HorizontalAlignment,
	expand: bool = false
) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = width
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_SHRINK_BEGIN
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	row.add_child(label)
	return label


func _set_focus() -> void:
	var buttons: Array[Control] = [main_menu_button]

	if continue_button.visible:
		buttons.append(continue_button)

	focus_manager.set_horizontal_navigation(buttons, false)
	focus_manager.set_neighbors(main_menu_button, null, null, null, continue_button if continue_button.visible else null)
	focus_manager.set_neighbors(continue_button, null, null, main_menu_button)


func _on_continue_pressed() -> void:
	if not GameManager.start_next_championship_race():
		return

	AudioManager.play_start_event()
	NavigationManager.go("Race", true, true)


func _on_main_menu_pressed() -> void:
	GameManager.clear_active_race()
	NavigationManager.go("MainMenu")
