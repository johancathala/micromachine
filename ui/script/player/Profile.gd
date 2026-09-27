extends Control


@onready var back_button: Button = \
	$MarginContainer/VBoxContainer/Footer/BackButton

@onready var nickname_edit: LineEdit = \
	$MarginContainer/VBoxContainer/VBoxContainer/NicknameEdit

@onready var error_label: Label = \
	$MarginContainer/VBoxContainer/VBoxContainer/ErrorLabel

@onready var save_button: Button = \
	$MarginContainer/VBoxContainer/Footer/SaveButton


func _ready() -> void:
	nickname_edit.text = SaveManager.get_nickname()

	error_label.text = ""

	back_button.pressed.connect(_on_back_pressed)
	save_button.pressed.connect(_on_save_pressed)

	nickname_edit.text_submitted.connect(
		_on_nickname_submitted
	)

	nickname_edit.grab_focus()


func _on_back_pressed() -> void:
	NavigationManager.go_back()


func _on_nickname_submitted(_text: String) -> void:
	_save_nickname()


func _on_save_pressed() -> void:
	_save_nickname()


func _save_nickname() -> void:
	var nickname := nickname_edit.text.strip_edges()

	if not _is_valid_nickname(nickname):
		error_label.text = "Pseudo invalide."
		nickname_edit.grab_focus()
		return

	SaveManager.set_nickname(nickname)

	NavigationManager.go_back()


func _is_valid_nickname(nickname: String) -> bool:
	if nickname.is_empty():
		return false

	if nickname.length() > 20:
		return false

	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9 _-]+$")

	return regex.search(nickname) != null
