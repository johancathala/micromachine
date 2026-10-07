extends Control
class_name RaceStartLight


enum LightState {
	ORANGE,
	RED,
	GREEN
}


@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var current_state: LightState = LightState.ORANGE


func _ready() -> void:
	sprite.pause()
	set_orange()


func set_orange() -> void:
	current_state = LightState.ORANGE
	sprite.animation = &"default"
	sprite.frame = 0
	sprite.pause()


func set_red() -> void:
	current_state = LightState.RED
	sprite.animation = &"default"
	sprite.frame = 1
	sprite.pause()
	print("FEU -> ROUGE : ", name)


func set_green() -> void:
	current_state = LightState.GREEN
	sprite.animation = &"default"
	sprite.frame = 2
	sprite.pause()
	print("FEU -> VERT : ", name)


func get_state() -> LightState:
	return current_state
