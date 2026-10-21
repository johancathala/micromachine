
extends CanvasLayer

@onready var sprites: AnimatedSprite2D = $CenterContainer/Control/AnimatedSprite2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	sprites.process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	sprites.stop()


func show_loading() -> void:
	sprites.play()
	show()


func hide_loading() -> void:
	hide()
	sprites.stop()
