extends Control

# ============================================================
# CIRCUIT ET RÉGLAGES (dernier écran avant la course)
# ============================================================
#
# Parcours : Mode → Joueurs → IA (course classique) → Circuit → Course.
# Le plateau (joueurs, IA) est déjà fait : on choisit où courir et
# les réglages de la course, puis on lance le départ. Le récapitulatif
# de fin de course revient ici (« changer de circuit ») avec les mêmes
# joueurs et les mêmes IA.
# ============================================================

enum ScreenMode {
	SHARED,
	SPLIT
}

const TARGET_SCORES := [12, 16, 20, 30, 40]
const LAP_COUNTS := [1, 2, 3, 4, 5, 7, 10, 15, 20]
const DEFAULT_LAP_COUNT := 3
## Sélecteur de tours : « ∞ » grisé hors course classique.
const INFINITE_LAPS_ID := 9999

const SETTINGS_PATH := "MarginContainer/VBoxContainer/MainContent/SettingsPanel/SettingsMargin/SettingsVBox/"

var race_config: RaceConfig
var track_catalog: Array

@onready var back_button: Button = $MarginContainer/VBoxContainer/Footer/BackButton
@onready var start_button: Button = $MarginContainer/VBoxContainer/Footer/StartButton
@onready var help_label: Label = $MarginContainer/VBoxContainer/Footer/HelpLabel
@onready var focus_manager: MenuFocusManager = $MenuFocusManager

@onready var track_selector: OptionButton = get_node(SETTINGS_PATH + "TrackRow/Track")
@onready var lap_selector: OptionButton = get_node(SETTINGS_PATH + "LapCountRow/LapCount")
@onready var target_score_row: HBoxContainer = get_node(SETTINGS_PATH + "TargetScoreRow")
@onready var target_score_selector: OptionButton = get_node(SETTINGS_PATH + "TargetScoreRow/TargetScore")
@onready var screen_mode_row: HBoxContainer = get_node(SETTINGS_PATH + "ScreenModeRow")
@onready var screen_mode_selector: OptionButton = get_node(SETTINGS_PATH + "ScreenModeRow/ScreenMode")
@onready var tire_wear_row: HBoxContainer = get_node(SETTINGS_PATH + "TireWearRow")
@onready var tire_wear_selector: OptionButton = get_node(SETTINGS_PATH + "TireWearRow/TireWear")
@onready var ghost_row: HBoxContainer = get_node(SETTINGS_PATH + "GhostRow")
@onready var ghost_selector: OptionButton = get_node(SETTINGS_PATH + "GhostRow/GhostMode")
@onready var championship_panel: PanelContainer = get_node(SETTINGS_PATH + "ChampionshipPanel")
@onready var championship_add_button: Button = get_node(SETTINGS_PATH + "ChampionshipPanel/ChampionshipMargin/ChampionshipVBox/AddTrackButton")
@onready var championship_tracks_list: VBoxContainer = get_node(SETTINGS_PATH + "ChampionshipPanel/ChampionshipMargin/ChampionshipVBox/TrackListScroll/TrackList")
@onready var preview_image: TextureRect = get_node(SETTINGS_PATH + "TrackPreview/PreviewVBox/PreviewImage")
@onready var preview_label: Label = get_node(SETTINGS_PATH + "TrackPreview/PreviewVBox/PreviewLabel")

# Pilotes fantômes : fantôme retrouvé pour chacun sur ce circuit.
var ghost_pilots_label: Label
var podium: TimePodium
var record_row: HBoxContainer
var record_icon: TextureRect
var record_label: Label
var selected_track: Dictionary = {}


func _ready() -> void:
	AudioManager.bind_sound_btt()
	race_config = GameManager.get_pending_race_config()
	track_catalog = GameManager.get_tracks()

	if race_config == null:
		race_config = RaceConfig.new()
		race_config.mode = GameManager.GameMode.SINGLE_RACE

	race_config.build_participants()

	ghost_pilots_label = Label.new()
	ghost_pilots_label.add_theme_font_size_override("font_size", 28)
	ghost_pilots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ghost_pilots_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var preview_box := preview_label.get_parent()
	preview_box.add_child(ghost_pilots_label)

	# Contre-la-montre : record du circuit en haut (toutes voitures, avec
	# la miniature de la voiture), puis podium à gauche et aperçu du
	# circuit à droite.
	record_row = HBoxContainer.new()
	record_row.alignment = BoxContainer.ALIGNMENT_CENTER
	record_row.add_theme_constant_override("separation", 16)
	record_icon = TextureRect.new()
	record_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	record_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	record_icon.custom_minimum_size = Vector2(72, 48)
	record_row.add_child(record_icon)
	record_label = Label.new()
	record_label.add_theme_font_size_override("font_size", 34)
	record_label.add_theme_color_override("font_color", Color("#ffd54f"))
	record_row.add_child(record_label)
	preview_box.add_child(record_row)
	preview_box.move_child(record_row, 0)

	var preview_row := HBoxContainer.new()
	preview_row.size_flags_vertical = preview_image.size_flags_vertical
	preview_row.add_theme_constant_override("separation", 24)
	preview_box.add_child(preview_row)
	preview_box.move_child(preview_row, preview_image.get_index())
	podium = TimePodium.new()
	podium.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	podium.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_row.add_child(podium)
	preview_image.reparent(preview_row)
	preview_image.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_setup_tracks()
	_setup_laps()
	_setup_screen_modes()
	_setup_tire_wear()
	_setup_ghost_modes()
	_setup_target_scores()
	_apply_game_type_ui()
	_connect_signals()
	_refresh_ui()


# ================================================================
# Réglages
# ================================================================

func _setup_tracks() -> void:
	track_selector.clear()

	for track: Dictionary in track_catalog:
		track_selector.add_item(track.name, track.id)

	if not LAP_COUNTS.has(race_config.lap_count):
		race_config.lap_count = DEFAULT_LAP_COUNT

	# Circuit en cours, sinon le premier.
	if race_config.track.is_empty() or track_selector.get_item_index(int(race_config.track.get("id", -1))) < 0:
		race_config.track = track_catalog.get(0)

	if race_config.allows_ai():
		var valid_tracks: Array[Dictionary] = []

		for scheduled_track in race_config.championship_tracks:
			for catalog_track in track_catalog:
				if int(catalog_track["id"]) == int(scheduled_track.get("id", -1)):
					var normalized_track: Dictionary = catalog_track.duplicate(true)
					var scheduled_lap_count := int(
						scheduled_track.get("lap_count", race_config.lap_count)
					)
					normalized_track["lap_count"] = (
						scheduled_lap_count
						if LAP_COUNTS.has(scheduled_lap_count)
						else DEFAULT_LAP_COUNT
					)
					valid_tracks.append(normalized_track)
					break

		if valid_tracks.is_empty():
			var initial_track := race_config.track.duplicate(true)
			initial_track["lap_count"] = race_config.lap_count
			valid_tracks.append(initial_track)

		race_config.championship_tracks = valid_tracks
		race_config.track = valid_tracks[0].duplicate(true)
		race_config.lap_count = int(valid_tracks[0]["lap_count"])

		_sync_championship_mode()
	else:
		race_config.championship_tracks.clear()
		race_config.mode = GameManager.GameMode.SINGLE_RACE

	selected_track = race_config.track.duplicate(true)
	track_selector.select(track_selector.get_item_index(int(selected_track.id)))


func _setup_laps() -> void:
	lap_selector.clear()

	for laps in LAP_COUNTS:
		lap_selector.add_item(str(laps), laps)

	# Nombre de tours en cours (3 par défaut).
	if lap_selector.get_item_index(race_config.lap_count) < 0:
		race_config.lap_count = DEFAULT_LAP_COUNT

	lap_selector.select(lap_selector.get_item_index(race_config.lap_count))


func _setup_screen_modes() -> void:
	screen_mode_selector.clear()
	screen_mode_selector.add_item("Écran partagé", ScreenMode.SHARED)
	screen_mode_selector.add_item("Écran splitté", ScreenMode.SPLIT)
	screen_mode_selector.select(screen_mode_selector.get_item_index(
		ScreenMode.SPLIT if race_config.split_screen else ScreenMode.SHARED
	))


func _setup_tire_wear() -> void:
	tire_wear_selector.clear()
	tire_wear_selector.add_item("Non", 0)
	tire_wear_selector.add_item("Oui (arrêts au stand)", 1)
	tire_wear_selector.select(1 if race_config.tire_wear else 0)


func _setup_ghost_modes() -> void:
	ghost_selector.clear()

	# Identifiants = GhostManager.GhostMode.
	ghost_selector.add_item("Les deux", 0)
	ghost_selector.add_item("Le meilleur", 1)
	ghost_selector.add_item("Le mien", 2)
	ghost_selector.select(ghost_selector.get_item_index(race_config.ghost_mode))


func _setup_target_scores() -> void:
	target_score_selector.clear()

	for score in TARGET_SCORES:
		target_score_selector.add_item("%d points" % score, score)

	if target_score_selector.get_item_index(race_config.target_score) < 0:
		race_config.target_score = RaceConfig.DEFAULT_TARGET_SCORE

	target_score_selector.select(target_score_selector.get_item_index(race_config.target_score))


## Réglages propres au mode choisi au début.
func _apply_game_type_ui() -> void:
	var classic := race_config.is_classic()

	target_score_row.visible = race_config.is_elimination()
	championship_panel.visible = race_config.allows_ai()
	lap_selector.get_parent().visible = not classic
	# Écran splitté : course classique à plusieurs joueurs.
	screen_mode_row.visible = classic and race_config.get_human_player_count() >= 2
	tire_wear_row.visible = classic
	ghost_row.visible = race_config.is_time_trial()
	# Tours illimités (∞, grisé) en élimination et en contre-la-montre.
	_show_infinite_laps(not classic)


func _show_infinite_laps(infinite: bool) -> void:
	var infinite_index := lap_selector.get_item_index(INFINITE_LAPS_ID)

	if infinite:
		if infinite_index < 0:
			lap_selector.add_item("∞", INFINITE_LAPS_ID)
			infinite_index = lap_selector.get_item_index(INFINITE_LAPS_ID)

		lap_selector.select(infinite_index)
		lap_selector.disabled = true
		return

	if infinite_index >= 0:
		lap_selector.remove_item(infinite_index)

	lap_selector.disabled = false
	lap_selector.select(lap_selector.get_item_index(race_config.lap_count))


func _connect_signals() -> void:
	back_button.pressed.connect(_on_back_pressed)
	start_button.pressed.connect(_on_start_pressed)
	championship_add_button.pressed.connect(_on_add_championship_track)

	track_selector.item_selected.connect(func(index: int) -> void:
		selected_track = track_catalog[index].duplicate(true)
		if not race_config.is_championship():
			race_config.track = selected_track.duplicate(true)

		_refresh_ui()
	)
	lap_selector.item_selected.connect(func(index: int) -> void:
		race_config.lap_count = lap_selector.get_item_id(index)
		_refresh_ui()
	)
	target_score_selector.item_selected.connect(func(index: int) -> void:
		race_config.target_score = target_score_selector.get_item_id(index)
	)
	screen_mode_selector.item_selected.connect(func(index: int) -> void:
		race_config.split_screen = screen_mode_selector.get_item_id(index) == ScreenMode.SPLIT
	)
	tire_wear_selector.item_selected.connect(func(index: int) -> void:
		race_config.tire_wear = tire_wear_selector.get_item_id(index) == 1
	)
	ghost_selector.item_selected.connect(func(index: int) -> void:
		race_config.ghost_mode = ghost_selector.get_item_id(index)
	)


# ================================================================
# Affichage
# ================================================================

func _refresh_ui() -> void:
	_refresh_track_preview()
	_refresh_championship_schedule()
	_refresh_ghost_pilots()
	_refresh_summary()
	start_button.disabled = not race_config.is_valid()
	_set_focus_navigation()


## Aperçu du circuit choisi (vue d'ensemble avec le parcours).
func _refresh_track_preview() -> void:
	var texture := TrackCatalog.get_preview(int(selected_track.get("id", -1)))

	if texture != null:
		preview_image.texture = texture

	preview_label.text = String(selected_track.get("name", ""))
	_refresh_podium()


func _refresh_championship_schedule() -> void:
	for child in championship_tracks_list.get_children():
		championship_tracks_list.remove_child(child)
		child.queue_free()

	var count: int = race_config.championship_tracks.size()

	for i in range(count):
		var track: Dictionary = race_config.championship_tracks[i]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%d. %s" % [i + 1, String(track.get("name", "?"))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 28)
		row.add_child(label)

		var up_button := Button.new()
		up_button.text = "↑"
		up_button.custom_minimum_size = Vector2(44, 40)
		up_button.add_theme_font_size_override("font_size", 24)
		up_button.disabled = i == 0
		up_button.pressed.connect(_on_move_championship_track.bind(i, -1))
		row.add_child(up_button)

		var down_button := Button.new()
		down_button.text = "↓"
		down_button.custom_minimum_size = Vector2(44, 40)
		down_button.add_theme_font_size_override("font_size", 24)
		down_button.disabled = i == count - 1
		down_button.pressed.connect(_on_move_championship_track.bind(i, 1))
		row.add_child(down_button)

		if race_config.is_classic():
			var track_lap_selector := OptionButton.new()
			track_lap_selector.custom_minimum_size = Vector2(120, 40)
			track_lap_selector.add_theme_font_size_override("font_size", 20)

			for lap_count in LAP_COUNTS:
				track_lap_selector.add_item("%d tours" % lap_count, lap_count)

			var track_lap_count := int(track.get("lap_count", DEFAULT_LAP_COUNT))
			var lap_item_index := track_lap_selector.get_item_index(track_lap_count)

			if lap_item_index < 0:
				lap_item_index = track_lap_selector.get_item_index(DEFAULT_LAP_COUNT)

			track_lap_selector.select(lap_item_index)
			track_lap_selector.item_selected.connect(
				_on_championship_lap_count_selected.bind(i, track_lap_selector)
			)
			row.add_child(track_lap_selector)
		else:
			var infinite_laps_label := Label.new()
			infinite_laps_label.text = "∞ tours"
			infinite_laps_label.add_theme_font_size_override("font_size", 20)
			row.add_child(infinite_laps_label)

		var remove_button := Button.new()
		remove_button.text = "×"
		remove_button.custom_minimum_size = Vector2(44, 40)
		remove_button.add_theme_font_size_override("font_size", 24)
		remove_button.pressed.connect(_on_remove_championship_track.bind(i))
		row.add_child(remove_button)
		championship_tracks_list.add_child(row)

	if count == 0:
		var empty_label := Label.new()
		empty_label.text = "Aucune course au programme"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		championship_tracks_list.add_child(empty_label)


func _sync_championship_mode() -> void:
	if race_config.championship_tracks.size() > 1:
		race_config.mode = GameManager.GameMode.CHAMPIONSHIP
		race_config.track = race_config.championship_tracks[0].duplicate(true)
		race_config.lap_count = int(
			race_config.championship_tracks[0].get("lap_count", race_config.lap_count)
		)
	else:
		race_config.mode = GameManager.GameMode.SINGLE_RACE

		if not race_config.championship_tracks.is_empty():
			race_config.track = race_config.championship_tracks[0].duplicate(true)
			race_config.lap_count = int(
				race_config.championship_tracks[0].get("lap_count", race_config.lap_count)
			)

		race_config.championship_race_index = 0
		race_config.championship_standings.clear()
		race_config.championship_race_recorded = false


func _on_add_championship_track() -> void:
	if not race_config.allows_ai():
		return

	var scheduled_track := selected_track.duplicate(true)
	scheduled_track["lap_count"] = race_config.lap_count
	race_config.championship_tracks.append(scheduled_track)
	_sync_championship_mode()
	_refresh_ui()
	focus_manager.set_focus(track_selector)


func _on_championship_lap_count_selected(
	option_index: int,
	race_index: int,
	selector: OptionButton
) -> void:
	if race_index < 0 or race_index >= race_config.championship_tracks.size():
		return

	var scheduled_track: Dictionary = race_config.championship_tracks[race_index].duplicate(true)
	scheduled_track["lap_count"] = selector.get_item_id(option_index)
	race_config.championship_tracks[race_index] = scheduled_track
	_sync_championship_mode()
	start_button.disabled = not race_config.is_valid()
	_refresh_summary()


func _on_remove_championship_track(index: int) -> void:
	if index < 0 or index >= race_config.championship_tracks.size():
		return

	race_config.championship_tracks.remove_at(index)

	if race_config.championship_tracks.size() == 1:
		race_config.track = race_config.championship_tracks[0].duplicate(true)
		race_config.lap_count = int(
			race_config.championship_tracks[0].get("lap_count", race_config.lap_count)
		)
		selected_track = race_config.track.duplicate(true)
		track_selector.select(track_selector.get_item_index(int(selected_track.id)))

	_sync_championship_mode()
	_refresh_ui()
	focus_manager.set_focus(track_selector)


func _on_move_championship_track(index: int, direction: int) -> void:
	var target := index + direction

	if index < 0 or index >= race_config.championship_tracks.size():
		return

	if target < 0 or target >= race_config.championship_tracks.size():
		return

	var track: Dictionary = race_config.championship_tracks[index]
	race_config.championship_tracks[index] = race_config.championship_tracks[target]
	race_config.championship_tracks[target] = track
	_sync_championship_mode()
	_refresh_ui()
	focus_manager.set_focus(track_selector)


## Contre-la-montre : record du circuit (toutes voitures) et podium
## des trois meilleurs temps avec la voiture du joueur.
func _refresh_podium() -> void:
	var time_trial := race_config.is_time_trial()
	podium.visible = time_trial
	record_row.visible = time_trial

	if not time_trial:
		return

	var track_id := int(selected_track.get("id", -1))
	var car_id := String(race_config.players[0].get("car_id", "")) if not race_config.players.is_empty() else ""
	var car := CarCatalog.get_car(car_id)
	var all_times: Array = []
	var car_times: Array = []

	for record in BestTimesManager.get_records():
		if int(record.get("track_id", -2)) != track_id or float(record.get("lap_time", 0.0)) <= 0.0:
			continue

		all_times.append(record)

		if String(record.get("car_id", "")) == car_id:
			car_times.append(record)

	var by_time := func(a, b): return float(a["lap_time"]) < float(b["lap_time"])
	all_times.sort_custom(by_time)
	car_times.sort_custom(by_time)

	podium.title = "MEILLEURS TEMPS EN %s" % (car.display_name.to_upper() if car != null else "?")
	podium.set_entries(car_times.slice(0, 3))

	if all_times.is_empty():
		record_icon.texture = null
		record_label.text = "Record du circuit : aucun temps"
		return

	var best: Dictionary = all_times[0]
	var best_car := CarCatalog.get_car(String(best.get("car_id", "")))
	record_icon.texture = best_car.preview_texture if best_car != null else null
	record_label.text = "Record du circuit : %s — %s (%s)" % [
		TimePodium._format_time(float(best["lap_time"])),
		String(best.get("nickname", "?")),
		best_car.display_name if best_car != null else String(best.get("car_name", ""))
	]


## Pilotes fantômes : fantôme retrouvé pour leur voiture sur ce
## circuit, sinon ils roulent en Expert.
func _refresh_ghost_pilots() -> void:
	var lines: PackedStringArray = []
	var track_id := int(selected_track.get("id", -1))

	for participant in race_config.participants:
		if int(participant.get("ai_pilot", -1)) != RaceConfig.AIPilot.GHOST:
			continue

		var car_id := String(participant.get("car_id", ""))
		var car := CarCatalog.get_car(car_id)
		var car_name := car.display_name if car != null else car_id
		var ghost := GhostManager.load_ghost_for(track_id, car_id, String(participant.get("ai_ghost", "")))
		var pilot_name := String(participant.get("nickname", ""))

		if ghost.is_empty():
			lines.append("%s — fantôme %s : aucun, roulera en Expert" % [pilot_name, car_name])
		else:
			lines.append("%s — fantôme %s : %s, %.1f s" % [
				pilot_name, car_name, String(ghost.get("nickname", "?")), float(ghost.get("lap_time", 0.0))
			])

	ghost_pilots_label.text = "\n".join(lines)
	ghost_pilots_label.visible = not lines.is_empty()


func _refresh_summary() -> void:
	var players := race_config.get_human_player_count()
	var text := "%d joueur%s" % [players, "s" if players > 1 else ""]

	if race_config.is_championship():
		text += " + %d IA · Championnat : %d courses" % [
			race_config.get_enabled_ai_count(),
			race_config.championship_tracks.size()
		]
	elif race_config.is_classic():
		text += " + %d IA" % race_config.get_enabled_ai_count()
	elif race_config.is_elimination():
		text = "Élimination : %s + %d IA" % [text, race_config.get_enabled_ai_count()]
	else:
		text = "Contre-la-montre : seul contre votre fantôme"

	help_label.text = text


func _set_focus_navigation() -> void:
	var settings: Array[Control] = [track_selector]

	if championship_panel.visible:
		settings.append(championship_add_button)

		for row in championship_tracks_list.get_children():
			for child in row.get_children():
				if child is Button:
					settings.append(child)

	if lap_selector.get_parent().visible:
		settings.append(lap_selector)

	for row_selector: Array in [
		[screen_mode_row, screen_mode_selector],
		[tire_wear_row, tire_wear_selector],
		[ghost_row, ghost_selector],
		[target_score_row, target_score_selector]
	]:
		if (row_selector[0] as Control).visible:
			settings.append(row_selector[1])

	focus_manager.set_vertical_navigation(settings, false)

	var last_setting: Control = settings[settings.size() - 1]

	focus_manager.set_neighbors(last_setting, null, start_button)
	focus_manager.set_neighbors(back_button, last_setting, track_selector, start_button, start_button)
	focus_manager.set_neighbors(start_button, last_setting, track_selector, back_button, back_button)
	focus_manager.set_neighbors(track_selector, start_button)


# ================================================================
# Navigation
# ================================================================

func _on_back_pressed() -> void:
	GameManager.set_pending_race_config(race_config.duplicate_config())
	NavigationManager.go("AISetup" if race_config.allows_ai() else "CarSelection")


func _on_start_pressed() -> void:
	race_config.build_participants()
	_sync_championship_mode()

	if not race_config.is_valid() or not race_config.is_car_selection_valid():
		push_warning("RaceSetup : configuration de course invalide.")
		return

	race_config.championship_race_index = 0
	race_config.championship_standings.clear()
	race_config.championship_race_recorded = false
	GameManager.set_pending_race_config(race_config)

	if not GameManager.start_race():
		return

	start_button.disabled = true
	AudioManager.play_start_event()
	await get_tree().create_timer(1.0).timeout
	NavigationManager.go("Race", true, true)
