extends RefCounted
class_name CarCatalog


const CARS := [
	{
		"id": "car_01",
		"name": "Rocket",
		"description": "Rapide et nerveuse."
	},
	{
		"id": "car_02",
		"name": "Bulldog",
		"description": "Lourde mais très stable."
	},
	{
		"id": "car_03",
		"name": "Flash",
		"description": "Très bonne accélération."
	},
	{
		"id": "car_04",
		"name": "Mini",
		"description": "Agile et facile à contrôler."
	}
]


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


static func get_cars() -> Array:
	return CARS.duplicate(true)


static func get_colors() -> Array:
	return COLORS.duplicate(true)


static func get_car(car_id: String) -> Dictionary:
	for car in CARS:
		if car.id == car_id:
			return car

	return {}


static func get_color(color_id: String) -> Dictionary:
	for color in COLORS:
		if color.id == color_id:
			return color

	return {}
