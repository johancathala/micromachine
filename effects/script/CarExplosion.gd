
extends Node2D
class_name CarExplosion

@export var animation_name: StringName = &"explosion"

@onready var explosion_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var explosion_audio: AudioStreamPlayer2D = $AudioStreamPlayer2D

var _animation_done := false
var _audio_done := true


func _ready() -> void:
	_start_animation()
	_start_audio()
	_try_free()


func _start_animation() -> void:
	if explosion_sprite.sprite_frames == null:
		push_warning("CarExplosion : aucune ressource SpriteFrames.")
		_animation_done = true
		return

	if not explosion_sprite.sprite_frames.has_animation(animation_name):
		push_warning(
			"CarExplosion : animation introuvable : "
			+ String(animation_name)
		)
		explosion_sprite.hide()
		_animation_done = true
		return

	explosion_sprite.animation_finished.connect(
		_on_animation_finished
	)

	explosion_sprite.play(animation_name)


func _start_audio() -> void:
	if explosion_audio.stream == null:
		_audio_done = true
		return

	_audio_done = false
	explosion_audio.finished.connect(_on_audio_finished)
	explosion_audio.play()


func _on_animation_finished() -> void:
	_animation_done = true
	explosion_sprite.hide()
	_try_free()


func _on_audio_finished() -> void:
	_audio_done = true
	_try_free()


func _try_free() -> void:
	if _animation_done and _audio_done:
		queue_free()
