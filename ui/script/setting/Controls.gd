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

@onready var back_button: Button = \
	$MarginContainer/VBoxContainer/Footer/BackButton

@onready var device_option: OptionButton = \
	$MarginContainer/VBoxContainer/DeviceSelector/DeviceOption

@onready var controls_list: VBoxContainer = \
	$MarginContainer/VBoxContainer/ControlsScroll/ControlsList

@onready var reset_button: Button = \
	$MarginContainer/VBoxContainer/Footer/ResetButton


var selected_device_type := "keyboard"
var selected_device_id := -1

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

	device_option.grab_focus()


func _setup_devices() -> void:
	device_option.clear()

	device_option.add_item(
		"Clavier",
		0
	)

	for device_id in Input.get_connected_joypads():
		device_option.add_item(
			"Manette %d" % (device_id + 1),
			device_id + 1
		)


func _refresh_controls() -> void:
	var btt = get_viewport().gui_get_focus_owner()
	if btt is Button:
		print("C'est un bouton !")
	else:
		btt = device_option

	for child in controls_list.get_children():
		child.queue_free()

	for action in ACTIONS:
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
		
		device_option.grab_focus()


func _on_device_selected(index: int) -> void:
	var value: int = device_option.get_item_id(index)

	if value == 0:
		selected_device_type = "keyboard"
		selected_device_id = -1
	else:
		selected_device_type = "gamepad"
		selected_device_id = value - 1

	_refresh_controls()


func _on_binding_requested(action_name: String) -> void:
	waiting_for_binding = true
	waiting_action = action_name

func _on_gamepad_connected(
	device_id: int
) -> void:

	_setup_devices()
	_refresh_controls()


func _on_gamepad_disconnected(
	device_id: int
) -> void:

	_setup_devices()

	# Si la manette actuellement sélectionnée
	# vient d'être débranchée, revenir au clavier.
	if (
		selected_device_type == "gamepad"
		and selected_device_id == device_id
	):
		selected_device_type = "keyboard"
		selected_device_id = -1

	_refresh_controls()

func _unhandled_input(event: InputEvent) -> void:
	if not waiting_for_binding:
		return

	if not event.is_pressed():
		return

	if event is InputEventKey:
		InputManager.set_keyboard_binding(
			waiting_action,
			event
		)

	elif event is InputEventJoypadButton:
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
	NavigationManager.go_back()
