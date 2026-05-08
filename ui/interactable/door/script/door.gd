extends Node2D

@export var next_scene: String = ""
@export var key_id: String = "" # vide = pas de clé requise

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var door_collider: CollisionShape2D = $StaticBody2D/CollisionShape2D

var door_open := false

func _on_activate_door_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	# Si une clé est requise, on vérifie l'inventaire (ajouté plus bas)
	if key_id != "" and not InventoryManager.items.has_item_by_id(key_id):
		# Ici tu peux jouer un son "locked"
		return
	if not door_open:
		if animated_sprite_2d.sprite_frames and animated_sprite_2d.sprite_frames.has_animation("open"):
			animated_sprite_2d.play("open")
		door_open = true
		door_collider.set_deferred("disabled", true) # libère le passage

func _on_activate_door_area_body_exited(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	if door_open:
		if animated_sprite_2d.sprite_frames and animated_sprite_2d.sprite_frames.has_animation("close"):
			animated_sprite_2d.play("close")
		door_open = false
		door_collider.set_deferred("disabled", false) # re-bloque la porte

func _on_exit_area_body_entered(body: Node2D) -> void:
	if not door_open:
		return
	if not body.is_in_group("Player"):
		return
	await get_tree().create_timer(0.05).timeout
	SceneManager.transition_to_scene(next_scene)
