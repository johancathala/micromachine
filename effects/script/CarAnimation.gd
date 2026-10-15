
extends Node2D
class_name CarAnimation

@export var animation_name: StringName = &"explosion"

@onready var animation_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var animation_audio: AudioStreamPlayer2D = $AudioStreamPlayer2D

var _animation_done := false
var _audio_done := true


func play_animation() -> void:
	animation_sprite.animation = animation_name
	_start_animation()
	_start_audio()
	_try_free()


func _start_animation() -> void:
	if animation_sprite.sprite_frames == null:
		push_warning("CarExplosion : aucune ressource SpriteFrames.")
		_animation_done = true
		return

	if not animation_sprite.sprite_frames.has_animation(animation_name):
		push_warning(
			"CarExplosion : animation introuvable : "
			+ String(animation_name)
		)
		animation_sprite.hide()
		_animation_done = true
		return

	animation_sprite.animation_finished.connect(
		_on_animation_finished
	)

	animation_sprite.play(animation_name)


func _start_audio() -> void:
	if animation_audio.stream == null:
		_audio_done = true
		return

	_audio_done = false
	animation_audio.finished.connect(_on_audio_finished)
	animation_audio.play()


func _on_animation_finished() -> void:
	_animation_done = true
	animation_sprite.hide()
	_try_free()


func _on_audio_finished() -> void:
	_audio_done = true
	_try_free()


func _try_free() -> void:
	if _animation_done and _audio_done:
		queue_free()
