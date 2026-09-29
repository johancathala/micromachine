extends Control

const RACE_WORLD_SCENE := preload(
    "res://level/Scene/RaceWorld.tscn"
)

var race_config: RaceConfig

@onready var race_world: Node2D = $RaceWorld


func _ready() -> void:
	race_config = GameManager.get_active_race_config()

	if race_config == null:
		push_error("Race : aucune configuration de course active.")
		return
	
	var instance_scene = RACE_WORLD_SCENE.instantiate()
	$RaceWorld.add_child(instance_scene)
