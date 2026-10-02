extends RefCounted
class_name PlayerInputState

var throttle: float = 0.0
var brake: float = 0.0
var steering: float = 0.0

var handbrake: bool = false
var respawn: bool = false


func reset() -> void:
	throttle = 0.0
	brake = 0.0
	steering = 0.0
	handbrake = false
	respawn = false
