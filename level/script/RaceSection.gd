extends Area2D
class_name RaceSection


# ============================================================
# CONFIGURATION
# ============================================================

@export var section_id: int = 0


# ============================================================
# INITIALISATION
# ============================================================

func _ready() -> void:

	body_entered.connect(
		_on_body_entered
	)


# ============================================================
# DÉTECTION D'UNE VOITURE
# ============================================================

func _on_body_entered(body: Node2D) -> void:

	if not body is Car:
		return

	var car := body as Car

	var controller := _get_race_controller()

	if controller == null:
		push_error("RaceSection %d : RaceController introuvable." % section_id)
		return

	controller.on_car_entered_section(
		car,
		section_id
	)


# ============================================================
# RECHERCHE DU RACE CONTROLLER
# ============================================================
func _get_race_controller() -> RaceController:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return null

	return current_scene.find_child(
		"RaceController",
		true,
		false
	) as RaceController
