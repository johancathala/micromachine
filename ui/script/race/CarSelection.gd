extends Control


var race_config: RaceConfig
var selected_participant_index: int = -1

var cars: Array[CarDefinition] = []
var colors: Array = []

@onready var focus_manager: MenuFocusManager = $MenuFocusManager

@onready var back_button: Button = $MarginContainer/VBoxContainer/Footer/BackButton

@onready var participant_list: VBoxContainer = $MarginContainer/VBoxContainer/MainContent/ParticipantsPanel/ParticipantsMargin/ParticipantsVBox/ParticipantScroll/ParticipantList

@onready var selected_participant_label: Label = $MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/SelectedParticipant

@onready var car_grid: GridContainer = $MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/CarGridScroll/CarGrid

@onready var color_grid: GridContainer = $MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/ColorGrid

@onready var preview_image: TextureRect = $MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/PreviewPanel/PreviewVBox/PreviewImage

@onready var car_name_label: Label = $MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/PreviewPanel/PreviewVBox/CarName

@onready var car_description_label: Label = $MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/PreviewPanel/PreviewVBox/CarDescription

@onready var start_button: Button = $MarginContainer/VBoxContainer/Footer/StartButton

@onready var help_label: Label = $MarginContainer/VBoxContainer/Footer/HelpLabel

# ------------------------------------------------------------
# Barres de caractéristiques (relatives à la meilleure voiture
# du catalogue pour chaque caractéristique).
# ------------------------------------------------------------
const STATS := [
	{"name": "Vitesse", "color": Color("#4fc3f7")},
	{"name": "Accélération", "color": Color("#81c784")},
	{"name": "Freinage", "color": Color("#ef5350")},
	{"name": "Adhérence", "color": Color("#ffd54f")}
]

var _stat_bars: Array[ProgressBar] = []
var _stat_max: Array[float] = []

# ------------------------------------------------------------
# Sélection simultanée : un panneau par joueur humain (jusqu'à 8),
# chacun avec ses propres commandes.
# ------------------------------------------------------------
const MAX_SIMULTANEOUS_PLAYERS := 8
# Au-delà, panneaux sur 4 colonnes et liste de gauche masquée.
const COMPACT_FROM_PLAYERS := 5
# Délai avant le départ quand tout le monde est prêt.
const ALL_READY_DELAY := 0.8

var _pickers: Array[PlayerCarPicker] = []
var _all_ready_timer: SceneTreeTimer = null


func _ready() -> void:
	# Écran « Joueurs » : vient après l'écran des paramètres (RaceSetup).
	race_config = GameManager.get_pending_race_config()

	if race_config == null:
		race_config = RaceConfig.new()
		race_config.mode = GameManager.GameMode.SINGLE_RACE

	race_config.build_participants()

	cars = CarCatalog.get_cars()
	colors = ColorCatalog.get_colors()

	_setup_stat_bars()

	# Ancien affichage (liste + choix unique) remplacé par un panneau
	# par joueur.
	($MarginContainer/VBoxContainer/MainContent/ParticipantsPanel as Control).hide()
	($MarginContainer/VBoxContainer/MainContent/SelectionPanel as Control).hide()
	($MarginContainer/VBoxContainer/Header/Title as Label).text = "JOUEURS"
	start_button.text = "COMMENCER LA COURSE"

	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)

	if not InputManager.gamepad_disconnected.is_connected(_on_lobby_gamepad_disconnected):
		InputManager.gamepad_disconnected.connect(_on_lobby_gamepad_disconnected)

	AudioManager.bind_sound_btt()

	_rebuild_pickers()

	# Les touches des joueurs (flèches comprises) ne doivent pas
	# déplacer le focus des menus.
	get_viewport().gui_release_focus()


func _exit_tree() -> void:
	if InputManager.gamepad_disconnected.is_connected(_on_lobby_gamepad_disconnected):
		InputManager.gamepad_disconnected.disconnect(_on_lobby_gamepad_disconnected)


# ============================================================
# SÉLECTION SIMULTANÉE (1 à 4 joueurs)
# ============================================================

func _rebuild_pickers() -> void:
	for picker in _pickers:
		picker.queue_free()

	_pickers.clear()

	var main_content := $MarginContainer/VBoxContainer/MainContent
	var grid := main_content.get_node_or_null("PlayerPickers") as GridContainer

	if grid == null:
		grid = GridContainer.new()
		grid.name = "PlayerPickers"
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		main_content.add_child(grid)

	var human_indices: Array[int] = []

	for i in range(race_config.participants.size()):
		if not bool(race_config.participants[i].get("is_ai", false)):
			human_indices.append(i)

	var count := human_indices.size()
	grid.columns = 1 if count <= 1 else (2 if count < COMPACT_FROM_PLAYERS else 4)

	# Invitation à rejoindre tant que personne n'est là.
	var prompt := main_content.get_node_or_null("JoinPrompt") as Label

	if prompt == null:
		prompt = Label.new()
		prompt.name = "JoinPrompt"
		prompt.text = "Appuyez sur E (clavier) ou B (manette) pour rejoindre"
		prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prompt.size_flags_vertical = Control.SIZE_EXPAND_FILL
		prompt.add_theme_font_size_override("font_size", 40)
		main_content.add_child(prompt)

	prompt.visible = count == 0
	grid.visible = count > 0

	var player_number := 1

	for index in human_indices:
		_ensure_player_livery(index)

		var picker := PlayerCarPicker.new()
		grid.add_child(picker)
		picker.setup(index, player_number, race_config.participants[index], STATS)
		picker.car_step_requested.connect(_on_picker_car_step)
		picker.color_step_requested.connect(_on_picker_color_step)
		picker.ready_toggled.connect(_on_picker_ready_toggled)
		picker.remove_requested.connect(_on_picker_remove)
		picker.nickname_changed.connect(_on_picker_nickname)
		_pickers.append(picker)
		player_number += 1

	_refresh_pickers()


## Voiture et couleur par défaut d'un joueur qui rejoint (livrée libre).
func _ensure_player_livery(index: int) -> void:
	var participant := race_config.participants[index]

	if not participant.has("car_id"):
		participant["car_id"] = cars[0].id

	if not participant.has("color_id"):
		participant["color_id"] = colors[0]["id"]

	race_config.participants[index] = participant
	_ensure_unique_livery_vs_humans(index)
	_store_player_choice(index)


## Recopie le choix (voiture, couleur, pseudo) dans la fiche du joueur,
## qui fait foi quand les participants sont reconstruits.
func _store_player_choice(index: int) -> void:
	var participant := race_config.participants[index]
	var player_id := int(participant.get("player_id", -1))

	for i in range(race_config.players.size()):
		if int(race_config.players[i].get("player_id", -2)) == player_id:
			for key in ["car_id", "color_id", "nickname"]:
				if participant.has(key):
					race_config.players[i][key] = participant[key]


# ------------------------------------------------------------
# Rejoindre / quitter (E : clavier, B : manette)
# ------------------------------------------------------------

const KEYBOARD_JOIN_KEY := KEY_E
const GAMEPAD_JOIN_BUTTON := JOY_BUTTON_B


func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEYBOARD_JOIN_KEY:
			_join("keyboard", -1)

	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == GAMEPAD_JOIN_BUTTON and not race_config.has_gamepad_player(event.device):
			_join("gamepad", event.device)


func _max_players() -> int:
	return 1 if race_config.is_time_trial() else RaceConfig.MAX_HUMAN_PLAYERS


func _join(device_type: String, device_id: int) -> void:
	if race_config.players.size() >= _max_players():
		return

	if device_type == "keyboard":
		device_id = race_config.get_free_keyboard_id()

		if device_id < 0:
			return

	var nickname := ""

	if device_type == "keyboard" and device_id == 0:
		nickname = SaveManager.get_nickname()
	else:
		nickname = SaveManager.get_player_nickname(device_type, device_id)

	if nickname.is_empty():
		nickname = "Joueur %d" % (race_config.players.size() + 1)

	race_config.players.append({
		"player_id": race_config.get_next_player_id(),
		"device_type": device_type,
		"device_id": device_id,
		"nickname": nickname
	})

	race_config.build_participants()
	AudioManager.play_click()
	_rebuild_pickers()


func _on_picker_remove(picker: PlayerCarPicker) -> void:
	var participant := race_config.participants[picker.participant_index]
	race_config.remove_player(int(participant.get("player_id", -1)))
	race_config.build_participants()
	_rebuild_pickers()


func _on_lobby_gamepad_disconnected(device_id: int) -> void:
	for player in race_config.players:
		if String(player.get("device_type", "")) == "gamepad" and int(player.get("device_id", -1)) == device_id:
			race_config.remove_player(int(player.get("player_id", -1)))
			race_config.build_participants()
			_rebuild_pickers()
			return


func _on_picker_nickname(picker: PlayerCarPicker, nickname: String) -> void:
	var participant := race_config.participants[picker.participant_index]
	participant["nickname"] = nickname
	race_config.participants[picker.participant_index] = participant
	_store_player_choice(picker.participant_index)

	var device_type := String(participant.get("device_type", ""))
	var device_id := int(participant.get("device_id", -1))

	if device_type == "keyboard" and InputManager.get_keyboard_index(device_id) == 0:
		SaveManager.set_nickname(nickname)
	else:
		SaveManager.set_player_nickname(device_type, device_id, nickname)


func _refresh_pickers() -> void:
	for picker in _pickers:
		var participant := race_config.participants[picker.participant_index]
		var car := CarCatalog.get_car(String(participant.get("car_id", "")))
		var color_data := ColorCatalog.get_color(String(participant.get("color_id", "")))
		var ratios: Array = []

		if car != null:
			var values := get_car_stats(car)

			for i in range(values.size()):
				ratios.append(values[i] / _stat_max[i] if _stat_max[i] > 0.0 else 0.0)

		picker.refresh(car, color_data, ratios)
		_store_player_choice(picker.participant_index)

	_refresh_start_button()
	_refresh_lobby_help()


func _on_picker_car_step(picker: PlayerCarPicker, direction: int) -> void:
	var participant := race_config.participants[picker.participant_index]
	var current := _car_index(String(participant.get("car_id", "")))

	# Voiture suivante qui a encore une couleur libre pour ce joueur.
	for step in range(1, cars.size() + 1):
		var car_id: String = cars[posmod(current + direction * step, cars.size())].id
		participant["car_id"] = car_id
		race_config.participants[picker.participant_index] = participant

		if _human_livery_available(picker.participant_index):
			break

	_ensure_unique_livery_vs_humans(picker.participant_index)
	_resolve_ai_liveries()
	AudioManager.play_click()
	_refresh_pickers()


func _on_picker_color_step(picker: PlayerCarPicker, direction: int) -> void:
	var participant := race_config.participants[picker.participant_index]
	var car_id := String(participant.get("car_id", ""))
	var ids := _get_color_ids()
	var current := ids.find(String(participant.get("color_id", "")))

	# Couleur suivante non prise par un autre joueur humain.
	for step in range(1, ids.size() + 1):
		var color_id: String = ids[posmod(current + direction * step, ids.size())]

		if not _taken_by_other_human(car_id, color_id, picker.participant_index):
			participant["color_id"] = color_id
			break

	race_config.participants[picker.participant_index] = participant
	_resolve_ai_liveries()
	AudioManager.play_click()
	_refresh_pickers()


func _on_picker_ready_toggled(picker: PlayerCarPicker) -> void:
	picker.is_ready = not picker.is_ready
	AudioManager.play_click()
	_refresh_pickers()

	for other in _pickers:
		if not other.is_ready:
			return

	# Tout le monde est prêt : départ après un court délai, annulé si
	# quelqu'un repasse « pas prêt » entre-temps.
	if not _can_start():
		return

	_all_ready_timer = get_tree().create_timer(ALL_READY_DELAY)
	var timer := _all_ready_timer
	await timer.timeout

	if timer != _all_ready_timer or not _can_start():
		return

	_on_start_pressed()


func _car_index(car_id: String) -> int:
	for i in range(cars.size()):
		if cars[i].id == car_id:
			return i

	return 0


func _is_human(index: int) -> bool:
	return not bool(race_config.participants[index].get("is_ai", false))


## Couleur prise, pour ce modèle, par un AUTRE joueur humain
## (les IA s'écartent d'elles-mêmes).
func _taken_by_other_human(car_id: String, color_id: String, index: int) -> bool:
	if not race_config.requires_unique_liveries():
		return false

	for i in range(race_config.participants.size()):
		if i == index or not _is_human(i):
			continue

		var other := race_config.participants[i]

		if String(other.get("car_id", "")) == car_id and String(other.get("color_id", "")) == color_id:
			return true

	return false


func _human_livery_available(index: int) -> bool:
	var car_id := String(race_config.participants[index].get("car_id", ""))

	for color_id in _get_color_ids():
		if not _taken_by_other_human(car_id, color_id, index):
			return true

	return false


func _ensure_unique_livery_vs_humans(index: int) -> void:
	var participant := race_config.participants[index]
	var car_id := String(participant.get("car_id", ""))

	if not _taken_by_other_human(car_id, String(participant.get("color_id", "")), index):
		return

	for color_id in _get_color_ids():
		if not _taken_by_other_human(car_id, color_id, index):
			participant["color_id"] = color_id
			race_config.participants[index] = participant
			return


## Les IA cèdent leur livrée aux joueurs : une IA en conflit reçoit
## une couleur libre (ou un autre modèle si toutes sont prises).
func _resolve_ai_liveries() -> void:
	if not race_config.requires_unique_liveries():
		return

	for i in range(race_config.participants.size()):
		if _is_human(i):
			continue

		var participant := race_config.participants[i]

		if not bool(participant.get("enabled", true)):
			continue

		if not race_config.is_livery_taken(
			String(participant.get("car_id", "")),
			String(participant.get("color_id", "")),
			i
		):
			continue

		# Son modèle d'abord, puis les autres.
		var candidates: Array = [CarCatalog.get_car(String(participant.get("car_id", "")))]
		candidates.append_array(cars)

		for car in candidates:
			if car == null:
				continue

			var free := race_config.find_free_color(car.id, i, _get_color_ids())

			if not free.is_empty():
				participant["car_id"] = car.id
				participant["color_id"] = free
				race_config.participants[i] = participant
				break


func _setup_participant_defaults() -> void:
	for i in range(race_config.participants.size()):
		var participant := race_config.participants[i]

		if String(participant.get("car_id", "")).is_empty():
			if not cars.is_empty():
				participant["car_id"] = cars[0].id

		if String(participant.get("color_id", "")).is_empty():
			participant["color_id"] = colors[0]["id"]

		race_config.participants[i] = participant

	# Écran commun : chaque participant reçoit une livrée distincte.
	for i in range(race_config.participants.size()):
		_ensure_unique_livery(i)


## Si la livrée (modèle + couleur) du participant est déjà prise,
## lui attribue la première couleur libre pour ce modèle.
func _ensure_unique_livery(index: int) -> void:
	if not race_config.requires_unique_liveries():
		return

	var participant := race_config.participants[index]

	if not bool(participant.get("enabled", true)):
		return

	var car_id := String(participant.get("car_id", ""))

	if not race_config.is_livery_taken(
		car_id,
		String(participant.get("color_id", "")),
		index
	):
		return

	var free_color := race_config.find_free_color(
		car_id,
		index,
		_get_color_ids()
	)

	if not free_color.is_empty():
		participant["color_id"] = free_color
		race_config.participants[index] = participant


func _get_color_ids() -> Array:
	var ids: Array = []

	for color_data in colors:
		ids.append(String(color_data["id"]))

	return ids


func _refresh_start_button() -> void:
	start_button.disabled = not _can_start()


## Prêt à partir : nombre de joueurs conforme au mode, tous prêts.
func _can_start() -> bool:
	if not race_config.is_valid():
		return false

	for picker in _pickers:
		if not picker.is_ready:
			return false

	return not _pickers.is_empty()


func _refresh_lobby_help() -> void:
	var count := race_config.players.size()
	var text := "E : rejoindre au clavier · B : à la manette"

	if race_config.is_time_trial():
		text = "Contre-la-montre : un seul joueur" if count != 1 else "Seul contre votre fantôme"
	elif race_config.is_elimination() and count < RaceConfig.ELIMINATION_MIN_PLAYERS:
		text += " — élimination : %d joueurs minimum" % RaceConfig.ELIMINATION_MIN_PLAYERS
	elif count > 0:
		text += " — tout le monde « prêt » pour partir"

	help_label.text = text


func _setup_car_grid() -> void:
	for child in car_grid.get_children():
		child.queue_free()

	for car: CarDefinition in cars:
		var button := Button.new()

		button.text = car.display_name
		button.set_meta("car_id", car.id)

		button.custom_minimum_size = Vector2(150, 60)
		button.focus_mode = Control.FOCUS_ALL

		button.pressed.connect(
			_on_car_selected.bind(car.id, car.display_name)
		)

		car_grid.add_child(button)


func _setup_color_grid() -> void:
	for child in color_grid.get_children():
		child.queue_free()

	for color_data: Dictionary in colors:
		var button := Button.new()

		button.text = color_data["name"]
		button.custom_minimum_size = Vector2(110, 50)
		button.focus_mode = Control.FOCUS_ALL

		_apply_color_button_style(
			button,
			color_data["color"]
		)

		button.pressed.connect(
			_on_color_selected.bind(color_data["id"])
		)

		color_grid.add_child(button)


func _apply_color_button_style(
	button: Button,
	color: Color
) -> void:

	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6

	button.add_theme_stylebox_override(
		"normal",
		normal
	)

	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.12)

	button.add_theme_stylebox_override(
		"hover",
		hover
	)

	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.12)

	button.add_theme_stylebox_override(
		"pressed",
		pressed
	)


func _refresh_participant_list() -> void:
	for child in participant_list.get_children():
		child.queue_free()

	for i in range(race_config.participants.size()):
		var participant := race_config.participants[i]

		var is_ai: bool = bool(
			participant.get("is_ai", false)
		)

		var enabled: bool = bool(
			participant.get("enabled", true)
		)

		var hbox := HBoxContainer.new()

		var select_button := Button.new()

		select_button.text = _get_participant_display_text(
			participant,
			i
		)

		select_button.custom_minimum_size = Vector2(0, 60)
		select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select_button.focus_mode = Control.FOCUS_ALL

		# Une IA désactivée reste visible mais ne peut pas
		# être sélectionnée pour modifier sa voiture/couleur.
		select_button.disabled = is_ai and not enabled

		select_button.pressed.connect(
			_select_participant.bind(i)
		)

		hbox.add_child(select_button)

		if is_ai:
			var toggle_button := Button.new()

			toggle_button.text = (
				"Désactiver"
				if enabled
				else "Activer"
			)

			toggle_button.custom_minimum_size = Vector2(110, 60)
			toggle_button.focus_mode = Control.FOCUS_ALL

			toggle_button.pressed.connect(
				_on_toggle_pressed.bind(i)
			)
			
			toggle_button.add_to_group("audio_back")

			hbox.add_child(toggle_button)

			# Aspect visuel d'une IA désactivée.
			if not enabled:
				select_button.modulate = Color(
					0.55,
					0.55,
					0.55,
					1.0
				)

		participant_list.add_child(hbox)


func _get_participant_display_text(
	participant: Dictionary,
	index: int
) -> String:

	var nickname := String(
		participant.get(
			"nickname",
			"Participant %d" % (index + 1)
		)
	)

	var car_id := String(
		participant.get("car_id", "")
	)

	var color_id := String(
		participant.get("color_id", "")
	)

	var car := CarCatalog.get_car(car_id)
	var color := ColorCatalog.get_color(color_id)

	var car_name := "?"
	if car != null:
		car_name = car.display_name

	var color_name := "?"
	if not color.is_empty():
		color_name = color["name"]

	var ai_text := ""

	if bool(participant.get("is_ai", false)):
		ai_text = " [IA]"

	return "%d. %s%s — %s / %s" % [
		index + 1,
		nickname,
		ai_text,
		car_name,
		color_name
	]


func _select_participant(index: int) -> void:
	if index < 0 or index >= race_config.participants.size():
		return

	selected_participant_index = index

	var participant := race_config.participants[index]

	selected_participant_label.text = String(
		participant.get(
			"nickname",
			"Participant %d" % (index + 1)
		)
	)

	_refresh_car_buttons()
	_refresh_color_buttons()
	_refresh_preview()

func _on_toggle_pressed(index: int) -> void:
	if index < 0 or index >= race_config.participants.size():
		return

	var participant := race_config.participants[index]

	if not bool(participant.get("is_ai", false)):
		return

	var enabled := bool(
		participant.get("enabled", true)
	)

	participant["enabled"] = not enabled

	race_config.participants[index] = participant

	# Une IA réactivée ne doit pas reprendre une livrée déjà utilisée.
	_ensure_unique_livery(index)

	_refresh_participant_list()

	_refresh_car_buttons()
	_refresh_color_buttons()
	_refresh_preview()
	_refresh_start_button()
	focus_manager.set_focus(back_button)

func _refresh_car_buttons() -> void:
	if selected_participant_index < 0:
		return

	var participant := race_config.participants[
		selected_participant_index
	]

	var selected_car_id := String(
		participant.get("car_id", "")
	)

	for child in car_grid.get_children():
		var button := child as Button

		if button == null:
			continue

		var car_id := String(
			button.get_meta("car_id", "")
		)

		var car := CarCatalog.get_car(car_id)

		if car == null:
			continue

		button.text = (
			"✓ " + car.display_name
			if car.id == selected_car_id
			else car.display_name
		)


func _find_car_by_display_name(
	display_name: String
) -> CarDefinition:

	for car: CarDefinition in cars:
		if car.display_name == display_name:
			return car

	return null


func _refresh_color_buttons() -> void:
	if selected_participant_index < 0:
		return

	var participant := race_config.participants[
		selected_participant_index
	]

	var selected_color_id := String(
		participant.get("color_id", "")
	)

	var car_id := String(participant.get("car_id", ""))

	for i in range(color_grid.get_child_count()):
		var button := color_grid.get_child(i) as Button

		if button == null:
			continue

		var color_data: Dictionary = colors[i]

		var color_id := String(
			color_data["id"]
		)

		var prefix := "✓ " if color_id == selected_color_id else ""

		# Écran commun : couleur déjà prise pour ce modèle.
		var taken: bool = (
			race_config.requires_unique_liveries()
			and race_config.is_livery_taken(
				car_id,
				color_id,
				selected_participant_index
			)
		)

		button.disabled = taken

		button.text = prefix + String(
			color_data["name"]
		) + (" (prise)" if taken else "")


func _on_car_selected(car_id: String, car_name: String) -> void:
	if selected_participant_index < 0:
		return

	race_config.participants[
		selected_participant_index
	]["car_id"] = car_id
	
	race_config.participants[
		selected_participant_index
	]["car_name"] = car_name

	# Nouveau modèle : la couleur actuelle peut y être déjà prise.
	_ensure_unique_livery(selected_participant_index)

	_refresh_participant_list()
	_refresh_car_buttons()
	_refresh_color_buttons()
	_refresh_preview()
	_refresh_start_button()


func _on_color_selected(color_id: String) -> void:
	if selected_participant_index < 0:
		return

	var car_id := String(
		race_config.participants[selected_participant_index].get("car_id", "")
	)

	if (
		race_config.requires_unique_liveries()
		and race_config.is_livery_taken(
			car_id,
			color_id,
			selected_participant_index
		)
	):
		return

	race_config.participants[
		selected_participant_index
	]["color_id"] = color_id

	_refresh_participant_list()
	_refresh_color_buttons()
	_refresh_preview()
	_refresh_start_button()


## Valeurs brutes des caractéristiques d'une voiture, dans l'ordre STATS.
static func get_car_stats(car: CarDefinition) -> Array[float]:
	return [
		car.max_speed,
		car.engine_force,
		car.brake_force,
		# Adhérence : de base et à haute vitesse (qui compte double).
		car.lateral_grip + 2.0 * car.lateral_grip_at_high_speed
	]


func _setup_stat_bars() -> void:
	_stat_max.clear()

	for i in range(STATS.size()):
		_stat_max.append(0.0)

	for car in cars:
		var values := get_car_stats(car)

		for i in range(values.size()):
			_stat_max[i] = maxf(_stat_max[i], values[i])

	var grid := GridContainer.new()
	grid.name = "StatBars"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)

	# Sous la description, dans le panneau d'aperçu.
	var preview_box := car_description_label.get_parent()
	preview_box.add_child(grid)
	preview_box.move_child(grid, car_description_label.get_index() + 1)

	_stat_bars.clear()

	for stat in STATS:
		var label := Label.new()
		label.text = stat["name"]
		label.add_theme_font_size_override("font_size", 22)
		grid.add_child(label)

		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(260, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var background := StyleBoxFlat.new()
		background.bg_color = Color(0, 0, 0, 0.45)
		background.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("background", background)

		var fill := StyleBoxFlat.new()
		fill.bg_color = stat["color"]
		fill.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("fill", fill)

		grid.add_child(bar)
		_stat_bars.append(bar)


func _refresh_stat_bars(car: CarDefinition) -> void:
	if car == null:
		for bar in _stat_bars:
			bar.value = 0.0
		return

	var values := get_car_stats(car)

	for i in range(_stat_bars.size()):
		# 10 % minimum pour que la barre reste visible.
		var ratio := values[i] / _stat_max[i] if _stat_max[i] > 0.0 else 0.0
		_stat_bars[i].value = clampf(ratio, 0.1, 1.0) * 100.0


func _refresh_preview() -> void:
	if selected_participant_index < 0:
		return

	var participant := race_config.participants[
		selected_participant_index
	]

	var car := CarCatalog.get_car(
		String(participant.get("car_id", ""))
	)

	_refresh_stat_bars(car)

	if car == null:
		car_name_label.text = "Voiture inconnue"
		car_description_label.text = ""
		preview_image.texture = null
		return

	car_name_label.text = car.display_name
	car_description_label.text = car.description

	preview_image.texture = car.preview_texture

	var color_data := ColorCatalog.get_color(
		String(participant.get("color_id", ""))
	)

	if not color_data.is_empty():
		preview_image.modulate = color_data["color"]
		#preview_image.modulate = Color.WHITE
	else:
		preview_image.modulate = Color.WHITE


func _on_start_pressed() -> void:
	if not _can_start():
		return

	# IA engagées selon les paramètres (course classique), livrées
	# distinctes de celles des joueurs.
	race_config.build_participants()
	race_config.enable_ai(_get_color_ids())

	if not race_config.is_car_selection_valid():
		return

	GameManager.set_pending_race_config(race_config)

	if not GameManager.start_race():
		return

	AudioManager.play_start_event()
	await get_tree().create_timer(1.0).timeout
	NavigationManager.go("Race", true, true)


func _on_back_pressed() -> void:
	# Retour aux paramètres en gardant les joueurs et leurs voitures.
	GameManager.set_pending_race_config(race_config.duplicate_config())
	NavigationManager.go_back()
