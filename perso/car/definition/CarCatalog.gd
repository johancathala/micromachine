extends Node
class_name CarCatalog


# Du moins puissant au plus puissant : une voiture d'un groupe plus
# élevé ne doit pas affronter une voiture d'un groupe plus bas.
const GROUP_ORDER := ["D", "C", "B", "A", "S"]

# Ordre d'affichage : par groupe, puis par modèle.
const CARS: Array[CarDefinition] = [
	preload("res://perso/car/definition/SaxoBic.tres"),
	preload("res://perso/car/definition/Clio.tres"),
	preload("res://perso/car/definition/Dacia.tres"),
	preload("res://perso/car/definition/Laguna.tres"),
	preload("res://perso/car/definition/ClioPrepa.tres"),
	preload("res://perso/car/definition/Pompier.tres"),
	preload("res://perso/car/definition/Poubelle.tres"),
	preload("res://perso/car/definition/BMW.tres"),
	preload("res://perso/car/definition/GTI.tres"),
	preload("res://perso/car/definition/Police.tres"),
	preload("res://perso/car/definition/Ferrari.tres"),
	preload("res://perso/car/definition/Porche.tres"),
	preload("res://perso/car/definition/MacLaren.tres"),
	preload("res://perso/car/definition/F1.tres"),
]


static func get_cars() -> Array[CarDefinition]:
	return CARS.duplicate()


static func get_car(car_id: String) -> CarDefinition:
	var car := _find_car(car_id)

	if car == null:
		push_warning("CarDefinition introuvable : " + car_id)

	return car


static func has_car(car_id: String) -> bool:
	return _find_car(car_id) != null


## Rang d'un groupe (0 = D, 4 = S) ; -1 si le groupe est inconnu.
static func group_rank(group: String) -> int:
	return GROUP_ORDER.find(group)


## Voitures d'un groupe, dans l'ordre du catalogue.
static func get_cars_in_group(group: String) -> Array[CarDefinition]:
	var result: Array[CarDefinition] = []

	for car in CARS:
		if car.group == group:
			result.append(car)

	return result


## Groupe le plus élevé parmi ces voitures (D si aucune n'est valide).
static func highest_group(car_ids: Array) -> String:
	var best := GROUP_ORDER[0]
	var best_rank := -1

	for car_id in car_ids:
		var car := _find_car(String(car_id))

		if car == null:
			continue

		var rank := group_rank(car.group)

		if rank > best_rank:
			best = car.group
			best_rank = rank

	return best


static func _find_car(car_id: String) -> CarDefinition:
	for car: CarDefinition in CARS:
		if car.id == car_id:
			return car

	return null
