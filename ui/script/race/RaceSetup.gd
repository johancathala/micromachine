extends Control

const PLAYER_SLOT_SCENE := preload("res://ui/scene/PlayerSlot.tscn")
const CAR_SELECTION_SCENE := "res://ui/scene/CarSelection.tscn"

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

# Une seule personne peut utiliser le clavier.
var keyboard_player_joined := false


@onready var back_button: Button = (
	$MarginContainer/VBoxContainer/Footer/BackButton
)

@onready var player_list: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainContent/PlayersPanel/PlayersMargin/PlayersVBox/PlayerListScroll/PlayerList
)

@onready var join_hint: Label = (
	$MarginContainer/VBoxContainer/MainContent/PlayersPanel/PlayersMargin/PlayersVBox/JoinHint
)

@onready var ai_difficulty: OptionButton = (
	$MarginContainer/VBoxContainer/MainContent/SettingsPanel/SettingsMargin/SettingsVBox/AIDifficultyRow/AIDifficulty
)

@onready var track_selector: OptionButton = (
	$MarginContainer/VBoxContainer/MainContent/SettingsPanel/SettingsMargin/SettingsVBox/TrackRow/Track
)

@onready var lap_selector: OptionButton = (
	$MarginContainer/VBoxContainer/MainContent/SettingsPanel/SettingsMargin/SettingsVBox/LapCountRow/LapCount
)

@onready var start_button: Button = (
	$MarginContainer/VBoxContainer/Footer/StartButton
)

@onready var help_label: Label = (
	$MarginContainer/VBoxContainer/Footer/HelpLabel
)

func _ready() -> void:

	race_config = GameManager.get_pending_race_config()

	if race_config == null:
		race_config = RaceConfig.new()
		race_config.mode = GameManager.GameMode.SINGLE_RACE

		_setup_settings()
	else:
		# Les paramètres existent déjà.
		# On reconstruit simplement les OptionButtons
		# à partir de la configuration.
		_setup_settings_from_config()


	_connect_signals()
	_refresh_ui()

	back_button.grab_focus()


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


	var track_index := _get_track_index(
		race_config.track_id
	)

	if track_index >= 0:
		track_selector.select(track_index)

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

	track_selector.add_item("Classique", 0)
	track_selector.add_item("Padock 1", 1)
	track_selector.add_item("Padock 2", 2)
	track_selector.add_item("Reverse", 3)

	track_selector.select(0)

	race_config.track_id = "track_01"

func _get_track_index(track_id: String) -> int:
	match track_id:
		"track_01":
			return 0

		"track_02":
			return 1

		"track_03":
			return 2

		"track_reverse":
			return 3

	return -1

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

func _try_join_keyboard() -> void:

	if keyboard_player_joined:
		return

	if race_config.is_full():
		return

	if race_config.has_keyboard_player():
		keyboard_player_joined = true
		return


	var player_id := race_config.get_next_player_id()

	var nickname : String = SaveManager.get_nickname()

	if nickname.is_empty():
		nickname = "Joueur 1"


	var player := {
		"player_id": player_id,
		"device_type": "keyboard",
		"device_id": -1,
		"nickname": nickname
	}

	race_config.players.append(player)

	keyboard_player_joined = true

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
		join_hint.text = ("Appuyer pour rejoindre (Touche E : clavier / B : manette)")
		help_label.text = "Aucun joueur dans la partie"
		return


	if human_count >= MAX_HUMAN_PLAYERS:
		join_hint.text = "%d joueurs" % human_count
		help_label.text = "Le maximum de %d joueurs est atteint" % human_count
		return


	join_hint.text = "Appuyer pour rejoindre (Touche E : clavier / B : manette)"
	help_label.text = ("%d joueurs / %d IA") % [
		human_count,
		ai_count
	]


# ================================================================
# PARAMÈTRES
# ================================================================

func _on_ai_difficulty_changed(index: int) -> void:
	race_config.ai_difficulty = ai_difficulty.get_item_id(index)

	_refresh_start_button()


func _on_track_changed(index: int) -> void:
	race_config.track_id = _get_track_id(index)

	_refresh_start_button()


func _on_laps_changed(index: int) -> void:
	race_config.lap_count = lap_selector.get_item_id(index)

	_refresh_start_button()


func _get_track_id(index: int) -> String:
	match index:
		0:
			return "track_01"

		1:
			return "track_02"

		2:
			return "track_03"

		3:
			return "track_reverse"

	return ""

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

		if device_type == "keyboard":
			# Le joueur clavier correspond au profil principal.
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


	if str(player.get("device_type", "")) == "keyboard":
		keyboard_player_joined = false


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
	NavigationManager.go_back()


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

	NavigationManager.go_to(
		CAR_SELECTION_SCENE
	)
