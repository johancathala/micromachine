
extends Node2D
class_name CarAnimation

signal effect_finished

@export var animation_name: StringName = &"explosion"
@export var audio_explosion: AudioStream
@export var audio_sink: AudioStream

@onready var animation_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var animation_audio: AudioStreamPlayer2D = $AudioStreamPlayer2D

var _animation_done := false
var _audio_done := true
var _started := false
var _effect_finished_emitted := false


func set_animation(animation: StringName = "explosion") -> void:
	animation_name = animation

	match animation:
		&"explosion":
			animation_audio.stream = audio_explosion
		&"sink":
			animation_audio.stream = audio_sink
		_:
			push_warning(
				"CarAnimation : type d'effet inconnu : "
				+ String(animation)
			)


func play_animation(animation: StringName = "explosion") -> void:
	if _started:
		push_warning("CarAnimation : effet déjà démarré.")
		return

	_started = true
	_animation_done = false
	_audio_done = true
	_effect_finished_emitted = false

	set_animation(animation)

	print(
		"CarAnimation : démarrage de l'effet ",
		animation_name
	)

	_start_animation()
	_start_audio()
	_try_finish_effect()


func _start_animation() -> void:
	if animation_sprite.sprite_frames == null:
		push_error("CarAnimation : aucune ressource SpriteFrames.")
		_animation_done = true
		return

	if not animation_sprite.sprite_frames.has_animation(animation_name):
		push_error(
			"CarAnimation : animation introuvable : ",
			animation_name
		)
		animation_sprite.hide()
		_animation_done = true
		return

	# L'animation doit être non bouclée pour émettre
	# animation_finished à la fin de sa lecture.
	if animation_sprite.sprite_frames.get_animation_loop(animation_name):
		push_warning(
			"CarAnimation : l'animation '%s' boucle. "
			% animation_name
			+ "Désactive Loop dans SpriteFrames."
		)

	if not animation_sprite.animation_finished.is_connected(
		_on_animation_finished
	):
		animation_sprite.animation_finished.connect(
			_on_animation_finished
		)

	animation_sprite.animation = animation_name
	animation_sprite.show()
	animation_sprite.play()


func _start_audio() -> void:
	if animation_audio.stream == null:
		print("CarAnimation : aucun son, attente de l'animation seulement.")
		_audio_done = true
		return

	_audio_done = false

	if not animation_audio.finished.is_connected(
		_on_audio_finished
	):
		animation_audio.finished.connect(_on_audio_finished)

	animation_audio.play()


func _on_animation_finished() -> void:
	print("CarAnimation : animation terminée.")

	_animation_done = true
	animation_sprite.hide()

	_try_finish_effect()


func _on_audio_finished() -> void:
	print("CarAnimation : son terminé.")

	_audio_done = true

	_try_finish_effect()


func _try_finish_effect() -> void:
	if _effect_finished_emitted:
		return

	if not _animation_done or not _audio_done:
		return

	_effect_finished_emitted = true

	print("CarAnimation : émission de effect_finished.")

	effect_finished.emit()
	queue_free()
