extends Node
class_name CarCatalog


const CARS: Array[CarDefinition] = [
	preload("res://perso/car/definition/Clio.tres"),
	preload("res://perso/car/definition/Dacia.tres"),
	preload("res://perso/car/definition/Ferrari.tres"),
]


static func get_cars() -> Array[CarDefinition]:
	return CARS.duplicate()


static func get_car(car_id: String) -> CarDefinition:
	for car: CarDefinition in CARS:
		if car.id == car_id:
			return car

	push_warning("CarDefinition introuvable : " + car_id)
	return null


static func has_car(car_id: String) -> bool:
	return get_car(car_id) != null
