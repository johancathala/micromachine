extends Node
class_name PitStopManager

# ============================================================
# USURE DES PNEUS ET ARRÊT AU STAND
# ============================================================
#
# - Les pneus des joueurs humains s'usent (voir Car.tire_wear).
# - « BOX, BOX ! » s'affiche à 60 % puis à 85 % d'usure.
#   Le joueur peut continuer, mais la voiture devient de plus en
#   plus difficile à conduire.
# - Une voiture arrêtée dans la zone de stand (nœud PitStop du
#   circuit) déclenche un QTE de 8 directions (haut / bas / gauche /
#   droite), jouées avec les commandes de conduite du joueur
#   (haut = accélérer, bas = freiner). Une erreur fait recommencer
#   la séquence depuis le début. Réussi : pneus neufs.
# ============================================================

signal box_requested(state: RaceParticipantState, wear: float)
signal pit_started(state: RaceParticipantState, sequence: Array)
signal pit_progress(state: RaceParticipantState, index: int)
signal pit_error(state: RaceParticipantState)
signal pit_finished(state: RaceParticipantState)

enum Direction { UP, DOWN, LEFT, RIGHT }

const DIRECTION_SYMBOLS := ["↑", "↓", "←", "→"]

const BOX_THRESHOLDS := [0.6, 0.85]
const QTE_LENGTH := 8
# Vitesse (px/s) en dessous de laquelle la voiture est « arrêtée ».
const PIT_STOP_MAX_SPEED := 120.0
# Usure minimale pour qu'un arrêt déclenche le changement de pneus.
const PIT_MIN_WEAR := 0.05
# Seuil des commandes pour compter une direction.
const INPUT_THRESHOLD := 0.5

var controller: RaceController = null
var pit_stop: PitStop = null

# participant_id -> index du prochain seuil de « BOX » à annoncer.
var _next_box_threshold: Dictionary = {}

# participant_id -> {sequence: Array[int], index: int, last_dir: int}
var _active_qte: Dictionary = {}


func setup(p_controller: RaceController) -> void:
	controller = p_controller

	var track := controller.race_world.current_track
	pit_stop = track.get_node_or_null("PitStop") as PitStop if track else null

	if pit_stop == null:
		push_warning(
			"PitStopManager : aucun nœud PitStop sur ce circuit, "
			+ "changement de pneus impossible."
		)

	for state in controller.participants:
		if state.is_ai or state.car == null:
			continue

		state.car.tire_wear_enabled = true
		state.car.reset_tires()
		_next_box_threshold[state.participant_id] = 0


func is_in_pit(state: RaceParticipantState) -> bool:
	return _active_qte.has(state.participant_id)


func get_qte(state: RaceParticipantState) -> Dictionary:
	return _active_qte.get(state.participant_id, {})


func _physics_process(_delta: float) -> void:
	if controller == null:
		return

	if controller.race_state != RaceController.RaceState.RUNNING:
		return

	if controller.race_is_paused or get_tree().paused:
		return

	for state in controller.participants:
		if state.is_ai or state.finished or not is_instance_valid(state.car):
			continue

		if is_in_pit(state):
			_update_qte(state)
			continue

		_check_box_message(state)
		_check_pit_entry(state)


# ------------------------------------------------------------
# « BOX, BOX »
# ------------------------------------------------------------

func _check_box_message(state: RaceParticipantState) -> void:
	var index: int = _next_box_threshold.get(state.participant_id, 0)

	if index >= BOX_THRESHOLDS.size():
		return

	if state.car.tire_wear >= BOX_THRESHOLDS[index]:
		_next_box_threshold[state.participant_id] = index + 1
		box_requested.emit(state, state.car.tire_wear)


# ------------------------------------------------------------
# ENTRÉE AU STAND
# ------------------------------------------------------------

func _check_pit_entry(state: RaceParticipantState) -> void:
	if pit_stop == null:
		return

	var car := state.car

	if car.tire_wear < PIT_MIN_WEAR:
		return

	if car._destruction_started or car._respawning:
		return

	if car.velocity.length() > PIT_STOP_MAX_SPEED:
		return

	if not pit_stop.contains_car(car):
		return

	# Voiture immobilisée pendant le changement de pneus.
	car.set_can_move(false)
	car.velocity = Vector2.ZERO
	car.speed = 0.0

	var sequence: Array[int] = []

	for i in range(QTE_LENGTH):
		sequence.append(randi_range(Direction.UP, Direction.RIGHT))

	_active_qte[state.participant_id] = {
		"sequence": sequence,
		"index": 0,
		# Attendre que le joueur relâche tout avant la 1re direction.
		"last_dir": _read_direction(state),
		"waiting_release": true
	}

	pit_started.emit(state, sequence)


# ------------------------------------------------------------
# QTE
# ------------------------------------------------------------

func _update_qte(state: RaceParticipantState) -> void:
	var qte: Dictionary = _active_qte[state.participant_id]
	var direction := _read_direction(state)

	# Une direction ne compte qu'au moment où elle est enfoncée.
	if direction == qte["last_dir"]:
		return

	qte["last_dir"] = direction

	if direction < 0:
		qte["waiting_release"] = false
		return

	if qte["waiting_release"]:
		return

	var sequence: Array = qte["sequence"]
	var index: int = qte["index"]

	if direction != sequence[index]:
		# Erreur : on recommence la même séquence depuis le début.
		qte["index"] = 0
		pit_error.emit(state)
		return

	index += 1
	qte["index"] = index
	pit_progress.emit(state, index)

	if index >= sequence.size():
		_finish_pit(state)


func _finish_pit(state: RaceParticipantState) -> void:
	_active_qte.erase(state.participant_id)
	_next_box_threshold[state.participant_id] = 0

	state.car.reset_tires()
	state.car.set_can_move(true)

	pit_finished.emit(state)


## Direction enfoncée par le joueur (-1 si aucune), avec ses
## commandes de conduite : accélérer = haut, freiner = bas.
func _read_direction(state: RaceParticipantState) -> int:
	var input := InputManager.get_player_input(
		state.car.input_device_type,
		state.car.input_device_id
	)

	if input.throttle > INPUT_THRESHOLD:
		return Direction.UP

	if input.brake > INPUT_THRESHOLD:
		return Direction.DOWN

	if input.steering < -INPUT_THRESHOLD:
		return Direction.LEFT

	if input.steering > INPUT_THRESHOLD:
		return Direction.RIGHT

	return -1
