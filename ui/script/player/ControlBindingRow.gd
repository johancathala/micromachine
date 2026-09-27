class_name ControlBindingRow
extends HBoxContainer


signal binding_requested(action_name: String)


@onready var action_label: Label = $ActionLabel
@onready var binding_button: Button = $BindingButton


var action_name: String = ""


func setup(
	p_action_name: String,
	display_name: String,
	binding_text: String
) -> void:
	action_name = p_action_name

	action_label.text = display_name
	binding_button.text = binding_text


func _ready() -> void:
	binding_button.pressed.connect(
		_on_binding_pressed
	)


func _on_binding_pressed() -> void:
	binding_requested.emit(action_name)
