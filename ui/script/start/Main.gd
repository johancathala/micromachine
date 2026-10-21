extends Control

@onready var navigation_layer: Control = $NavigationLayer
@onready var transition_layer: CanvasLayer = $TransitionLayer

func _ready() -> void:
	NavigationManager.setup(navigation_layer, transition_layer)
	#NavigationManager.setup(self)
	
	NavigationManager.go("StartupScreen",false)
