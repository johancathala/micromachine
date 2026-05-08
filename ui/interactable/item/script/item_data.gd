extends Resource
class_name ItemData

@export_category("Identity")
@export var id: StringName
@export var item_type: Enums.ItemType = Enums.ItemType.NONE
@export var display_name: String
@export var description : String

@export_category("Visual")
@export var icon: Texture2D
@export var texture: Texture2D
@export var texture_scale : Vector2 = Vector2.ONE
@export var modulate: Color = Color.WHITE

@export_category("Properties")
@export var can_interact := false
@export var can_be_picked := false
@export var is_static_body := false
@export var can_be_pushed := false
@export var can_be_grabbed := false
@export var can_be_possessed := false
@export var can_shrink := false
@export var is_invisible := false
@export var can_fly := false
@export var weight := 0
@export var default_flight_altitude := 16.0
@export var rise_speed := 64.0
@export var fall_speed := 96.0
@export var max_stack_size := 1
