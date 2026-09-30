extends Node2D
class_name RaceWorld

signal move_car(can_move: bool)

@onready var track_root: Node2D = $Track
@onready var spawn_points: Node2D = $SpawnPoints
@onready var cars_root: Node2D = $Cars
@onready var skid_marks: Node2D = $SkidMarks
@onready var race_camera: Camera2D = $RaceCamera

var section: Node2D
var light_start: Node2D

var all_section : Array[Node]
var valid_section: Array[bool]

func clear_track() -> void:
	for child in track_root.get_children():
		child.queue_free()


func load_track(track_scene: PackedScene) -> Node2D:
	clear_track()

	if track_scene == null:
		push_error("RaceWorld : scène de circuit invalide.")
		return null

	var track := track_scene.instantiate() as Node2D

	if track == null:
		push_error("RaceWorld : le circuit doit avoir un Node2D comme racine.")
		return null

	track_root.add_child(track)

	return track


func get_spawn_point(index: int) -> Marker2D:
	if index < 0 or index >= spawn_points.get_child_count():
		return null

	return spawn_points.get_child(index) as Marker2D


func clear_cars() -> void:
	for child in cars_root.get_children():
		child.queue_free()


func add_car(car: Node2D) -> void:
	cars_root.add_child(car)

func get_cars_root() -> Node2D:
	return cars_root

func get_skid_marks() -> Node2D:
	return skid_marks
