extends Control


const CAR_SCENE := preload("res://perso/car/car.tscn")


const TRACK_SCENES := {
	"track_01": "res://level/track/Track01.tscn",
	"track_02": "res://level/track/Track02.tscn",
	"track_03": "res://level/track/Track03.tscn",
	"track_reverse": "res://level/track/TrackReverse.tscn",
}


var race_config: RaceConfig


@onready var race_world: Node2D = $RaceWorld


func _ready() -> void:
	race_config = GameManager.get_active_race_config()

	if race_config == null:
		push_error("Race : aucune configuration active.")
		return

	_initialize_race()


func _initialize_race() -> void:
	_load_track()
	_spawn_cars()

	# Pour cette étape, les voitures sont créées mais
	# leur pilotage sera activé par le système de course.
	_set_cars_can_move(false)


func _load_track() -> void:
	var track_id := race_config.track_id

	if not TRACK_SCENES.has(track_id):
		push_error(
			"Race : aucun circuit associé à '%s'."
			% track_id
		)
		return

	var track_scene := load(TRACK_SCENES[track_id]) as PackedScene

	if track_scene == null:
		push_error(
			"Race : impossible de charger le circuit '%s'."
			% TRACK_SCENES[track_id]
		)
		return

	race_world.load_track(track_scene)


func _spawn_cars() -> void:
	race_world.clear_cars()

	var participants := race_config.participants

	if participants.size() != RaceConfig.TOTAL_RACE_SLOTS:
		push_error(
			"Race : %d participants reçus, 8 attendus."
			% participants.size()
		)
		return

	for index in range(participants.size()):
		_spawn_participant(
			participants[index],
			index
		)


func _spawn_participant(
	participant: Dictionary,
	spawn_index: int
) -> void:

	var car_definition := CarCatalog.get_car(
		String(participant.get("car_id", ""))
	)

	if car_definition == null:
		push_error(
			"Race : voiture introuvable pour participant %d."
			% spawn_index
		)
		return

	var color_data := ColorCatalog.get_color(
		String(participant.get("color_id", ""))
	)

	if color_data.is_empty():
		push_error(
			"Race : couleur introuvable pour participant %d."
			% spawn_index
		)
		return

	var car := CAR_SCENE.instantiate() as Car

	if car == null:
		push_error("Race : car.tscn n'utilise pas le script Car.")
		return

	race_world.add_car(car)

	var spawn : Marker2D = race_world.get_spawn_point(spawn_index)

	if spawn != null:
		car.global_position = spawn.global_position
		car.global_rotation = spawn.global_rotation

	car.setup_car(
		car_definition,
		color_data["color"],
		int(participant.get("participant_id", spawn_index)),
		bool(participant.get("is_ai", false)),
		String(participant.get("device_type", "")),
		int(participant.get("device_id", -1)),
		race_world.get_skid_marks()
	)


func _set_cars_can_move(can_move: bool) -> void:
	for child in race_world.get_cars_root().get_children():
		var car := child as Car

		if car != null:
			car.set_can_move(can_move)
