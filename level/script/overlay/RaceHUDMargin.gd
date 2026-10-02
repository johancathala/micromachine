extends MarginContainer

var valeur_marge_x = 100
var valeur_marge_y = 50

func _ready() -> void:
	add_theme_constant_override("margin_top", valeur_marge_y)
	add_theme_constant_override("margin_left", valeur_marge_x)
	add_theme_constant_override("margin_bottom", valeur_marge_y)
	add_theme_constant_override("margin_right", valeur_marge_x)
