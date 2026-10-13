extends Control
class_name PauseOverlay

# ============================================================
# SIGNAUX
# ============================================================
signal resume_pressed
signal quit_pressed
signal controls_pressed
signal main_menu_pressed


# ============================================================
# NŒUDS
# ============================================================
@onready var resume_button: Button = $MarginContainer/PanelContainer/VBoxContainer/ResumeButton
@onready var quit_button: Button = $MarginContainer/PanelContainer/VBoxContainer/QuitButton
@onready var controls_button: Button = $MarginContainer/PanelContainer/VBoxContainer/ControlsButton
@onready var main_menu_button: Button = $MarginContainer/PanelContainer/VBoxContainer/MainMenuButton


# ============================================================
# INITIALISATION
# ============================================================
func _ready() -> void:
	AudioManager.bind_sound_btt()
	process_mode = Node.PROCESS_MODE_ALWAYS

	resume_button.pressed.connect(_on_resume_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)

	hide()

func get_focus() -> void:
	resume_button.grab_focus()

# ============================================================
# OUVERTURE / FERMETURE
# ============================================================
func open() -> void:
	AudioManager.push_pause_music()
	show()
	get_focus()


func close() -> void:
	AudioManager.pop_pause_music()
	hide()


# ============================================================
# BOUTONS
# ============================================================
func _on_resume_pressed() -> void:
	close()
	resume_pressed.emit()


func _on_quit_pressed() -> void:
	close()
	quit_pressed.emit()


func _on_controls_pressed() -> void:
	controls_pressed.emit()


func _on_main_menu_pressed() -> void:
	close()
	main_menu_pressed.emit()
