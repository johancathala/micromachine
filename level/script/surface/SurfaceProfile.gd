extends RefCounted
class_name SurfaceProfile


var name: String

# Influence sur la physique
var grip_mul: float
var rolling_mul: float
var engine_mul: float
var brake_mul: float

# Effets visuels
var skid_color: Color
var smoke_color: Color

# Effets sonores
var sound_volume: float
var sound_scale: float


func _init(
	_name: String,
	_grip_mul: float,
	_rolling_mul: float,
	_engine_mul: float,
	_brake_mul: float,
	_skid_color: Color,
	_smoke_color: Color,
	_sound_volume: float,
	_sound_scale: float
) -> void:
	name = _name

	grip_mul = _grip_mul
	rolling_mul = _rolling_mul
	engine_mul = _engine_mul
	brake_mul = _brake_mul

	skid_color = _skid_color
	smoke_color = _smoke_color

	sound_volume = _sound_volume
	sound_scale = _sound_scale
