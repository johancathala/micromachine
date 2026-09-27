extends Node

var navigation_layer: Control
var current_screen: Control
var history: Array[String] = []

func setup(layer: Control) -> void:
	navigation_layer = layer

func go_to(scene_path: String, add_to_history: bool = true) -> void:
	if navigation_layer == null:
		push_error("NavigationManager: navigation layer non configuré.")
		return

	if add_to_history and current_screen != null:
		history.append(current_screen.scene_file_path)

	if current_screen != null:
		current_screen.queue_free()
		current_screen = null

	var scene: PackedScene = load(scene_path)

	if scene == null:
		push_error("Impossible de charger la scène : " + scene_path)
		return

	current_screen = scene.instantiate() as Control

	if current_screen == null:
		push_error("La scène doit avoir un Control comme racine : " + scene_path)
		return

	navigation_layer.add_child(current_screen)

func go_back() -> void:
	if history.is_empty():
		return

	var previous_scene: String = history.pop_back()
	go_to(previous_scene, false)

func clear_history() -> void:
	history.clear()
