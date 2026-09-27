extends Node2D

signal move_car(can_move: bool)

var section: Node2D
var light_start: Node2D

var all_section : Array[Node]
var valid_section: Array[bool]

func _on_start_level() -> void:
	move_car.emit(true)
	var all_light : Array[Node] = light_start.get_children()
	for light:AnimatedSprite2D in all_light:
		light.set_frame(1)

func _on_ready_level() -> void:
	move_car.emit(false)
	light_start = %FeuDepartLevel
	var all_light : Array[Node] = light_start.get_children()
	for light:AnimatedSprite2D in all_light:
		light.set_frame(0)
	section = %Section
	all_section = section.get_children()
	for s:Area2D in all_section:
		s.valid_section = false
		valid_section.append(false)
