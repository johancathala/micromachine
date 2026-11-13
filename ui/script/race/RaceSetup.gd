extends Control

const PLAYER_SLOT_SCENE := preload("res://ui/scene/PlayerSlot.tscn")

const MAX_HUMAN_PLAYERS := 8

# Actions de JOIN fixes.
# Elles ne dépendent PAS des contrôles configurables.
const KEYBOARD_JOIN_KEY := KEY_E
const GAMEPAD_JOIN_BUTTON := JOY_BUTTON_B

enum AIDifficulty {
	NOVICE,
	MEDIUM,
	EXPERT
}


var race_config: RaceConfig
var track_catalog: Array


@onready var back_button: Button = ($MarginContainer/VBoxContainer/Footer/BackButton)

@onready var player_list: VBoxContainer = ($MarginContainer/VBoxContainer/MainContent/PlayersPanel/PlayersMargin/PlayersVBox/PlayerListScroll/PlayerList)

@onready var join_hint: Label = ($MarginContainer/VBoxContainer/MainContent/PlayersPanel/PlayersMargin/PlayersVBox/JoinHint)

@onready var ai_difficulty: OptionButton = ($MarginContainer/VBoxContainer/MainContent/SettingsPanel/SettingsMargin/SettingsVBox/AIDifficultyRow/AIDifficulty)

@onready var track_selector: OptionButton = ($MarginContainer/VBoxContainer/MainContent/SettingsPanel/SettingsMargin/SettingsVBox/TrackRow/Track)

@onready var lap_selector: OptionButton = ($MarginContainer/VBoxContainer/MainContent/SettingsPanel/SettingsMargin/SettingsVBox/LapCountRow/LapCount)

@onready var game_type_selector: OptionButton = ($MarginContainer/VBoxContainer/MainContent/SettingsPanel/SettingsMargin/SettingsVBox/GameTypeRow/GameType)

@onready var target_score_row: HBoxContainer = ($MarginContainer/VBoxContainer/MainContent/SettingsPanel/SettingsMargin/SettingsVBox/TargetScoreRow)

@onready var target_score_selector: OptionButton = ($MarginContainer/VBoxContainer/MainContent/SettingsPanel/SettingsMargin/SettingsVBox/TargetScoreRow/TargetScore)

const TARGET_SCORES := [5, 10, 15, 20, 30]

@onready var screen_mode_row: HBoxContainer = ($MarginContainer/VBoxContainer/MainContent/SettingsPanel/SettingsMargin/SettingsVBox/ScreenModeRow)

@onready var screen_mode_selector: OptionButton = ($MarginContainer/VBoxContainer/MainContent/SettingsPanel/SettingsMargin/SettingsVBox/ScreenModeRow/ScreenMode)

@onready var tire_wear_row: HBoxContainer = ($MarginContainer/VBoxContainer/MainContent/SettingsPanel/SettingsMargin/SettingsVBox/TireWearRow)

@onready var tire_wear_selector: OptionButton = ($MarginContainer/VBoxContainer/MainContent/SettingsPanel/SettingsMargin/SettingsVBox/TireWearRow/TireWear)

enum ScreenMode {
	SHARED,
	SPLIT
}

@onready var start_button: Button = ($MarginContainer/VBoxContainer/Footer/StartButton)

@onready var help_label: Label = ($MarginContainer/VBoxContainer/Footer/HelpLabel)

@onready var focus_manager: MenuFocusManager = $MenuFocusManager

func _ready() -> void:
	AudioManager.bind_sound_btt()
	race_config = GameManager.get_pending_race_config()
	track_catalog = GameManager.get_tracks()

	if race_config == null:
		race_config = RaceConfig.new()
		race_config.mode = GameManager.GameMode.SINGLE_RACE

	_setup_settings()
	_connect_signals()
	_refresh_ui()


func set_focus() -> void:
	var settings: Array[Control] = [
		ai_difficulty,
		track_selector,
		lap_selector,
		game_type_selector
	]

	if screen_mode_row.visible:
		settings.append(screen_mode_selector)

	if tire_wear_row.visible:
		settings.append(tire_wear_selector)

	if target_score_row.visible:
		settings.append(target_score_selector)

	focus_manager.set_vertical_navigation(settings)

	var last_setting: Control = settings[settings.size() - 1]

	focus_manager.set_neighbors(last_setting,settings[settings.size() - 2],back_button)
	focus_manager.set_neighbors(back_button,last_setting,ai_difficulty,start_button,start_button)
	focus_manager.set_neighbors(start_button,last_setting,ai_difficulty,back_button,back_button)



func _exit_tree() -> void:
	if InputManager.gamepad_disconnected.is_connected(
		_on_gamepad_disconnected
	):
		InputManager.gamepad_disconnected.disconnect(
			_on_gamepad_disconnected
	)


# ================================================================
# Configuration
# ================================================================
func _setup_settings() -> void:
	_setup_ai_difficulty()
	_setup_laps()
	_setup_tracks()
	_setup_game_types()
	_setup_screen_modes()
	_setup_tire_wear()
	_setup_target_scores()
	_apply_game_type_ui()


func _setup_tire_wear() -> void:
	tire_wear_selector.clear()

	tire_wear_selector.add_item("Non", 0)
	tire_wear_selector.add_item("Oui (arrêts au stand)", 1)

	tire_wear_selector.select(1 if race_config.tire_wear else 0)


func _setup_screen_modes() -> void:
	screen_mode_selector.clear()

	screen_mode_selector.add_item("Écran partagé", ScreenMode.SHARED)
	screen_mode_selector.add_item("Écran splitté", ScreenMode.SPLIT)

	screen_mode_selector.select(
		screen_mode_selector.get_item_index(
			ScreenMode.SPLIT if race_config.split_screen else ScreenMode.SHARED
		)
	)


func _setup_game_types() -> void:
	game_type_selector.clear()

	game_type_selector.add_item(
		"Course classique",
		RaceConfig.RaceRules.CLASSIC
	)
	game_type_selector.add_item(
		"Élimination hors écran",
		RaceConfig.RaceRules.ELIMINATION
	)

	game_type_selector.select(
		game_type_selector.get_item_index(race_config.race_rules)
	)


func _setup_target_scores() -> void:
	target_score_selector.clear()

	for score in TARGET_SCORES:
		target_score_selector.add_item("%d points" % score, score)

	var index := target_score_selector.get_item_index(
		race_config.target_score
	)

	if index < 0:
		index = target_score_selector.get_item_index(
			RaceConfig.DEFAULT_TARGET_SCORE
		)
		race_config.target_score = RaceConfig.DEFAULT_TARGET_SCORE

	target_score_selector.select(index)


## En élimination : pas d'IA et pas de limite de tours,
## mais un score à atteindre.
func _apply_game_type_ui() -> void:
	var elimination := race_config.is_elimination()

	target_score_row.visible = elimination
	# L'écran splitté ne concerne que la course classique.
	screen_mode_row.visible = not elimination
	# Usure des pneus : course classique uniquement.
	tire_wear_row.visible = not elimination
	ai_difficulty.disabled = elimination
	lap_selector.disabled = elimination

func _setup_settings_from_config() -> void:
	_setup_settings()

	var difficulty_index := race_config.ai_difficulty

	if difficulty_index >= 0 and difficulty_index < ai_difficulty.item_count:
		ai_difficulty.select(difficulty_index)


	var lap_index := lap_selector.get_item_index(
		race_config.lap_count
	)

	if lap_index >= 0:
		lap_selector.select(lap_index)

	track_selector.select(track_selector.get_item_index(race_config.track.id))

func _setup_ai_difficulty() -> void:
	ai_difficulty.clear()

	ai_difficulty.add_item("Novice", AIDifficulty.NOVICE)
	ai_difficulty.add_item("Moyen", AIDifficulty.MEDIUM)
	ai_difficulty.add_item("Expert", AIDifficulty.EXPERT)

	ai_difficulty.select(AIDifficulty.NOVICE)

	race_config.ai_difficulty = AIDifficulty.NOVICE


func _setup_laps() -> void:
	lap_selector.clear()

	var lap_counts := [
		1,
		2,
		3,
		4,
		5,
		7,
		10,
		15,
		20
	]

	for laps in lap_counts:
		lap_selector.add_item(str(laps), laps)

	# 3 tours
	lap_selector.select(2)

	race_config.lap_count = 3


func _setup_tracks() -> void:
	track_selector.clear()
	
	for track: Dictionary in track_catalog:
		track_selector.add_item(track.name, track.id)
	
	var first_track: Dictionary = track_catalog.get(0)
	track_selector.select(track_selector.get_item_index(first_track.id))

	race_config.track = first_track

# ================================================================
# Signaux
# ================================================================
func _connect_signals() -> void:
	back_button.pressed.connect(_on_back_pressed)
	start_button.pressed.connect(_on_start_pressed)

	ai_difficulty.item_selected.connect(
		_on_ai_difficulty_changed
	)

	track_selector.item_selected.connect(
		_on_track_changed
	)

	lap_selector.item_selected.connect(
		_on_laps_changed
	)

	game_type_selector.item_selected.connect(
		_on_game_type_changed
	)

	target_score_selector.item_selected.connect(
		_on_target_score_changed
	)

	screen_mode_selector.item_selected.connect(
		_on_screen_mode_changed
	)

	tire_wear_selector.item_selected.connect(
		_on_tire_wear_changed
	)

	# IMPORTANT :
	# Une connexion de manette ne fait PAS rejoindre automatiquement
	# un joueur.
	if not InputManager.gamepad_disconnected.is_connected(
		_on_gamepad_disconnected
	):
		InputManager.gamepad_disconnected.connect(
			_on_gamepad_disconnected
	)


# ================================================================
# JOIN
# ================================================================
func _unhandled_input(event: InputEvent) -> void:

	# ------------------------------------------------------------
	# Clavier
	# ------------------------------------------------------------
	if event is InputEventKey:
		if not event.pressed:
			return

		if event.echo:
			return

		if event.physical_keycode == KEYBOARD_JOIN_KEY:
			_try_join_keyboard()

		return


	# ------------------------------------------------------------
	# Manette
	# ------------------------------------------------------------
	if event is InputEventJoypadButton:
		if not event.pressed:
			return

		if event.button_index == GAMEPAD_JOIN_BUTTON:
			_try_join_gamepad(event.device)

		return


# ================================================================
# JOIN CLAVIER
# ================================================================
# Jusqu'à InputManager.KEYBOARD_PLAYER_COUNT joueurs partagent le clavier :
# chaque appui sur la touche de JOIN ajoute le joueur clavier suivant.
func _try_join_keyboard() -> void:

	if race_config.is_full():
		return

	var keyboard_id := race_config.get_free_keyboard_id()

	if keyboard_id < 0:
		return

	AudioManager.play_click()
	var player_id := race_config.get_next_player_id()

	var nickname : String

	if keyboard_id == 0:
		# Le clavier 1 correspond au profil principal.
		nickname = SaveManager.get_nickname()
	else:
		nickname = SaveManager.get_player_nickname(
			"keyboard",
			keyboard_id
		)

	if nickname.is_empty():
		nickname = "Joueur %d" % (
			race_config.get_human_player_count() + 1
		)

	var player := {
		"player_id": player_id,
		"device_type": "keyboard",
		"device_id": keyboard_id,
		"nickname": nickname
	}

	race_config.players.append(player)

	_refresh_ui()


# ================================================================
# JOIN MANETTE
# ================================================================
func _try_join_gamepad(device_id: int) -> void:

	if race_config.is_full():
		return

	# Une manette déjà inscrite ne peut pas rejoindre une seconde fois.
	if race_config.has_gamepad_player(device_id):
		return

	AudioManager.play_click()
	var player_id := race_config.get_next_player_id()

	var player_number := race_config.get_human_player_count() + 1

	var nickname : String = SaveManager.get_player_nickname(
		"gamepad",
		device_id
	)

	if nickname.is_empty():
		nickname = "Joueur %d" % player_number

	var player := {
		"player_id": player_id,
		"device_type": "gamepad",
		"device_id": device_id,
		"nickname": nickname
	}

	race_config.players.append(player)

	_refresh_ui()


# ================================================================
# REFRESH INTERFACE
# ================================================================
func _refresh_ui() -> void:
	_refresh_players()
	_refresh_start_button()
	_refresh_join_hint()
	set_focus()


func _refresh_players() -> void:

	for child in player_list.get_children():
		child.queue_free()


	for i in range(race_config.players.size()):

		var player: Dictionary = race_config.players[i]

		var slot: PlayerSlot = PLAYER_SLOT_SCENE.instantiate()

		player_list.add_child(slot)

		# i + 1 = numéro affiché.
		slot.setup(player, i + 1)

		slot.remove_requested.connect(
			_on_player_remove_requested
		)
		
		slot.nickname_changed.connect(
			_on_player_nickname_changed
		)


func _refresh_start_button() -> void:
	start_button.disabled = not race_config.is_valid()


func _refresh_join_hint() -> void:

	var human_count := race_config.get_human_player_count()
	var ai_count := race_config.get_ai_count()


	if human_count == 0:
		join_hint.text = ("Appuyer pour rejoindre (Touche E : clavier, 4 joueurs max / B : manette)")
		help_label.text = "Aucun joueur dans la partie"
		return


	if human_count >= MAX_HUMAN_PLAYERS:
		join_hint.text = "%d joueurs" % human_count
		help_label.text = "Le maximum de %d joueurs est atteint" % human_count
		return


	join_hint.text = "Appuyer pour rejoindre (Touche E : clavier, 4 joueurs max / B : manette)"

	if race_config.is_elimination():
		if human_count < RaceConfig.ELIMINATION_MIN_PLAYERS:
			help_label.text = "Élimination : %d joueurs minimum" % (
				RaceConfig.ELIMINATION_MIN_PLAYERS
			)
		else:
			help_label.text = "%d joueurs, sans IA" % human_count
		return

	help_label.text = ("%d joueurs / %d IA") % [
		human_count,
		ai_count
	]

	if race_config.split_screen and human_count < 2:
		help_label.text += " (écran splitté à partir de 2 joueurs)"


# ================================================================
# PARAMÈTRES
# ================================================================
func _on_ai_difficulty_changed(index: int) -> void:
	race_config.ai_difficulty = ai_difficulty.get_item_id(index)

	_refresh_start_button()


func _on_track_changed(index: int) -> void:
	race_config.track = track_catalog.get(index)

	_refresh_start_button()


func _on_laps_changed(index: int) -> void:
	race_config.lap_count = lap_selector.get_item_id(index)

	_refresh_start_button()


func _on_game_type_changed(index: int) -> void:
	race_config.race_rules = (
		game_type_selector.get_item_id(index)
		as RaceConfig.RaceRules
	)

	_apply_game_type_ui()
	_refresh_ui()


func _on_tire_wear_changed(index: int) -> void:
	race_config.tire_wear = tire_wear_selector.get_item_id(index) == 1


func _on_screen_mode_changed(index: int) -> void:
	race_config.split_screen = (
		screen_mode_selector.get_item_id(index) == ScreenMode.SPLIT
	)

	_refresh_join_hint()


func _on_target_score_changed(index: int) -> void:
	race_config.target_score = target_score_selector.get_item_id(index)

	_refresh_start_button()


func _on_player_nickname_changed(
	player_id: int,
	new_nickname: String
) -> void:

	for player in race_config.players:
		if int(player.get("player_id", -1)) != player_id:
			continue

		player["nickname"] = new_nickname

		var device_type := str(
			player.get("device_type", "")
		)

		var device_id := int(
			player.get("device_id", -1)
		)

		if (
			device_type == "keyboard"
			and InputManager.get_keyboard_index(device_id) == 0
		):
			# Le joueur clavier 1 correspond au profil principal.
			SaveManager.set_nickname(new_nickname)
		else:
			SaveManager.set_player_nickname(
				device_type,
				device_id,
				new_nickname
			)

		break

# ================================================================
# SUPPRESSION JOUEUR
# ================================================================
func _on_player_remove_requested(player_id: int) -> void:

	var player := race_config.get_player_by_id(player_id)

	if player.is_empty():
		return

	race_config.remove_player(player_id)

	_refresh_ui()


# ================================================================
# DÉCONNEXION MANETTE
# ================================================================
func _on_gamepad_disconnected(device_id: int) -> void:

	var player_id := -1

	for player in race_config.players:

		if str(player.get("device_type", "")) != "gamepad":
			continue

		if int(player.get("device_id", -1)) == device_id:
			player_id = int(player.get("player_id", -1))
			break

	if player_id < 0:
		return

	race_config.remove_player(player_id)

	_refresh_ui()


# ================================================================
# NAVIGATION
# ================================================================
func _on_back_pressed() -> void:
	NavigationManager.go_back_menu()


func _on_start_pressed() -> void:

	if not race_config.is_valid():
		return

	# On conserve une copie indépendante.
	#
	# RaceSetup ne choisit PAS les voitures.
	# CarSelection complètera cette configuration.
	GameManager.set_pending_race_config(
		race_config.duplicate_config()
	)

	NavigationManager.go(
		"CarSelection"
	)
