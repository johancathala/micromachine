extends Control

@onready var back_button: Button = $MarginContainer/VBoxContainer/OptionsContainer/BackButton

@onready var profile_button: Button = $MarginContainer/VBoxContainer/OptionsContainer/ProfileButton

@onready var controls_button: Button = $MarginContainer/VBoxContainer/OptionsContainer/ControlsButton

@onready var audio_button: Button = $MarginContainer/VBoxContainer/OptionsContainer/AudioButton

@onready var display_button: Button = $MarginContainer/VBoxContainer/OptionsContainer/DisplayButton

@onready var focus_manager: MenuFocusManager = $MenuFocusManager


func _ready() -> void:
	AudioManager.bind_sound_btt()
	back_button.pressed.connect(_on_back_pressed)
	profile_button.pressed.connect(_on_profile_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	audio_button.pressed.connect(_on_audio_pressed)
	display_button.pressed.connect(_on_display_pressed)

	set_focus()


func set_focus() -> void:
	focus_manager.set_vertical_navigation([
		profile_button,
		controls_button,
		audio_button,
		display_button,
		back_button
	])


func _on_back_pressed() -> void:
	NavigationManager.go_back_menu()


func _on_profile_pressed() -> void:
	NavigationManager.go("Profile")


func _on_controls_pressed() -> void:
	NavigationManager.go("Controls")


func _on_audio_pressed() -> void:
	NavigationManager.go("Audio")


func _on_display_pressed() -> void:
	NavigationManager.go("Display")
