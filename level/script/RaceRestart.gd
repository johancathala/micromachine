extends Control


@onready var title_label: Label = (
	$MarginContainer/VBoxContainer/Title
)


func _ready() -> void:
	get_tree().paused = false
	restart()


func restart() -> void:
	
	GameManager.clear_result_race()
	
	var race_config = GameManager.get_active_race_config()
	
	GameManager.clear_active_race()
	
	GameManager.set_active_race_config(race_config)
	
	#set_pending_race_config(config: RaceConfig)
	
	GameManager.prepare_race_setup()
	
	if not GameManager.start_race():
		return


	NavigationManager.go("Race")
