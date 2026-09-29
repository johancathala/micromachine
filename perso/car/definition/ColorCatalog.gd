extends Node
class_name ColorCatalog


const COLORS := [
	{
		"id": "red",
		"name": "Rouge",
		"color": Color("#e53935")
	},
	{
		"id": "blue",
		"name": "Bleu",
		"color": Color("#1e88e5")
	},
	{
		"id": "green",
		"name": "Vert",
		"color": Color("#43a047")
	},
	{
		"id": "yellow",
		"name": "Jaune",
		"color": Color("#fdd835")
	},
	{
		"id": "orange",
		"name": "Orange",
		"color": Color("#fb8c00")
	},
	{
		"id": "purple",
		"name": "Violet",
		"color": Color("#8e24aa")
	},
	{
		"id": "cyan",
		"name": "Cyan",
		"color": Color("#00acc1")
	},
	{
		"id": "white",
		"name": "Blanc",
		"color": Color("#eeeeee")
	}
]


static func get_colors() -> Array:
	return COLORS.duplicate(true)


static func get_color(color_id: String) -> Dictionary:
	for color_data: Dictionary in COLORS:
		if color_data["id"] == color_id:
			return color_data.duplicate(true)

	push_warning("Couleur introuvable : " + color_id)
	return {}


static func has_color(color_id: String) -> bool:
	return not get_color(color_id).is_empty()
