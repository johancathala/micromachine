extends Control

@onready var focus_manager: MenuFocusManager = $MenuFocusManager
@onready var back_button: Button = \
	$MarginContainer/VBoxContainer/Footer/BackButton

@onready var master_slider: HSlider = \
	$MarginContainer/VBoxContainer/MasterRow/MasterSlider

@onready var music_slider: HSlider = \
	$MarginContainer/VBoxContainer/MusicRow/MusicSlider

@onready var sfx_slider: HSlider = \
	$MarginContainer/VBoxContainer/SFXRow/SFXSlider

@onready var reset_button: Button = \
	$MarginContainer/VBoxContainer/Footer/ResetButton


func _ready() -> void:
	AudioManager.bind_sound_btt()
	_load_values()
	_connect_signals()

	focus_manager.set_vertical_navigation([
		master_slider,
		music_slider,
		sfx_slider,
		back_button
	])
	focus_manager.set_neighbors(back_button,null,null,reset_button,reset_button)
	focus_manager.set_neighbors(reset_button,null,null,back_button,back_button)

	focus_manager.set_focus(master_slider)


func _connect_signals() -> void:
	back_button.pressed.connect(_on_back_pressed)

	master_slider.value_changed.connect(
		_on_master_changed
	)

	music_slider.value_changed.connect(
		_on_music_changed
	)

	sfx_slider.value_changed.connect(
		_on_sfx_changed
	)

	reset_button.pressed.connect(
		_on_reset_pressed
	)


func _load_values() -> void:
	master_slider.value = \
		SaveManager.get_audio_setting(
			"master_volume",
			1.0
		)

	music_slider.value = \
		SaveManager.get_audio_setting(
			"music_volume",
			1.0
		)

	sfx_slider.value = \
		SaveManager.get_audio_setting(
			"sfx_volume",
			1.0
		)

	_apply_audio()


func _on_master_changed(value: float) -> void:
	SaveManager.set_audio_setting(
		"master_volume",
		value
	)

	_apply_audio()


func _on_music_changed(value: float) -> void:
	SaveManager.set_audio_setting(
		"music_volume",
		value
	)

	_apply_audio()


func _on_sfx_changed(value: float) -> void:
	SaveManager.set_audio_setting(
		"sfx_volume",
		value
	)

	_apply_audio()


func _apply_audio() -> void:
	SaveManager.apply_audio_settings()


func _on_reset_pressed() -> void:
	master_slider.value = 1.0
	music_slider.value = 1.0
	sfx_slider.value = 1.0


func _on_back_pressed() -> void:
	NavigationManager.go_back()
