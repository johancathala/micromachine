class_name PlayerConfig
extends RefCounted

var player_id: int = 0
var nickname: String = ""

var device_type: String = ""
var device_id: int = -1

var control_profile_id: String = ""

var car_id: String = ""
var color_id: String = ""

func is_keyboard() -> bool:
	return device_type == "keyboard"

func is_gamepad() -> bool:
	return device_type == "gamepad"
