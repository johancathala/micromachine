extends Control

const CAR_SCENE := preload("res://perso/car/car.tscn")

const TRACK_SCENES := {
	"track_01": "res://level/track/Track01.tscn",
	"track_02": "res://level/track/Track02.tscn",
	"track_03": "res://level/track/Track03.tscn",
	"track_reverse": "res://level/track/TrackReverse.tscn",
}

@onready var race_world: RaceWorld = $RaceWorld
@onready var race_controller: RaceController = $RaceController
@onready var race_hud: RaceHUD = $HUDLayer/HUD

var race_config: RaceConfig = null


func _ready() -> void:
	race_config = GameManager.get_active_race_config()

	if race_config == null:
		push_error("Race : aucune configuration de course active.")
		return

	_initialize_race()


func _initialize_race() -> void:
	if not _load_track():
		return

	if not _spawn_cars():
		return

	_initialize_camera()

	race_controller.initialize(race_config, race_world)

	race_hud.initialize(race_controller, race_world)

	# Les voitures restent bloquées tant que le compte à rebours
	# n'est pas terminé.
	race_controller.start_countdown()


func _load_track() -> bool:
	var track_id := race_config.track_id

	if not TRACK_SCENES.has(track_id):
		push_error(
			"Race : aucun circuit associé à l'identifiant '%s'."
			% track_id
		)
		return false

	var track_path: String = TRACK_SCENES[track_id]
	var track_scene := load(track_path) as PackedScene

	if track_scene == null:
		push_error(
			"Race : impossible de charger le circuit '%s'."
			% track_path
		)
		return false

	var track := race_world.load_track(track_scene)

	if track == null:
		push_error("Race : échec du chargement du circuit.")
		return false

	return true


func _spawn_cars() -> bool:
	race_world.clear_cars()

	var participants := race_config.get_active_participants()

	if participants.is_empty():
		push_error("Race : aucun participant actif.")
		return false

	if participants.size() > RaceConfig.TOTAL_RACE_SLOTS:
		push_error(
			"Race : %d participants actifs, maximum %d."
			% [
				participants.size(),
				RaceConfig.TOTAL_RACE_SLOTS
			]
		)
		return false

	for spawn_index in range(participants.size()):
		var participant: Dictionary = participants[spawn_index]

		if not _spawn_participant(participant, spawn_index):
			return false

	return true


func _spawn_participant(
	participant: Dictionary,
	spawn_index: int
) -> bool:

	var participant_id := int(
		participant.get("participant_id", spawn_index)
	)

	var car_id := String(
		participant.get("car_id", "")
	)

	var color_id := String(
		participant.get("color_id", "")
	)

	var car_definition := CarCatalog.get_car(car_id)

	if car_definition == null:
		push_error(
			"Race : voiture inconnue '%s' pour le participant %d."
			% [car_id, participant_id]
		)
		return false

	var color_data := ColorCatalog.get_color(color_id)

	if color_data.is_empty():
		push_error(
			"Race : couleur inconnue '%s' pour le participant %d."
			% [color_id, participant_id]
		)
		return false

	var car := CAR_SCENE.instantiate() as Car

	if car == null:
		push_error("Race : impossible d'instancier Car.")
		return false

	var spawn := race_world.get_spawn_point(spawn_index)

	if spawn == null:
		push_error(
			"Race : SpawnPoint %d introuvable."
			% (spawn_index + 1)
		)
		car.queue_free()
		return false

	race_world.add_car(car)

	car.global_position = spawn.global_position
	car.global_rotation = spawn.global_rotation

	car.setup_car(
		car_definition,
		color_data["color"],
		participant_id,
		bool(participant.get("is_ai", false)),
		String(participant.get("device_type", "")),
		int(participant.get("device_id", -1)),
		race_world.get_skid_marks()
	)

	return true


func _initialize_camera() -> void:
	var camera := race_world.race_camera as RaceCamera

	if camera == null:
		push_warning(
			"Race : RaceCamera n'utilise pas le script RaceCamera."
		)
		return
