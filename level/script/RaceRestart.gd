extends Control


@onready var title_label: Label = (
	$MarginContainer/VBoxContainer/Title
)


func _ready() -> void:
	restart()


func restart() -> void:

	if not GameManager.restart_active_race():
		return

	NavigationManager.go("Race")
