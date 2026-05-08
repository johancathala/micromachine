extends Area2D

signal detect_car(id_section: int, tab_section: Array[Area2D])
var valid_section: bool = false
var time: float = 0.0


func _on_body_entered(body: Node2D) -> void:
	if body.get_class() == "CharacterBody2D":
		var id: int = int(get_name())
		var node_section: Node2D = get_parent()
		var all_section: Array[Node] = node_section.get_children()
		detect_car.emit(id,all_section)
	
	
