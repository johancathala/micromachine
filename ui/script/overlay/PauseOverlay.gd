extends Control
class_name PauseOverlay


# ============================================================
# SIGNAUX
# ============================================================

signal resume_pressed
signal restart_pressed
signal controls_pressed
signal main_menu_pressed


# ============================================================
# NŒUDS
# ============================================================

@onready var resume_button: Button = $MarginContainer/PanelContainer/VBoxContainer/ResumeButton
@onready var restart_button: Button = $MarginContainer/PanelContainer/VBoxContainer/RestartButton
@onready var controls_button: Button = $MarginContainer/PanelContainer/VBoxContainer/ControlsButton
@onready var main_menu_button: Button = $MarginContainer/PanelContainer/VBoxContainer/MainMenuButton


# ============================================================
# INITIALISATION
# ============================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)

	hide()


# ============================================================
# OUVERTURE / FERMETURE
# ============================================================

func open() -> void:
	show()

	resume_button.grab_focus()


func close() -> void:
	hide()


# ============================================================
# BOUTONS
# ============================================================

func _on_resume_pressed() -> void:
	resume_pressed.emit()


func _on_restart_pressed() -> void:
	restart_pressed.emit()


func _on_controls_pressed() -> void:
	controls_pressed.emit()


func _on_main_menu_pressed() -> void:
	main_menu_pressed.emit()
