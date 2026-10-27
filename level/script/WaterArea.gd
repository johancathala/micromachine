extends Area2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var car := body as Car

	if car == null:
		return
		
	if car._destruction_started  or car._respawning:
		return
	
	car.sink_in_water()
