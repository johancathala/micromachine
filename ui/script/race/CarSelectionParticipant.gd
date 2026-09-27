extends Button
class_name CarSelectionParticipant

signal participant_selected(index: int)

var participant_index: int = -1


@onready var name_label: Label = (
	$MarginContainer/HBoxContainer/InfoVBox/NameLabel
)

@onready var device_label: Label = (
	$MarginContainer/HBoxContainer/InfoVBox/DeviceLabel
)

@onready var car_label: Label = (
	$MarginContainer/HBoxContainer/SelectionVBox/CarLabel
)

@onready var color_label: Label = (
	$MarginContainer/HBoxContainer/SelectionVBox/ColorLabel
)


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	pressed.connect(_on_pressed)


func setup(
	index: int,
	participant: Dictionary
) -> void:

	participant_index = index

	var nickname := str(
		participant.get("nickname", "")
	)

	var is_ai := bool(
		participant.get("is_ai", false)
	)

	var car_id := str(
		participant.get("car_id", "")
	)

	var color_id := str(
		participant.get("color_id", "")
	)


	if is_ai:
		name_label.text = nickname
		device_label.text = "IA"
	else:
		name_label.text = nickname

		var device_type := str(
			participant.get("device_type", "")
		)

		var device_id := int(
			participant.get("device_id", -1)
		)

		if device_type == "keyboard":
			device_label.text = "Clavier"
		else:
			device_label.text = "Manette %d" % (device_id + 1)


	if car_id.is_empty():
		car_label.text = "Voiture : —"
	else:
		var car := CarCatalog.get_car(car_id)

		if car.is_empty():
			car_label.text = "Voiture : —"
		else:
			car_label.text = "Voiture : %s" % car.name


	if color_id.is_empty():
		color_label.text = "Couleur : —"
	else:
		var color := CarCatalog.get_color(color_id)

		if color.is_empty():
			color_label.text = "Couleur : —"
		else:
			color_label.text = "Couleur : %s" % color.name


func _on_pressed() -> void:
	participant_selected.emit(participant_index)
