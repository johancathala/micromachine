extends Node2D

@onready var interact_label: Label = $Label
var _player_origin: Node2D
var _detected_interactables : Array[Interactable] = []
var _current: Interactable = null

func _ready() -> void:
	_player_origin = get_parent() as Node2D
	
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _current:
		if _current.is_interactable and _current.interact.is_valid():
			_current.interact.call()
		_update_current_target() # au cas où l'interaction change l'état/priority

func _process(_delta: float) -> void:
	_clean_detected_interactables()
	_update_current_target()

func _update_current_target() -> void:
	if _player_origin == null or _detected_interactables.is_empty():
		_set_current_target(null)
		return

	var origin_pos: Vector2 = _player_origin.global_position

	var best: Interactable = null
	var best_priority: int = 0
	var best_dist_sq: float = 0.0

	for interactable in _detected_interactables:
		if not interactable.is_interactable:
			continue

		var dist_sq = origin_pos.distance_squared_to(interactable.global_position)
		
		if best == null:
			best = interactable
			best_priority = interactable.priority_interaction
			best_dist_sq = dist_sq
			continue
		
		var priority = interactable.priority_interaction
		# 1) plus haute priorité
		# 2) à priorité égale, le plus proche
		if priority > best_priority or (priority == best_priority and dist_sq < best_dist_sq):
			best = interactable
			best_priority = priority
			best_dist_sq = dist_sq
	
	_set_current_target(best)


func _update_ui() -> void:
	if _current and _current.is_interactable and _current.interact_name.strip_edges() != "":
		interact_label.text = _current.interact_name
		interact_label.show()
	else:
		interact_label.hide()

func _on_interact_range_area_entered(area: Area2D) -> void:
	if area is Interactable:
		var interactable = area as Interactable
		if not _detected_interactables.has(interactable):
			_detected_interactables.append(interactable)

func _on_interact_range_area_exited(area: Area2D) -> void:
	if area is Interactable:
		var interactable = area as Interactable
		_detected_interactables.erase(interactable)
		if _current == interactable:
			_set_current_target(null)

func _clean_detected_interactables() -> void:
	for i in range(_detected_interactables.size() - 1, -1, -1):
		var interactable = _detected_interactables[i]
		if interactable == null or not is_instance_valid(interactable) or not interactable.is_inside_tree():
			_detected_interactables.remove_at(i)

func _set_current_target(new_target: Interactable) -> void:
	if _current == new_target:
		return

	_current = new_target
	_update_ui()
