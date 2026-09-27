extends Control

const PROFILE_SCENE := \
    "res://ui/scene/Profile.tscn"

const CONTROLS_SCENE := \
    "res://ui/scene/Controls.tscn"

const AUDIO_SCENE := \
    "res://ui/scene/Audio.tscn"

const DISPLAY_SCENE := \
    "res://ui/scene/Display.tscn"


@onready var back_button: Button = \
	$MarginContainer/VBoxContainer/OptionsContainer/BackButton

@onready var profile_button: Button = \
	$MarginContainer/VBoxContainer/OptionsContainer/ProfileButton

@onready var controls_button: Button = \
	$MarginContainer/VBoxContainer/OptionsContainer/ControlsButton

@onready var audio_button: Button = \
	$MarginContainer/VBoxContainer/OptionsContainer/AudioButton

@onready var display_button: Button = \
	$MarginContainer/VBoxContainer/OptionsContainer/DisplayButton


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	profile_button.pressed.connect(_on_profile_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	audio_button.pressed.connect(_on_audio_pressed)
	display_button.pressed.connect(_on_display_pressed)

	profile_button.grab_focus()


func _on_back_pressed() -> void:
	NavigationManager.go_back()


func _on_profile_pressed() -> void:
	NavigationManager.go_to(PROFILE_SCENE)


func _on_controls_pressed() -> void:
	NavigationManager.go_to(CONTROLS_SCENE)


func _on_audio_pressed() -> void:
	NavigationManager.go_to(AUDIO_SCENE)


func _on_display_pressed() -> void:
	NavigationManager.go_to(DISPLAY_SCENE)
