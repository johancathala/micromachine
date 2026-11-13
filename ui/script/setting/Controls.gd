extends Control


const BINDING_ROW_SCENE := preload(
    "res://ui/scene/ControlBindingRow.tscn"
)

const ACTIONS := [
	{"id": "accelerate", "name": "Accélérer"},
	{"id": "brake", "name": "Freiner"},
	{"id": "left", "name": "Gauche"},
	{"id": "right", "name": "Droite"},
	{"id": "handbrake", "name": "Frein à main"},
	{"id": "respawn", "name": "Réapparition"},
	{"id": "pause", "name": "Pause"},
	{"id": "confirm", "name": "Confirmer"}
]

signal quit_control()

# Identifiants des entrées de device_option :
# 0..N-1 = joueurs clavier, GAMEPAD_ITEM_OFFSET + device_id = manettes.
const GAMEPAD_ITEM_OFFSET := 100

@onready var back_button: Button = \
	$MarginContainer/VBoxContainer/Footer/BackButton

@onready var device_option: OptionButton = \
	$MarginContainer/VBoxContainer/DeviceSelector/DeviceOption

@onready var controls_list: VBoxContainer = \
	$MarginContainer/VBoxContainer/ControlsScroll/ControlsList

@onready var reset_button: Button = \
	$MarginContainer/VBoxContainer/Footer/ResetButton

@onready var focus_manager: MenuFocusManager = $MenuFocusManager
#var opened_from_pause := false

var selected_device_type := "keyboard"
var selected_device_id := 0

var waiting_for_binding := false
var waiting_action := ""


func _ready() -> void:
	_setup_devices()
	_refresh_controls()
	InputManager.gamepad_connected.connect(
		_on_gamepad_connected
	)

	InputManager.gamepad_disconnected.connect(
		_on_gamepad_disconnected
	)

	back_button.pressed.connect(
		_on_back_pressed
	)

	reset_button.pressed.connect(
		_on_reset_pressed
	)

	device_option.item_selected.connect(
		_on_device_selected
	)

	AudioManager.bind_sound_btt()


func set_focus() -> void:
	
	focus_manager.set_neighbors(back_button,null,null,reset_button,reset_button)
	focus_manager.set_neighbors(reset_button,null,null,back_button,back_button)

	focus_manager.focus_initial()

func _setup_devices() -> void:
	device_option.clear()

	for keyboard_id in range(InputManager.KEYBOARD_PLAYER_COUNT):
		device_option.add_item(
			"Clavier %d" % (keyboard_id + 1),
			keyboard_id
		)

	for device_id in Input.get_connected_joypads():
		device_option.add_item(
			"Manette %d" % (device_id + 1),
			GAMEPAD_ITEM_OFFSET + device_id
		)

	_select_current_device_item()


func _select_current_device_item() -> void:
	var item_id := selected_device_id

	if selected_device_type == "gamepad":
		item_id = GAMEPAD_ITEM_OFFSET + selected_device_id

	var index := device_option.get_item_index(item_id)

	if index >= 0:
		device_option.select(index)


func _refresh_controls() -> void:
	var btt = get_viewport().gui_get_focus_owner()
	if not btt is Button:
		btt = device_option

	for child in controls_list.get_children():
		child.queue_free()

	for action in ACTIONS:
		# Seul le clavier 1 a la pause et la confirmation.
		if (
			selected_device_type == "keyboard"
			and not InputManager.has_keyboard_action(
				action["id"],
				selected_device_id
			)
		):
			continue

		var row: ControlBindingRow = \
			BINDING_ROW_SCENE.instantiate()

		controls_list.add_child(row)

		var binding_text : String = \
			InputManager.get_binding_display_name(
				selected_device_type,
				selected_device_id,
				action["id"]
			)

		row.setup(
			action["id"],
			action["name"],
			binding_text
		)

		row.binding_requested.connect(
			_on_binding_requested
		)
		
	set_focus()


func _on_device_selected(index: int) -> void:
	var value: int = device_option.get_item_id(index)

	if value < GAMEPAD_ITEM_OFFSET:
		selected_device_type = "keyboard"
		selected_device_id = value
	else:
		selected_device_type = "gamepad"
		selected_device_id = value - GAMEPAD_ITEM_OFFSET

	_refresh_controls()


func _on_binding_requested(action_name: String) -> void:
	waiting_for_binding = true
	waiting_action = action_name

func _on_gamepad_connected(
	_device_id: int
) -> void:

	_setup_devices()
	_refresh_controls()


func _on_gamepad_disconnected(
	device_id: int
) -> void:

	# Si la manette actuellement sélectionnée
	# vient d'être débranchée, revenir au clavier.
	if (
		selected_device_type == "gamepad"
		and selected_device_id == device_id
	):
		selected_device_type = "keyboard"
		selected_device_id = 0

	_setup_devices()

	_refresh_controls()

func _unhandled_input(event: InputEvent) -> void:
	if not waiting_for_binding:
		return

	if not event.is_pressed():
		return

	# La touche est enregistrée pour le périphérique sélectionné
	# (clavier 1, clavier 2 ou manette) ; les autres entrées sont ignorées.
	if event is InputEventKey and selected_device_type == "keyboard":
		InputManager.set_keyboard_binding(
			waiting_action,
			event,
			selected_device_id
		)

	elif (
		event is InputEventJoypadButton
		and selected_device_type == "gamepad"
	):
		InputManager.set_gamepad_binding(
			selected_device_id,
			waiting_action,
			event
		)

	else:
		return

	waiting_for_binding = false
	waiting_action = ""

	_refresh_controls()


func _on_reset_pressed() -> void:
	InputManager.reset_bindings(
		selected_device_type,
		selected_device_id
	)

	_refresh_controls()


func _on_back_pressed() -> void:
	if get_meta("opened_from_pause", false):
		quit_control.emit()
		queue_free()
	else:
		NavigationManager.go_back()
