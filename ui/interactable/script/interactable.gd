extends Area2D
class_name Interactable

@export var interact_name: String = "Interagir"
@export var is_interactable: bool = true
@export var priority_interaction: int = 0

var interact: Callable = Callable()
