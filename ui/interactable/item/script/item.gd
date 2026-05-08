@tool
extends Node2D

@export var item_data: ItemData:
	set(value):
		_item_data = value
		if Engine.is_editor_hint():
			_apply_visual(value)
	get:
		return _item_data

var _item_data: ItemData

@onready var sprite: Sprite2D = $Sprite2D
@onready var pickUpArea: Area2D = $PickUpArea2D
@onready var interactable: Area2D = $Interactable

func _ready() -> void:
	# C'est pour éviter que le script genere des erreurs inutiles lorsqu'on ouvre le projet dans l'éditeur de Godot.
	if Engine.is_editor_hint():
		return
	
	_on_item_data_assigned(_item_data)

func _on_item_data_assigned(data: ItemData) -> void:
	if not data:
		printerr("Error : this item has no data !") 
		return
	_apply_visual(data)
	_apply_components(data)

func _enable_interact(area : Area2D, on: bool, data: ItemData) -> void:
	_enable_area(area, on)
	
	# On dit au système d'interaction si cette zone est active ou pas
	interactable.is_interactable = on
	
	if not on:
		# Pas interactif : on vide le texte et on met une action "vide"
		interactable.interact_name = ""
		interactable.interact = func() -> void:
			pass
		return
	
	# Choix du texte d'interaction en fonction du type d'item
	match data.item_type:
		Enums.ItemType.NOTE:
			interactable.interact_name = "Lire " + data.display_name
		_:
			interactable.interact_name = "Interagir avec " + data.display_name
	
	# On branche l'action commune : _on_interact
	interactable.interact = _on_interact
	
func _enable_area(area : Area2D, on : bool):
	area.visible = on
	area.monitoring = on
	_set_shapes_disabled(area, !on)

func _set_shapes_disabled(node: Node, disabled: bool):
	for shape in node.get_children():
		if shape is CollisionShape2D: shape.disabled = disabled

# ---------------- VISUEL ----------------
func _apply_visual(data: ItemData) -> void:
	if sprite and data.texture:
		sprite.texture = data.texture
		sprite.scale = data.texture_scale

## ---------------- COMPONENTS (diff + unique key) ----------------
func _apply_components(data: ItemData) -> void:
	_enable_interact(interactable, data.can_interact, data)
	_enable_area(pickUpArea, data.can_be_picked)	

### On dispatch selon le type d'item
func _on_interact() -> void: 
	if not _item_data:
		return
	
	match _item_data.item_type:
		Enums.ItemType.NOTE:
			_interact_note()
		_:
			print("Interacting with ", _item_data.display_name)

func _interact_note() -> void:
	if _item_data.description == "":
		print("Ce parchemin est vide…")
		return
	
	UIManager.show_popup(
		_item_data.display_name,
		_item_data.description,
		PopupMessage.PositionMode.CENTER,
		PopupMessage.TextMode.TYPEWRITER
	)

func _on_pick_up_area_2d_body_entered(body: Node2D) -> void:
	if not _item_data.can_be_picked:
		return
	if not body.is_in_group("Player"):
		return
	
	var picked_up = false
	match _item_data.item_type:
		Enums.ItemType.CARD:
			picked_up = InventoryManager.cards.add_item(_item_data)
		_:
			picked_up = InventoryManager.items.add_item(_item_data)
	if not picked_up:
		return
	
	queue_free()
