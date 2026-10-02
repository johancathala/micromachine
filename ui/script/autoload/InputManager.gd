extends Node

const PlayerInputStateClass = preload(
	"res://input/PlayerInputState.gd"
)

signal gamepad_connected(device_id: int)
signal gamepad_disconnected(device_id: int)


const DEFAULT_KEY_BINDINGS := {
	"accelerate": KEY_UP,
	"brake": KEY_DOWN,
	"left": KEY_LEFT,
	"right": KEY_RIGHT,
	"handbrake": KEY_SPACE,
	"respawn": KEY_R,
	"pause": KEY_ESCAPE,
	"confirm": KEY_ENTER
}


const DEFAULT_GAMEPAD_BINDINGS := {
	"accelerate": JOY_BUTTON_A,
	"brake": JOY_BUTTON_B,
	#"left": JOY_BUTTON_DPAD_LEFT,
	#"right": JOY_BUTTON_DPAD_RIGHT,
	"handbrake": JOY_BUTTON_X,
	"respawn": JOY_BUTTON_Y,
	"pause": JOY_BUTTON_START,
	"confirm": JOY_BUTTON_A
}


const GAMEPAD_STICK_DEADZONE := 0.15


var keyboard_bindings: Dictionary = {}
var gamepad_bindings: Dictionary = {}

var custom_confirm_keyboard_event: InputEventKey = null
var custom_confirm_gamepad_events: Dictionary = {}


func _ready() -> void:
	Input.joy_connection_changed.connect(
		_on_joy_connection_changed
	)


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

	for action in DEFAULT_KEY_BINDINGS:
		var saved_value = SaveManager.get_keyboard_binding(
			action,
			DEFAULT_KEY_BINDINGS[action]
		)

		keyboard_bindings[action] = int(saved_value)


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
	event: InputEventKey
) -> void:

	if not DEFAULT_KEY_BINDINGS.has(action_name):
		push_warning(
			"Action clavier inconnue : " + action_name
		)
		return

	var keycode := event.physical_keycode

	keyboard_bindings[action_name] = keycode

	SaveManager.set_keyboard_binding(
		action_name,
		keycode
	)

	if action_name == "confirm":
		_apply_confirm_bindings()


func get_keyboard_binding(
	action_name: String
) -> int:

	return int(
		keyboard_bindings.get(
			action_name,
			DEFAULT_KEY_BINDINGS.get(
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
			_fill_keyboard_input(input_state)

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
	input_state: PlayerInputState
) -> void:

	input_state.throttle = (
		_get_keyboard_action_strength(
			"accelerate"
		)
	)

	input_state.brake = (
		_get_keyboard_action_strength(
			"brake"
		)
	)

	input_state.steering = (
		_get_keyboard_action_strength("right")
		-
		_get_keyboard_action_strength("left")
	)

	input_state.handbrake = (
		_is_keyboard_action_pressed(
			"handbrake"
		)
	)

	input_state.respawn = (
		_is_keyboard_action_pressed(
			"respawn"
		)
	)


func _get_keyboard_action_strength(
	action_name: String
) -> float:

	var keycode := get_keyboard_binding(
		action_name
	)

	if keycode == KEY_NONE:
		return 0.0

	if Input.is_key_pressed(keycode):
		return 1.0

	return 0.0


func _is_keyboard_action_pressed(
	action_name: String
) -> bool:

	return (
		_get_keyboard_action_strength(
			action_name
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

	var keyboard_keycode := get_keyboard_binding(
		"confirm"
	)

	if keyboard_keycode != KEY_NONE:
		var key_event := InputEventKey.new()

		key_event.physical_keycode = (
			keyboard_keycode
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
		joy_event.button_index = button_index

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
			action_name
		)

	if device_type == "gamepad":
		return _get_gamepad_display_name(
			device_id,
			action_name
		)

	return "Non configuré"


func _get_keyboard_display_name(
	action_name: String
) -> String:

	var keycode := get_keyboard_binding(
		action_name
	)

	if keycode == KEY_NONE:
		return "Non configuré"

	return OS.get_keycode_string(
		keycode
	)


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

		keyboard_bindings = (
			DEFAULT_KEY_BINDINGS.duplicate()
		)

		SaveManager.reset_keyboard_bindings(
			DEFAULT_KEY_BINDINGS
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
