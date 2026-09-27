extends Control
class_name PlayerSlot

signal remove_requested(player_id: int)
signal nickname_changed(player_id: int, nickname: String)

var player_id: int = -1
var device_type: String = ""
var device_id: int = -1
var nickname: String = ""


@onready var player_label: Label = (
	$PanelContainer/MarginContainer/HBoxContainer/PlayerLabel
)

@onready var remove_button: Button = (
	$PanelContainer/MarginContainer/HBoxContainer/RemoveButton
)

@onready var device_label: Label = (
	$PanelContainer/MarginContainer/HBoxContainer/DeviceLabel
)

@onready var nickname_edit: LineEdit = (
	$PanelContainer/MarginContainer/HBoxContainer/NicknameEdit
)


func _ready() -> void:
	remove_button.pressed.connect(_on_remove_pressed)
	nickname_edit.text_submitted.connect(_on_nickname_submitted)
	nickname_edit.focus_exited.connect(_on_nickname_focus_exited)
	remove_button.focus_mode = Control.FOCUS_ALL
	nickname_edit.focus_mode = Control.FOCUS_ALL

func setup(player: Dictionary, display_number: int) -> void:
	player_id = int(player.get("player_id", -1))
	device_type = str(player.get("device_type", ""))
	device_id = int(player.get("device_id", -1))
	nickname = str(player.get("nickname", ""))

	_update_display(display_number)


func _update_display(display_number: int) -> void:
	player_label.text = "Joueur %d" % display_number

	if device_type == "keyboard":
		device_label.text = "Clavier"
	else:
		device_label.text = "Manette %d" % (device_id + 1)

	nickname_edit.text = nickname
	nickname_edit.placeholder_text = "Pseudo"
	nickname_edit.max_length = 20

	remove_button.text = "Supprimer"


func _on_remove_pressed() -> void:
	if player_id < 0:
		return

	remove_requested.emit(player_id)


func _on_nickname_submitted(new_text: String) -> void:
	_save_nickname(new_text)


func _on_nickname_focus_exited() -> void:
	_save_nickname(nickname_edit.text)


func _save_nickname(new_nickname: String) -> void:
	new_nickname = new_nickname.strip_edges()

	# On refuse un pseudo vide.
	if new_nickname.is_empty():
		nickname_edit.text = nickname
		return

	# Validation identique à celle utilisée pour le profil.
	if not _is_valid_nickname(new_nickname):
		nickname_edit.text = nickname
		return

	# Rien n'a changé.
	if new_nickname == nickname:
		return

	nickname = new_nickname
	nickname_edit.text = nickname

	nickname_changed.emit(player_id, nickname)


func _is_valid_nickname(value: String) -> bool:
	if value.is_empty():
		return false

	if value.length() > 20:
		return false

	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9 _-]+$")

	return regex.search(value) != null
