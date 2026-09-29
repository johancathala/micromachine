extends Resource
class_name CarDefinition

@export_category("Identification")

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""


@export_category("Visual")

@export var model_scene: PackedScene
@export var preview_texture: Texture2D


@export_category("Performance")

@export_range(0.0, 5000.0, 1.0)
var engine_force: float = 1300.0

@export_range(0.0, 5000.0, 1.0)
var brake_force: float = 1700.0

@export_range(0.0, 2000.0, 1.0)
var reverse_force: float = 900.0

@export_range(0.0, 3000.0, 1.0)
var max_speed: float = 2000.0

@export_range(0.0, 1000.0, 1.0)
var max_reverse_speed: float = 450.0


@export_category("Resistance")

@export_range(0.0, 1000.0, 1.0)
var rolling_resistance: float = 140.0

@export_range(0.0, 0.01, 0.0001)
var air_drag: float = 0.0009


@export_category("Grip")

@export_range(0.0, 50.0, 0.1)
var lateral_grip: float = 10.0

@export_range(0.0, 50.0, 0.1)
var lateral_grip_at_high_speed: float = 2.0

@export_range(0.0, 3000.0, 1.0)
var high_speed_grip_start: float = 300.0

@export_range(0.0, 3000.0, 1.0)
var high_speed_grip_end: float = 1600.0


@export_category("Steering")

@export_range(0.0, 1.5708, 0.01)
var max_steer_angle: float = deg_to_rad(35.0)

@export_range(0.0, 20.0, 0.1)
var steer_speed: float = 4.0

@export_range(0.0, 20.0, 0.1)
var steer_return_speed: float = 6.0

@export_range(0.0, 5.0, 0.01)
var steering_response_low_speed: float = 1.0

@export_range(0.0, 5.0, 0.01)
var steering_response_high_speed: float = 0.45

@export_range(0.0, 3000.0, 1.0)
var steering_high_speed_start: float = 300.0

@export_range(0.0, 3000.0, 1.0)
var steering_high_speed_end: float = 1600.0


@export_category("Chassis")

@export_range(0.0, 200.0, 0.1)
var wheel_base: float = 62.0

@export_range(0.0, 200.0, 0.1)
var wheel_spacing: float = 18.0

@export_range(0.0, 200.0, 0.1)
var min_speed_for_steer: float = 30.0


@export_category("Handbrake")

@export_range(0.0, 1.0, 0.01)
var handbrake_grip_multiplier: float = 0.05

@export_range(0.0, 1.0, 0.01)
var handbrake_brake_multiplier: float = 0.4


@export_category("Camera")

@export_range(0.1, 4.0, 0.1)
var camera_zoom_min: float = 0.3

@export_range(0.1, 4.0, 0.1)
var camera_zoom_max: float = 1.8

@export_range(0.1, 1.0, 0.01)
var camera_zoom_speed: float = 0.3
