extends Control


const MAIN_MENU_SCENE := \
    "res://ui/scene/MainMenu.tscn"


@onready var nickname_edit: LineEdit = \
	$MarginContainer/VBoxContainer/NicknameEdit

@onready var error_label: Label = \
	$MarginContainer/VBoxContainer/ErrorLabel

@onready var continue_button: Button = \
	$MarginContainer/VBoxContainer/ContinueButton


func _ready() -> void:
	error_label.text = ""

	continue_button.pressed.connect(
		_on_continue_pressed
	)

	nickname_edit.text_submitted.connect(
		_on_nickname_submitted
	)

	nickname_edit.grab_focus()


func _on_continue_pressed() -> void:
	_validate_and_continue()


func _on_nickname_submitted(_text: String) -> void:
	_validate_and_continue()

func _is_valid_nickname(nickname: String) -> bool:
	if nickname.is_empty():
		return false
		
	if nickname.length() > 20:
		return false
		
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9 _-]+$")
	
	return regex.search(nickname) != null


func _validate_and_continue() -> void:
	var nickname := nickname_edit.text.strip_edges()
	
	if not _is_valid_nickname(nickname):
		error_label.text = "Pseudo invalide."
		nickname_edit.grab_focus()
		return

	SaveManager.set_nickname(nickname)

	NavigationManager.go_to(
		MAIN_MENU_SCENE,
		false
	)
	
	
