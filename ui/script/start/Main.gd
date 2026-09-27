extends Control

@onready var navigation_layer: Control = $NavigationLayer

func _ready() -> void:
	NavigationManager.setup(navigation_layer)
	
	NavigationManager.go_to("res://ui/scene/StartupScreen.tscn",
	false
	)
