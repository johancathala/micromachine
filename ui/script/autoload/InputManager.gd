extends Node

const PlayerInputStateClass = preload(
	"res://input/PlayerInputState.gd"
)

signal gamepad_connected(device_id: int)
signal gamepad_disconnected(device_id: int)


# Touches PHYSIQUES (position sur le clavier, indépendante de la disposition).
# Les commentaires donnent l'équivalent AZERTY.
# La réapparition est placée près des touches de chaque joueur.
#
# Un binding clavier est un entier : physical_keycode, auquel s'ajoute
# éventuellement le côté de la touche (KeyLocation) décalé de
# KEY_LOCATION_SHIFT bits. Cela permet de distinguer Ctrl gauche et
# Ctrl droit (même physical_keycode pour Godot).
const KEY_LOCATION_SHIFT := 28
const KEY_BINDING_CODE_MASK := (1 << KEY_LOCATION_SHIFT) - 1

const KEY_CTRL_LEFT := KEY_CTRL | (KEY_LOCATION_LEFT << KEY_LOCATION_SHIFT)
const KEY_CTRL_RIGHT := KEY_CTRL | (KEY_LOCATION_RIGHT << KEY_LOCATION_SHIFT)

# Joueur clavier 1 : Z Q S D, frein à main Ctrl gauche, réapparition R.
# Pause et confirmation sont communes et portées par le clavier 1.
const DEFAULT_KEY_BINDINGS := {
	"accelerate": KEY_W,
	"brake": KEY_S,
	"left": KEY_A,
	"right": KEY_D,
	"handbrake": KEY_CTRL_LEFT,
	"respawn": KEY_R,
	"pause": KEY_ESCAPE,
	"confirm": KEY_ENTER
}

# Joueur clavier 2 : O K L M, frein à main U, réapparition P.
const DEFAULT_KEY_BINDINGS_P2 := {
	"accelerate": KEY_O,
	"brake": KEY_L,
	"left": KEY_K,
	"right": KEY_SEMICOLON,
	"handbrake": KEY_U,
	"respawn": KEY_P
}

# Joueur clavier 3 : flèches, frein à main Ctrl droit, réapparition Page suiv.
const DEFAULT_KEY_BINDINGS_P3 := {
	"accelerate": KEY_UP,
	"brake": KEY_DOWN,
	"left": KEY_LEFT,
	"right": KEY_RIGHT,
	"handbrake": KEY_CTRL_RIGHT,
	"respawn": KEY_PAGEDOWN
}

# Joueur clavier 4 : pavé numérique 8 4 5 6, frein à main 0, réapparition -.
const DEFAULT_KEY_BINDINGS_P4 := {
	"accelerate": KEY_KP_8,
	"brake": KEY_KP_5,
	"left": KEY_KP_4,
	"right": KEY_KP_6,
	"handbrake": KEY_KP_0,
	"respawn": KEY_KP_SUBTRACT
}

const KEYBOARD_DEFAULTS := [
	DEFAULT_KEY_BINDINGS,
	DEFAULT_KEY_BINDINGS_P2,
	DEFAULT_KEY_BINDINGS_P3,
	DEFAULT_KEY_BINDINGS_P4
]


# Nombre de joueurs pouvant partager le clavier.
# device_id clavier : 0..3 = clavier 1..4
# (-1 est accepté comme clavier 1 pour compatibilité).
const KEYBOARD_PLAYER_COUNT := 4


const DEFAULT_GAMEPAD_BINDINGS := {
	"accelerate": JOY_BUTTON_A,
	"brake": JOY_BUTTON_B,
	#"left": JOY_BUTTON_DPAD_LEFT,
	#"right": JOY_BUTTON_DPAD_RIGHT,
	"handbrake": JOY_BUTTON_X,
	"respawn": JOY_BUTTON_BACK,
	"pause": JOY_BUTTON_START,
	"confirm": JOY_BUTTON_A
}


const GAMEPAD_STICK_DEADZONE := 0.15


# Un dictionnaire de bindings par joueur clavier.
var keyboard_bindings: Array[Dictionary] = []
var gamepad_bindings: Dictionary = {}

var custom_confirm_keyboard_event: InputEventKey = null
var custom_confirm_gamepad_events: Dictionary = {}

# État des touches avec côté (binding encodé -> enfoncée).
# Input.is_physical_key_pressed() ne distingue pas gauche / droite.
var _located_keys_pressed: Dictionary = {}


func _ready() -> void:
	# Continuer à suivre les relâchements de touches pendant la pause.
	process_mode = Node.PROCESS_MODE_ALWAYS

	Input.joy_connection_changed.connect(
		_on_joy_connection_changed
	)


func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey

	if key_event == null or key_event.echo:
		return

	var keycode := int(key_event.physical_keycode)

	if key_event.location == KEY_LOCATION_UNSPECIFIED:
		# Côté inconnu (dépend du système) : on considère les deux.
		for location in [KEY_LOCATION_LEFT, KEY_LOCATION_RIGHT]:
			_located_keys_pressed[
				encode_key_binding(keycode, location)
			] = key_event.pressed
		return

	_located_keys_pressed[
		encode_key_binding(keycode, key_event.location)
	] = key_event.pressed


func _notification(what: int) -> void:
	# Évite les touches « bloquées » si la fenêtre perd le focus.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_located_keys_pressed.clear()


# ============================================================
# CLAVIER : ENCODAGE DES TOUCHES (CODE + CÔTÉ)
# ============================================================

func encode_key_binding(keycode: int, location: int) -> int:
	return keycode | (location << KEY_LOCATION_SHIFT)


func get_binding_keycode(binding: int) -> int:
	return binding & KEY_BINDING_CODE_MASK


func get_binding_location(binding: int) -> int:
	return binding >> KEY_LOCATION_SHIFT


func is_key_binding_pressed(binding: int) -> bool:
	var keycode := get_binding_keycode(binding)

	if keycode == KEY_NONE:
		return false

	if get_binding_location(binding) == KEY_LOCATION_UNSPECIFIED:
		return Input.is_physical_key_pressed(keycode as Key)

	return bool(_located_keys_pressed.get(binding, false))


func initialize() -> void:
	_load_bindings()


# ============================================================
# INITIALISATION / CHARGEMENT
# ============================================================

func _load_bindings() -> void:
	_load_keyboard_bindings()
	_load_connected_gamepads()
	_apply_confirm_bindings()


func _load_keyboard_bindings() -> void:
	keyboard_bindings.clear()

	for keyboard_index in range(KEYBOARD_PLAYER_COUNT):
		var defaults := get_default_keyboard_bindings(
			keyboard_index
		)
		var bindings: Dictionary = {}

		for action in defaults:
			var default_binding := int(defaults[action])

			var saved_value := int(SaveManager.get_keyboard_binding(
				action,
				default_binding,
				keyboard_index
			))

			# Ancienne sauvegarde sans côté (ex. « Ctrl ») identique
			# à la touche par défaut : on reprend le côté par défaut.
			if (
				get_binding_location(saved_value) == KEY_LOCATION_UNSPECIFIED
				and saved_value == get_binding_keycode(default_binding)
			):
				saved_value = default_binding

			bindings[action] = saved_value

		keyboard_bindings.append(bindings)


# ============================================================
# CLAVIER : JOUEURS MULTIPLES
# ============================================================

## Convertit un device_id clavier en index de joueur clavier.
## -1 (ancien format) et 0 désignent le clavier 1.
func get_keyboard_index(device_id: int) -> int:
	return clampi(device_id, 0, KEYBOARD_PLAYER_COUNT - 1)


func get_default_keyboard_bindings(
	keyboard_index: int
) -> Dictionary:

	return KEYBOARD_DEFAULTS[
		clampi(keyboard_index, 0, KEYBOARD_DEFAULTS.size() - 1)
	]


## Indique si une action est configurable pour ce joueur clavier
## (seul le clavier 1 a la pause et la confirmation).
func has_keyboard_action(
	action_name: String,
	device_id: int
) -> bool:

	return get_default_keyboard_bindings(
		get_keyboard_index(device_id)
	).has(action_name)


func _load_connected_gamepads() -> void:
	gamepad_bindings.clear()

	for device_id in Input.get_connected_joypads():
		register_gamepad(device_id)


# ============================================================
# GAMEPADS : CONNEXION / DECONNEXION
# ============================================================

func _on_joy_connection_changed(
	device_id: int,
	connected: bool
) -> void:

	if connected:
		register_gamepad(device_id)
		gamepad_connected.emit(device_id)
	else:
		unregister_gamepad(device_id)
		gamepad_disconnected.emit(device_id)


func register_gamepad(device_id: int) -> void:
	if device_id < 0:
		return

	if gamepad_bindings.has(device_id):
		return

	var bindings: Dictionary = {}

	for action in DEFAULT_GAMEPAD_BINDINGS:
		var saved_value = SaveManager.get_gamepad_binding(
			device_id,
			action,
			DEFAULT_GAMEPAD_BINDINGS[action]
		)

		bindings[action] = int(saved_value)

	gamepad_bindings[device_id] = bindings

	_apply_confirm_bindings()


func unregister_gamepad(device_id: int) -> void:
	gamepad_bindings.erase(device_id)


func is_gamepad_registered(device_id: int) -> bool:
	return gamepad_bindings.has(device_id)


func get_connected_gamepads() -> Array[int]:
	var result: Array[int] = []

	for device_id in gamepad_bindings.keys():
		result.append(int(device_id))

	return result


# ============================================================
# CLAVIER : CONFIGURATION
# ============================================================

func set_keyboard_binding(
	action_name: String,
	event: InputEventKey,
	device_id: int = 0
) -> void:

	var keyboard_index := get_keyboard_index(device_id)

	if not has_keyboard_action(action_name, keyboard_index):
		push_warning(
			"Action clavier inconnue : " + action_name
		)
		return

	if keyboard_bindings.size() <= keyboard_index:
		_load_keyboard_bindings()

	# Le côté n'est conservé que pour les touches doubles
	# (Ctrl, Shift, Alt, Méta) ; il vaut UNSPECIFIED pour les autres.
	var keycode := encode_key_binding(
		int(event.physical_keycode),
		int(event.location)
	)

	keyboard_bindings[keyboard_index][action_name] = keycode

	SaveManager.set_keyboard_binding(
		action_name,
		keycode,
		keyboard_index
	)

	if action_name == "confirm":
		_apply_confirm_bindings()


func get_keyboard_binding(
	action_name: String,
	device_id: int = 0
) -> int:

	var keyboard_index := get_keyboard_index(device_id)

	var defaults := get_default_keyboard_bindings(
		keyboard_index
	)

	if keyboard_bindings.size() <= keyboard_index:
		return int(defaults.get(action_name, KEY_NONE))

	return int(
		keyboard_bindings[keyboard_index].get(
			action_name,
			defaults.get(
				action_name,
				KEY_NONE
			)
		)
	)


# ============================================================
# GAMEPAD : CONFIGURATION
# ============================================================

func set_gamepad_binding(
	device_id: int,
	action_name: String,
	event: InputEventJoypadButton
) -> void:

	if device_id < 0:
		push_warning("Device gamepad invalide.")
		return

	if not DEFAULT_GAMEPAD_BINDINGS.has(action_name):
		push_warning(
			"Action gamepad inconnue : " + action_name
		)
		return

	if not gamepad_bindings.has(device_id):
		register_gamepad(device_id)

	gamepad_bindings[device_id][action_name] = (
		event.button_index
	)

	SaveManager.set_gamepad_binding(
		device_id,
		action_name,
		event.button_index
	)

	if action_name == "confirm":
		_apply_confirm_bindings()


func get_gamepad_binding(
	device_id: int,
	action_name: String
) -> int:

	if device_id < 0:
		return -1

	if not gamepad_bindings.has(device_id):
		register_gamepad(device_id)

	if not gamepad_bindings.has(device_id):
		return -1

	return int(
		gamepad_bindings[device_id].get(
			action_name,
			DEFAULT_GAMEPAD_BINDINGS.get(
				action_name,
				-1
			)
		)
	)


# ============================================================
# INPUT JOUEUR
# ============================================================

func get_player_input(
	device_type: String,
	device_id: int
) -> PlayerInputState:

	var input_state := PlayerInputState.new()

	match device_type:
		"keyboard":
			_fill_keyboard_input(
				input_state,
				device_id
			)

		"gamepad":
			_fill_gamepad_input(
				input_state,
				device_id
			)

		_:
			push_warning(
				"Type de périphérique inconnu : "
				+ device_type
			)

	return input_state


# ============================================================
# INPUT CLAVIER
# ============================================================

func _fill_keyboard_input(
	input_state: PlayerInputState,
	device_id: int
) -> void:

	input_state.throttle = (
		_get_keyboard_action_strength(
			"accelerate",
			device_id
		)
	)

	input_state.brake = (
		_get_keyboard_action_strength(
			"brake",
			device_id
		)
	)

	input_state.steering = (
		_get_keyboard_action_strength("right", device_id)
		-
		_get_keyboard_action_strength("left", device_id)
	)

	input_state.handbrake = (
		_is_keyboard_action_pressed(
			"handbrake",
			device_id
		)
	)

	input_state.respawn = (
		_is_keyboard_action_pressed(
			"respawn",
			device_id
		)
	)



func _get_keyboard_action_strength(
	action_name: String,
	device_id: int
) -> float:

	var binding := get_keyboard_binding(
		action_name,
		device_id
	)

	if is_key_binding_pressed(binding):
		return 1.0

	return 0.0


func _is_keyboard_action_pressed(
	action_name: String,
	device_id: int
) -> bool:

	return (
		_get_keyboard_action_strength(
			action_name,
			device_id
		) > 0.5
	)


# ============================================================
# INPUT GAMEPAD
# ============================================================

func _fill_gamepad_input(
	input_state: PlayerInputState,
	device_id: int
) -> void:

	if device_id < 0:
		return

	if not is_gamepad_registered(device_id):
		register_gamepad(device_id)

	if not is_gamepad_registered(device_id):
		return

	input_state.throttle = (
		_get_gamepad_action_strength(
			device_id,
			"accelerate"
		)
	)

	input_state.brake = (
		_get_gamepad_action_strength(
			device_id,
			"brake"
		)
	)

	input_state.steering = (
		_get_gamepad_steering(
			device_id
		)
	)

	input_state.handbrake = (
		_is_gamepad_action_pressed(
			device_id,
			"handbrake"
		)
	)

	input_state.respawn = (
		_is_gamepad_action_pressed(
			device_id,
			"respawn"
		)
	)


func _get_gamepad_steering(
	device_id: int
) -> float:

	var axis_value := Input.get_joy_axis(
		device_id,
		JOY_AXIS_LEFT_X
	)

	return _apply_deadzone(
		axis_value,
		GAMEPAD_STICK_DEADZONE
	)


func _get_gamepad_action_strength(
	device_id: int,
	action_name: String
) -> float:

	if action_name == "left":
		return maxf(
			-_get_gamepad_steering(device_id),
			0.0
		)

	if action_name == "right":
		return maxf(
			_get_gamepad_steering(device_id),
			0.0
		)

	if action_name == "accelerate":
		return _get_gamepad_button_strength(
			device_id,
			action_name
		)

	if action_name == "brake":
		return _get_gamepad_button_strength(
			device_id,
			action_name
		)

	return _get_gamepad_button_strength(
		device_id,
		action_name
	)


func _get_gamepad_button_strength(
	device_id: int,
	action_name: String
) -> float:

	var button_index := get_gamepad_binding(
		device_id,
		action_name
	)

	if button_index < 0:
		return 0.0

	if Input.is_joy_button_pressed(
		device_id,
		button_index
	):
		return 1.0

	return 0.0


func _is_gamepad_action_pressed(
	device_id: int,
	action_name: String
) -> bool:

	return (
		_get_gamepad_button_strength(
			device_id,
			action_name
		) > 0.5
	)


func _apply_deadzone(
	value: float,
	deadzone: float
) -> float:

	var magnitude := absf(value)

	if magnitude <= deadzone:
		return 0.0

	var normalized := (
		magnitude - deadzone
	) / (
		1.0 - deadzone
	)

	return (
		signf(value)
		* clampf(
			normalized,
			0.0,
			1.0
		)
	)


# ============================================================
# CONFIRMATION DES MENUS
# ============================================================

func _apply_confirm_bindings() -> void:
	_remove_custom_confirm_events()

	# --------------------------------------------------------
	# CLAVIER
	# --------------------------------------------------------

	var keyboard_keycode := get_binding_keycode(
		get_keyboard_binding("confirm")
	)

	if keyboard_keycode != KEY_NONE:
		var key_event := InputEventKey.new()

		key_event.physical_keycode = (
			keyboard_keycode as Key
		)

		key_event.device = -1

		custom_confirm_keyboard_event = key_event

		InputMap.action_add_event(
			"ui_accept",
			key_event
		)

	# --------------------------------------------------------
	# GAMEPADS
	# --------------------------------------------------------

	for device_id in gamepad_bindings:
		var button_index := get_gamepad_binding(
			int(device_id),
			"confirm"
		)

		if button_index < 0:
			continue

		var joy_event := InputEventJoypadButton.new()

		joy_event.device = int(device_id)
		joy_event.button_index = button_index as JoyButton

		custom_confirm_gamepad_events[
			int(device_id)
		] = joy_event

		InputMap.action_add_event(
			"ui_accept",
			joy_event
		)


func _remove_custom_confirm_events() -> void:

	if custom_confirm_keyboard_event != null:
		if InputMap.has_action("ui_accept"):
			InputMap.action_erase_event(
				"ui_accept",
				custom_confirm_keyboard_event
			)

		custom_confirm_keyboard_event = null

	for device_id in custom_confirm_gamepad_events:
		var event: InputEventJoypadButton = (
			custom_confirm_gamepad_events[
				device_id
			]
		)

		if InputMap.has_action("ui_accept"):
			InputMap.action_erase_event(
				"ui_accept",
				event
			)

	custom_confirm_gamepad_events.clear()


# ============================================================
# AFFICHAGE DES BINDINGS
# ============================================================

func get_binding_display_name(
	device_type: String,
	device_id: int,
	action_name: String
) -> String:

	if device_type == "keyboard":
		return _get_keyboard_display_name(
			action_name,
			device_id
		)

	if device_type == "gamepad":
		return _get_gamepad_display_name(
			device_id,
			action_name
		)

	return "Non configuré"



func _get_keyboard_display_name(
	action_name: String,
	device_id: int
) -> String:

	var binding := get_keyboard_binding(
		action_name,
		device_id
	)

	var physical_keycode := get_binding_keycode(binding)

	if physical_keycode == KEY_NONE:
		return "Non configuré"

	var text := ""
	var physical_name := OS.get_keycode_string(physical_keycode as Key)

	# Pavé numérique : nom explicite (sinon « Left », « Clear »... selon
	# l'état du Verr. Num).
	if physical_name.begins_with("Kp "):
		text = "Pavé " + physical_name.substr(3).replace("Subtract", "-").replace("Add", "+").replace("Multiply", "*").replace("Divide", "/").replace("Period", ".").replace("Enter", "Entrée")
	else:
		var key_label := DisplayServer.keyboard_get_label_from_physical(
			physical_keycode as Key
		)
		text = OS.get_keycode_string(key_label)

	match get_binding_location(binding):
		KEY_LOCATION_LEFT:
			text += " gauche"
		KEY_LOCATION_RIGHT:
			text += " droit"

	return text


func _get_gamepad_display_name(
	device_id: int,
	action_name: String
) -> String:

	var button_index := get_gamepad_binding(
		device_id,
		action_name
	)

	if button_index < 0:
		return "Non configuré"

	return _get_gamepad_button_name(
		button_index
	)


func _get_gamepad_button_name(
	button_index: int
) -> String:

	match button_index:
		JOY_BUTTON_A:
			return "A"

		JOY_BUTTON_B:
			return "B"

		JOY_BUTTON_X:
			return "X"

		JOY_BUTTON_Y:
			return "Y"

		JOY_BUTTON_BACK:
			return "Back"

		JOY_BUTTON_GUIDE:
			return "Guide"

		JOY_BUTTON_START:
			return "Start"

		JOY_BUTTON_LEFT_STICK:
			return "Stick gauche"

		JOY_BUTTON_RIGHT_STICK:
			return "Stick droit"

		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"

		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"

		JOY_BUTTON_DPAD_UP:
			return "D-Pad ↑"

		JOY_BUTTON_DPAD_DOWN:
			return "D-Pad ↓"

		JOY_BUTTON_DPAD_LEFT:
			return "D-Pad ←"

		JOY_BUTTON_DPAD_RIGHT:
			return "D-Pad →"

		_:
			return "Bouton %d" % button_index


# ============================================================
# RESET
# ============================================================

func reset_bindings(
	device_type: String,
	device_id: int
) -> void:

	if device_type == "keyboard":

		var keyboard_index := get_keyboard_index(device_id)

		var defaults := get_default_keyboard_bindings(
			keyboard_index
		)

		if keyboard_bindings.size() <= keyboard_index:
			_load_keyboard_bindings()

		keyboard_bindings[keyboard_index] = defaults.duplicate()

		SaveManager.reset_keyboard_bindings(
			defaults,
			keyboard_index
		)

		_apply_confirm_bindings()

	elif device_type == "gamepad":

		if not gamepad_bindings.has(device_id):
			register_gamepad(device_id)

		gamepad_bindings[device_id] = (
			DEFAULT_GAMEPAD_BINDINGS.duplicate()
		)

		SaveManager.reset_gamepad_bindings(
			device_id,
			DEFAULT_GAMEPAD_BINDINGS
		)

		_apply_confirm_bindings()
