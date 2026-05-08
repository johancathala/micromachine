extends Node

const SCENES := {
	"Level1": "res://level/scene/level1.tscn",
	"Level2": "res://level/scene/level2.tscn",
}

func transition_to_scene(level: String) -> void:
	var scene_path = SCENES.get(level, null)
	if scene_path == null:
		push_warning("Scene id '%s' introuvable dans SCENES." % level)
		return
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file(scene_path)
