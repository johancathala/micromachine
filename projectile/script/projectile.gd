extends Area2D
class_name Projectile

@export var speed = 400.0
@onready var direction := Vector2.RIGHT.rotated(rotation)

func _ready() -> void:
	$SoundFire.play()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var velocity = direction * speed * delta
	global_position += velocity


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("Player"):
		area.destroy()
		queue_free()
