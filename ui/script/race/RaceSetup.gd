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
@onready var preview_image: TextureRect = get_node(SETTINGS_PATH + "TrackPreview/PreviewVBox/PreviewImage")
@onready var preview_label: Label = get_node(SETTINGS_PATH + "TrackPreview/PreviewVBox/PreviewLabel")

# Pilotes fantômes : fantôme retrouvé pour chacun sur ce circuit.
var ghost_pilots_label: Label
var podium: TimePodium


func _ready() -> void:
	AudioManager.bind_sound_btt()
	race_config = GameManager.get_pending_race_config()
	track_catalog = GameManager.get_tracks()

	if race_config == null:
		race_config = RaceConfig.new()
		race_config.mode = GameManager.GameMode.SINGLE_RACE

	race_config.build_participants()

	# Les joueurs ont rejoint sur l'écran précédent.
	($MarginContainer/VBoxContainer/MainContent/PlayersPanel as Control).hide()

	ghost_pilots_label = Label.new()
	ghost_pilots_label.add_theme_font_size_override("font_size", 28)
	ghost_pilots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ghost_pilots_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var preview_box := preview_label.get_parent()
	preview_box.add_child(ghost_pilots_label)

	# Contre-la-montre : podium des meilleurs temps à côté de l'aperçu.
	var preview_row := HBoxContainer.new()
	preview_row.size_flags_vertical = preview_image.size_flags_vertical
	preview_row.add_theme_constant_override("separation", 24)
	preview_box.add_child(preview_row)
	preview_box.move_child(preview_row, preview_image.get_index())
	preview_image.reparent(preview_row)
	preview_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Aperçu à la largeur de son image (hauteur disponible), podium collé.
	preview_row.resized.connect(func() -> void:
		var texture := preview_image.texture

		if texture != null and texture.get_height() > 0:
			preview_image.custom_minimum_size.x = preview_row.size.y * texture.get_width() / texture.get_height()
	)
	podium = TimePodium.new()
	podium.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_row.add_child(podium)

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

	# Circuit en cours, sinon le premier.
	if race_config.track.is_empty() or track_selector.get_item_index(int(race_config.track.get("id", -1))) < 0:
		race_config.track = track_catalog.get(0)

	track_selector.select(track_selector.get_item_index(int(race_config.track.id)))


func _setup_laps() -> void:
	lap_selector.clear()

	for laps in LAP_COUNTS:
		lap_selector.add_item(str(laps), laps)

	# Nombre de tours en cours (3 par défaut).
	if lap_selector.get_item_index(race_config.lap_count) < 0:
		race_config.lap_count = 3

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

	track_selector.item_selected.connect(func(index: int) -> void:
		race_config.track = track_catalog.get(index)
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
	_refresh_ghost_pilots()
	_refresh_summary()
	start_button.disabled = not race_config.is_valid()
	_set_focus_navigation()


## Aperçu du circuit choisi (vue d'ensemble avec le parcours).
func _refresh_track_preview() -> void:
	var texture := TrackCatalog.get_preview(int(race_config.track.get("id", -1)))

	if texture != null:
		preview_image.texture = texture

	preview_label.text = String(race_config.track.get("name", ""))
	_refresh_podium()


## Trois meilleurs temps du circuit (tous joueurs, toutes voitures).
func _refresh_podium() -> void:
	podium.visible = race_config.is_time_trial()

	if not podium.visible:
		return

	var track_id := int(race_config.track.get("id", -1))
	var times: Array = []

	for record in BestTimesManager.get_records():
		if int(record.get("track_id", -2)) == track_id and float(record.get("lap_time", 0.0)) > 0.0:
			times.append(record)

	times.sort_custom(func(a, b): return float(a["lap_time"]) < float(b["lap_time"]))
	podium.set_entries(times.slice(0, 3))


## Pilotes fantômes : fantôme retrouvé pour leur voiture sur ce
## circuit, sinon ils roulent en Expert.
func _refresh_ghost_pilots() -> void:
	var lines: PackedStringArray = []
	var track_id := int(race_config.track.get("id", -1))

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

	if race_config.is_classic():
		text += " + %d IA" % race_config.get_enabled_ai_count()
	elif race_config.is_elimination():
		text = "Élimination : %s + %d IA" % [text, race_config.get_enabled_ai_count()]
	else:
		text = "Contre-la-montre : seul contre votre fantôme"

	help_label.text = text


func _set_focus_navigation() -> void:
	var settings: Array[Control] = [track_selector, lap_selector]

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

	if not race_config.is_valid() or not race_config.is_car_selection_valid():
		push_warning("RaceSetup : configuration de course invalide.")
		return

	GameManager.set_pending_race_config(race_config)

	if not GameManager.start_race():
		return

	start_button.disabled = true
	AudioManager.play_start_event()
	await get_tree().create_timer(1.0).timeout
	NavigationManager.go("Race", true, true)
