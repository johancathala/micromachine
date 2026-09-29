extends Node2D
class_name CarModel

@onready var body: Node2D = $Body
@onready var sprite: AnimatedSprite2D = $Body/AnimatedSprite2D


func set_color(color: Color) -> void:
	body.modulate = color


func get_sprite() -> AnimatedSprite2D:
	return sprite
