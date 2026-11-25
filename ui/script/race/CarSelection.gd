extends Control


var race_config: RaceConfig

var cars: Array[CarDefinition] = []
var colors: Array = []

@onready var back_button: Button = $MarginContainer/VBoxContainer/Footer/BackButton

@onready var start_button: Button = $MarginContainer/VBoxContainer/Footer/StartButton

@onready var help_label: Label = $MarginContainer/VBoxContainer/Footer/HelpLabel

const STATS := [
	{"name": "Vitesse", "color": Color("#4fc3f7")},
	{"name": "Accélération", "color": Color("#81c784")},
	{"name": "Freinage", "color": Color("#ef5350")},
	{"name": "Adhérence", "color": Color("#ffd54f")}
]

var _stat_max: Array[float] = []

# ------------------------------------------------------------
# Sélection simultanée : un panneau par joueur humain, chacun avec ses
# propres commandes.
# ------------------------------------------------------------
# À partir de cinq joueurs, disposition compacte en quatre colonnes.
const COMPACT_FROM_PLAYERS := 5
# Délai avant le départ quand tout le monde est prêt.
const ALL_READY_DELAY := 0.8

var _pickers: Array[PlayerCarPicker] = []
var _all_ready_timer: SceneTreeTimer = null


func _ready() -> void:
	# Écran « Joueurs » : après le mode de jeu (RaceModeSelect), avant
	# les IA (course classique) ou directement le circuit (RaceSetup).
	race_config = GameManager.get_pending_race_config()

	if race_config == null:
		race_config = RaceConfig.new()
		race_config.mode = GameManager.GameMode.SINGLE_RACE

	race_config.build_participants()

	cars = CarCatalog.get_cars()
	colors = ColorCatalog.get_colors()

	_setup_stat_maxima()
	start_button.text = "IA ›" if race_config.allows_ai() else "CIRCUIT ›"

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
# SÉLECTION SIMULTANÉE (1 à 8 joueurs)
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
## Un ancien choix verrouillé est conservé tel quel : le joueur le voit,
## mais ne peut pas valider tant qu'il ne choisit pas une voiture
## débloquée.
func _ensure_player_livery(index: int) -> void:
	var participant := race_config.participants[index]

	if not participant.has("car_id") or not CarCatalog.has_car(String(participant["car_id"])):
		participant["car_id"] = _default_car_id()

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
		var car_id := String(participant.get("car_id", ""))
		var car := CarCatalog.get_car(car_id)
		var color_data := ColorCatalog.get_color(String(participant.get("color_id", "")))
		var locked := not _is_car_selectable(car_id)
		var ratios: Array = []

		if car != null:
			var values := get_car_stats(car)

			for i in range(values.size()):
				ratios.append(values[i] / _stat_max[i] if _stat_max[i] > 0.0 else 0.0)

		# Une voiture verrouillée ne peut pas être validée.
		if locked:
			picker.is_ready = false

		picker.refresh(car, color_data, ratios, locked)
		_store_player_choice(picker.participant_index)

	_refresh_start_button()
	_refresh_lobby_help()


## Vrai si la voiture est débloquée : seule une voiture débloquée peut
## être validée (les autres restent consultables).
func _is_car_selectable(car_id: String) -> bool:
	return CarCatalog.has_car(car_id) and SaveManager.is_car_unlocked(car_id)


## Vrai si la voiture du joueur est validable (débloquée).
func _picker_car_selectable(picker: PlayerCarPicker) -> bool:
	return _is_car_selectable(
		String(race_config.participants[picker.participant_index].get("car_id", ""))
	)


func _default_car_id() -> String:
	var unlocked := SaveManager.get_unlocked_cars()

	if not unlocked.is_empty():
		return unlocked[0].id

	return cars[0].id if not cars.is_empty() else ""


## Toutes les voitures sont consultables (y compris celles à débloquer) :
## une voiture verrouillée s'affiche en silhouette et empêche de valider.
func _on_picker_car_step(picker: PlayerCarPicker, direction: int) -> void:
	var participant := race_config.participants[picker.participant_index]
	var current := _car_index(String(participant.get("car_id", "")))

	# Voiture suivante qui a encore une couleur libre pour ce joueur.
	for step in range(1, cars.size() + 1):
		var car := cars[posmod(current + direction * step, cars.size())]
		participant["car_id"] = car.id
		race_config.participants[picker.participant_index] = participant

		if _human_livery_available(picker.participant_index):
			break

	_ensure_unique_livery_vs_humans(picker.participant_index)
	_resolve_ai_liveries()
	AudioManager.play_click()
	_refresh_pickers()


func _on_picker_color_step(picker: PlayerCarPicker, direction: int) -> void:
	# Une voiture verrouillée n'a pas de livrée à choisir.
	if not _picker_car_selectable(picker):
		return

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
	# Voiture verrouillée : impossible de se déclarer prêt.
	if not _picker_car_selectable(picker):
		picker.is_ready = false
		_refresh_pickers()
		return

	picker.is_ready = not picker.is_ready
	AudioManager.play_click()
	_refresh_pickers()

	for other in _pickers:
		if not other.is_ready:
			return

	# Tout le monde est prêt : écran suivant après un court délai, annulé si
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


func _get_color_ids() -> Array:
	var ids: Array = []

	for color_data in colors:
		ids.append(String(color_data["id"]))

	return ids


## Valeurs brutes des caractéristiques d'une voiture, dans l'ordre STATS.
static func get_car_stats(car: CarDefinition) -> Array[float]:
	return [
		car.max_speed,
		car.engine_force,
		car.brake_force,
		car.lateral_grip + 2.0 * car.lateral_grip_at_high_speed
	]


func _setup_stat_maxima() -> void:
	_stat_max.clear()

	for i in range(STATS.size()):
		_stat_max.append(0.0)

	for car in cars:
		var values := get_car_stats(car)

		for i in range(values.size()):
			_stat_max[i] = maxf(_stat_max[i], values[i])


func _refresh_start_button() -> void:
	start_button.disabled = not _can_start()


## Prêt à partir : nombre de joueurs conforme au mode, tous prêts.
func _can_start() -> bool:
	# Le circuit est choisi plus tard : seuls les joueurs comptent ici.
	if not race_config.are_players_valid():
		return false

	for picker in _pickers:
		# Une voiture verrouillée invalide la sélection, même prête.
		if not picker.is_ready or not _picker_car_selectable(picker):
			return false

	return not _pickers.is_empty()


func _refresh_lobby_help() -> void:
	var count := race_config.players.size()
	var text := "E : rejoindre au clavier · B : à la manette"

	for picker in _pickers:
		if not _picker_car_selectable(picker):
			help_label.text = "Voiture verrouillée : ◀ ▶ pour choisir une voiture débloquée"
			return

	if race_config.is_time_trial():
		text = "Contre-la-montre : un seul joueur" if count != 1 else "Seul contre votre fantôme"
	elif race_config.is_elimination() and count == 1:
		text += " — élimination : ajoutez des IA à l'écran suivant"
	elif count > 0:
		text += " — tout le monde « prêt » pour continuer"

	help_label.text = text


func _on_start_pressed() -> void:
	if not _can_start():
		return

	race_config.build_participants()
	GameManager.set_pending_race_config(race_config.duplicate_config())
	# IA (course classique), puis circuit et réglages.
	NavigationManager.go("AISetup" if race_config.allows_ai() else "RaceSetup")


func _on_back_pressed() -> void:
	# Retour au mode de jeu en gardant les joueurs et leurs voitures.
	GameManager.set_pending_race_config(race_config.duplicate_config())
	NavigationManager.go("RaceModeSelect")
