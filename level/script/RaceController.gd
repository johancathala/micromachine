extends Node
class_name RaceController

const CONTROLS_SCENE := preload(
	"res://ui/scene/Controls.tscn"
)

# ============================================================
# SIGNAUX
# ============================================================
signal race_started()

signal participant_section_completed(
	participant: RaceParticipantState,
	section_id: int
)

signal participant_lap_completed(
	participant: RaceParticipantState
)

signal participant_finished(
	participant: RaceParticipantState
)

signal positions_changed(participant: RaceParticipantState)

signal race_end_countdown_started(
	remaining_time: float
)

signal race_finished()

signal restart_race()

signal return_to_main_menu()


# ============================================================
# ÉTAT DE LA COURSE
# ============================================================
enum RaceState {
	COUNTDOWN,
	RUNNING,
	FINISHED
}

var race_state: RaceState = RaceState.COUNTDOWN

var race_is_paused := false

# ============================================================
# RÉFÉRENCES
# ============================================================
var race_config: RaceConfig = null
var race_world: RaceWorld = null

# ============================================================
# MENU PAUSE
# ============================================================
var pause_overlay: PauseOverlay = null
var can_pause := true

# ============================================================
# PARTICIPANTS
# ============================================================
var participants: Array[RaceParticipantState] = []

# ============================================================
# CIRCUIT
# ============================================================
var section_count: int = 0

# ============================================================
# CHRONOMÉTRAGE
# ============================================================

# Temps monotone utilisé comme origine de la course.
#
# Time.get_ticks_usec() est préférable à un cumul de delta
# pour un chronométrage précis.
var race_start_usec: int = 0


# ============================================================
# DÉPART
# ============================================================
@onready var timer_race_end: Timer = $TimerRaceEnd

var start_lights: RaceStartLights = null

const RACE_END_DELAY := 30.0


# ============================================================
# INITIALISATION
# ============================================================
func _ready() -> void:

	timer_race_end.one_shot = true
	timer_race_end.wait_time = RACE_END_DELAY
	timer_race_end.timeout.connect(
		_on_timer_race_end_timeout
	)


func initialize(
	p_config: RaceConfig,
	p_race_world: RaceWorld,
	p_pause_overlay: PauseOverlay
) -> bool:

	print("Initialisation de RaceController")
	if p_config == null:
		push_error(
			"RaceController : RaceConfig invalide."
		)
		return false

	if p_race_world == null:
		push_error(
			"RaceController : RaceWorld invalide."
		)
		return false

	race_config = p_config
	race_world = p_race_world
	
	pause_overlay = p_pause_overlay
	
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	pause_overlay.resume_pressed.connect(_on_pause_resume_pressed)
	pause_overlay.restart_pressed.connect(_on_pause_restart_pressed)
	pause_overlay.controls_pressed.connect(_on_pause_controls_pressed)
	pause_overlay.main_menu_pressed.connect(_on_pause_main_menu_pressed)

	print("Initialisation des sections")
	if not _initialize_sections():
		return false

	print("Initialisation des participants")
	if not _initialize_participants():
		return false

	return true


# ============================================================
# INITIALISATION DES SECTIONS
# ============================================================
func _initialize_sections() -> bool:

	section_count = 0

	if race_world.current_track == null:

		push_error(
			"RaceController : aucun circuit chargé."
		)

		return false

	var sections_root := (
		race_world.current_track.get_node_or_null(
			"Sections"
		) as Node
	)

	if sections_root == null:

		push_error(
			"RaceController : le circuit '%s' ne possède "
			% race_world.current_track.name
			+ "pas de nœud Sections."
		)

		return false

	if sections_root.get_child_count() == 0:

		push_error(
			"RaceController : le circuit ne possède "
			+ "aucune section."
		)

		return false

	# --------------------------------------------------------
	# Vérification des IDs
	# --------------------------------------------------------

	var section_ids: Dictionary = {}

	for child in sections_root.get_children():

		var section := child as RaceSection

		if section == null:

			push_error(
				"RaceController : '%s' n'est pas un RaceSection."
				% child.name
			)

			return false

		var id := section.section_id

		if id < 0:

			push_error(
				"RaceController : section '%s' possède "
				% section.name
				+ "un section_id négatif."
			)

			return false

		if section_ids.has(id):

			push_error(
				"RaceController : section_id %d est utilisé "
				% id
				+ "plusieurs fois."
			)

			return false

		section_ids[id] = true

	# --------------------------------------------------------
	# Les IDs doivent être continus :
	#
	# 0, 1, 2, 3, ...
	# --------------------------------------------------------

	section_count = sections_root.get_child_count()

	for i in range(section_count):

		if not section_ids.has(i):

			push_error(
				"RaceController : section_id %d manquant."
				% i
			)

			return false

	return true


# ============================================================
# INITIALISATION DES PARTICIPANTS
# ============================================================
func _initialize_participants() -> bool:

	participants.clear()

	var cars_root := race_world.get_cars_root()

	if cars_root == null:

		push_error(
			"RaceController : nœud Cars introuvable."
		)

		return false

	for child in cars_root.get_children():

		var car := child as Car

		if car == null:
			continue

		var state := RaceParticipantState.new()

		state.initialize(
			car.participant_id,
			_get_participant_nickname(
				car.participant_id
			),
			car,
			car.is_ai,
			section_count,
			car.input_device_type
		)

		participants.append(state)

	if participants.is_empty():

		push_error(
			"RaceController : aucun participant actif."
		)

		return false

	# Initialisation du classement.
	_update_positions()

	return true


# ============================================================
# COMPTE À REBOURS
# ============================================================
func _get_start_lights() -> RaceStartLights:

	var node := get_tree().get_first_node_in_group(
		"race_start_lights"
	)

	return node as RaceStartLights

func start_countdown() -> void:

	print("Démarrage du compte à rebourd du départ")
	if race_config == null:
		push_error(
			"RaceController : RaceConfig non initialisée."
		)
		return

	if race_world == null:
		push_error(
			"RaceController : RaceWorld non initialisé."
		)
		return

	if participants.is_empty():
		push_error(
			"RaceController : aucun participant."
		)
		return

	race_state = RaceState.COUNTDOWN

	race_start_usec = 0

	# --------------------------------------------------------
	# Toutes les voitures sont bloquées.
	# --------------------------------------------------------

	for state in participants:

		if state.car != null:

			state.car.set_can_move(
				false
			)

		_reset_participant_state(
			state
		)

	# --------------------------------------------------------
	# Récupération du système de feux.
	# --------------------------------------------------------
	start_lights = _get_start_lights()

	if start_lights == null:

		push_error(
			"RaceController : RaceStartLights introuvable."
		)

		return

	# --------------------------------------------------------
	# Lancement de la séquence réelle de départ.
	# --------------------------------------------------------
	if not start_lights.start_sequence_finished.is_connected(
		_on_start_sequence_finished
	):

		start_lights.start_sequence_finished.connect(
			_on_start_sequence_finished
		)

	start_lights.start_sequence()


# ============================================================
# GESTION DU MENU PAUSE
# ==========================================================
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if race_is_paused:
			resume_race()
		else:
			pause_race()


func pause_race() -> void:
	if race_is_paused:
		return

	race_is_paused = true

	pause_overlay.open()

	get_tree().paused = true


func resume_race() -> void:
	if not race_is_paused:
		return

	race_is_paused = false

	get_tree().paused = false

	pause_overlay.close()


func _on_pause_resume_pressed() -> void:
	resume_race()


func _on_pause_restart_pressed() -> void:
	_on_restart_race()


func _on_pause_controls_pressed() -> void:
	open_controls()


func _on_pause_main_menu_pressed() -> void:
	_on_return_to_main_menu()

func open_controls() -> void:
	#NavigationManager.go("Controls")
	CONTROLS_SCENE.instantiate()


func _on_restart_race() -> void:
	race_is_paused = false
	get_tree().paused = false
	
	race_state = RaceState.FINISHED

	timer_race_end.stop()
	
	for state in participants:

		if state.car != null:
			state.car.set_can_move(false)

	# On fige le classement final.
	_update_positions()
	
	restart_race.emit()
	#get_parent().reload_current_scene()


func _on_return_to_main_menu() -> void:
	race_is_paused = false
	get_tree().paused = false
	return_to_main_menu.emit()



# ============================================================
# RESET D'UN PARTICIPANT
# ============================================================
func _reset_participant_state(
	state: RaceParticipantState
) -> void:

	state.finished = false
	state.finish_position = 0

	state.current_lap = 0
	state.next_section = 0
	state.has_started_lap = false

	state.lap_start_time = 0.0
	state.last_lap_time = 0.0
	state.best_lap_time = 0.0

	state.section_times.clear()
	state.lap_records.clear()

	for i in range(
		state.best_section_times.size()
	):
		state.best_section_times[i] = 0.0

	state.finish_time = 0.0
	state.race_position = 0
	state.last_progress_time = 0.0
	
	state.last_section_time = 0.0
	state.last_section_delta = 0.0
	state.last_section_index = -1


# ============================================================
# FIN DU TIMER DE DÉPART
# ============================================================
func _on_start_sequence_finished() -> void:
	_start_race()


# ============================================================
# DÉPART EFFECTIF
# ============================================================

func _start_race() -> void:
	print("Démarrage de la course")
	if race_state != RaceState.COUNTDOWN:
		return

	# --------------------------------------------------------
	# Etat logique de la course.
	# --------------------------------------------------------
	race_state = RaceState.RUNNING

	# --------------------------------------------------------
	# Origine du chronométrage.
	# --------------------------------------------------------
	race_start_usec = Time.get_ticks_usec()

	# --------------------------------------------------------
	# Le HUD reçoit d'abord l'ordre de passer les feux au vert.
	# --------------------------------------------------------
	race_started.emit()

	# --------------------------------------------------------
	# SEULEMENT APRÈS LE SIGNAL DE DÉPART,
	# on débloque les voitures.
	# --------------------------------------------------------
	for state in participants:
		if state.car != null:
			state.car.set_can_move(
				true
			)


# ============================================================
# TEMPS DE COURSE
# ============================================================
func get_race_time() -> float:

	if race_start_usec <= 0:
		return 0.0

	return float(
		Time.get_ticks_usec()
		- race_start_usec
	) / 1_000_000.0


# ============================================================
# DÉTECTION D'UNE SECTION
# ============================================================

func on_car_entered_section(
	car: Car,
	section_id: int
) -> void:

	# --------------------------------------------------------
	# Une section n'a aucun effet avant le départ.
	# --------------------------------------------------------

	if race_state != RaceState.RUNNING:
		return

	# --------------------------------------------------------
	# Validation de l'ID.
	# --------------------------------------------------------

	if (
		section_id < 0
		or section_id >= section_count
	):

		push_error(
			"RaceController : section_id %d invalide."
			% section_id
		)

		return

	# --------------------------------------------------------
	# Recherche de la voiture.
	# --------------------------------------------------------

	var state := _get_participant_state(car)

	if state == null:
		return

	if state.finished:
		return

	# --------------------------------------------------------
	# La voiture doit franchir les sections dans l'ordre.
	# --------------------------------------------------------

	if section_id != state.next_section:
		return

	var current_time := get_race_time()

	# ========================================================
	# PREMIER PASSAGE SUR LA LIGNE DE DÉPART
	# ========================================================

	if not state.has_started_lap:

		if section_id != 0:
			return

		_start_first_lap(
			state,
			current_time
		)

		return

	# ========================================================
	# PASSAGE NORMAL
	# ========================================================

	state.section_times.append(
		current_time
	)
	
	_update_last_section_delta(state)

	state.last_progress_time = current_time

	participant_section_completed.emit(
		state,
		section_id
	)

	# --------------------------------------------------------
	# La section 0 est la ligne de départ / arrivée.
	#
	# Si elle est franchie alors qu'un tour est déjà en cours,
	# le tour vient de se terminer.
	# --------------------------------------------------------

	if section_id == 0:

		_finish_lap(
			state,
			current_time
		)

		return

	# --------------------------------------------------------
	# Section normale.
	# --------------------------------------------------------

	state.next_section += 1

	# Après la dernière section, la prochaine section
	# attendue est la ligne de départ / arrivée.
	if state.next_section >= section_count:

		state.next_section = 0

	_update_positions()


# ============================================================
# PREMIER DÉPART D'UN PARTICIPANT
# ============================================================

func _start_first_lap(
	state: RaceParticipantState,
	current_time: float
) -> void:

	state.has_started_lap = true

	state.current_lap = 1

	state.lap_start_time = current_time

	state.last_progress_time = current_time

	state.section_times.clear()

	state.section_times.append(
		current_time
	)

	# La section 0 est déjà franchie.
	state.next_section = 1

	# Si le circuit ne possède qu'une section,
	# le prochain passage doit rester sur 0.
	if section_count <= 1:
		state.next_section = 0

	participant_section_completed.emit(
		state,
		0
	)

	_update_positions()


# ============================================================
# FIN D'UN TOUR
# ============================================================
func _finish_lap(
	state: RaceParticipantState,
	current_time: float
) -> void:
	# --------------------------------------------------------
	# Le passage sur la ligne termine le tour.
	# --------------------------------------------------------
	state.section_times.append(
		current_time
	)
	
	_update_last_section_delta(state)

	var lap_time := (
		current_time
		- state.lap_start_time
	)

	state.last_lap_time = lap_time

	# --------------------------------------------------------
	# Calcul des temps intermédiaires du tour.
	# --------------------------------------------------------
	var section_times := (
		_calculate_section_times(state)
	)

	# --------------------------------------------------------
	# Conservation définitive du tour.
	# --------------------------------------------------------
	state.lap_records.append({
		"lap": state.current_lap,
		"lap_time": lap_time,
		"section_times": section_times.duplicate()
	})

	# --------------------------------------------------------
	# Meilleur tour personnel.
	# --------------------------------------------------------
	if (
		state.best_lap_time <= 0.0
		or lap_time < state.best_lap_time
	):

		state.best_lap_time = lap_time

	# --------------------------------------------------------
	# Meilleurs temps intermédiaires personnels.
	# --------------------------------------------------------
	_update_best_section_times(
		state
	)

	participant_lap_completed.emit(
		state
	)

	# --------------------------------------------------------
	# Dernier tour de la course.
	# --------------------------------------------------------
	if state.current_lap >= race_config.lap_count:

		_finish_participant(
			state,
			current_time
		)

		return

	# --------------------------------------------------------
	# Nouveau tour.
	# --------------------------------------------------------
	state.current_lap += 1

	state.next_section = 1

	state.section_times.clear()

	state.section_times.append(
		current_time
	)

	state.lap_start_time = current_time

	state.last_progress_time = current_time

	_update_positions()

# ============================================================
# MEILLEURS TEMPS DE SECTIONS
# ============================================================
func _update_best_section_times(
	state: RaceParticipantState
) -> void:

	var section_times := _calculate_section_times(
		state
	)

	for i in range(section_times.size()):

		if i >= state.best_section_times.size():
			continue

		var section_time := section_times[i]

		var best := (
			state.best_section_times[i]
		)

		if (
			best <= 0.0
			or section_time < best
		):

			state.best_section_times[i] = section_time

func _calculate_section_times(
	state: RaceParticipantState
) -> Array[float]:

	var result: Array[float] = []

	if state.section_times.size() < 2:
		return result

	var previous_time := state.lap_start_time

	for i in range(
		state.section_times.size()
	):

		var current_time := (
			state.section_times[i]
		)

		var section_time := (
			current_time
			- previous_time
		)

		previous_time = current_time

		if i == 0:
			continue

		result.append(section_time)

	return result

func _update_last_section_delta(
	state: RaceParticipantState
) -> void:

	if state.section_times.size() < 2:
		state.last_section_time = 0.0
		state.last_section_delta = 0.0
		state.last_section_index = -1
		return

	var section_index := state.section_times.size() - 2

	if (
		section_index < 0
		or section_index >= state.best_section_times.size()
	):
		state.last_section_time = 0.0
		state.last_section_delta = 0.0
		state.last_section_index = -1
		return

	var previous_time := (
		state.section_times[
			state.section_times.size() - 2
		]
	)

	var current_time := (
		state.section_times[
			state.section_times.size() - 1
		]
	)

	var section_time := current_time - previous_time

	state.last_section_time = section_time
	state.last_section_index = section_index

	var best_section_time := (
		state.best_section_times[section_index]
	)

	if best_section_time > 0.0:
		state.last_section_delta = (
			section_time - best_section_time
		)
	else:
		state.last_section_delta = 0.0

# ============================================================
# FIN D'UN PARTICIPANT
# ============================================================

func _finish_participant(
	state: RaceParticipantState,
	current_time: float
) -> void:

	if state.finished:
		return

	state.finished = true
	state.finish_time = current_time

	state.last_progress_time = current_time

	state.finish_position = (
		_get_finished_count()
	)

	if state.car != null:
		state.car.set_can_move(false)

	participant_finished.emit(state)

	_update_positions()

	print("{nickname} a fini la course en {position} position".format({"nickname": state.nickname, "position": state.race_position}))
	print("{nb} participants ont fini la course".format({"nb": state.finish_position}))
	# --------------------------------------------------------
	# Le premier arrivé déclenche le délai de fin de course.
	# --------------------------------------------------------
	if _get_finished_count() == 1:

		_start_race_end_timer()

		race_end_countdown_started.emit(
			RACE_END_DELAY
		)
	
	# Si tout le monde est arrivé avant les 30 secondes,
	# on termine immédiatement.
	if _get_finished_count() >= participants.size():

		timer_race_end.stop()

		_finish_race()

# ============================================================
# DÉLAI DE FIN DE COURSE
# ============================================================
func _start_race_end_timer() -> void:
	print("Activation du timer de fin de course")
	if race_state != RaceState.RUNNING:
		return

	if not timer_race_end.is_stopped():
		return

	timer_race_end.start(RACE_END_DELAY)

func _on_timer_race_end_timeout() -> void:

	if race_state != RaceState.RUNNING:
		return

	_finish_race()

# ============================================================
# NOMBRE DE PARTICIPANTS ARRIVÉS
# ============================================================

func _get_finished_count() -> int:

	var count := 0

	for state in participants:

		if state.finished:
			count += 1

	return count


# ============================================================
# CLASSEMENT
# ============================================================

func _update_positions() -> void:

	var ordered := (
		participants.duplicate()
	)

	ordered.sort_custom(
		_compare_participants
	)

	for i in range(
		ordered.size()
	):

		ordered[i].race_position = i + 1

	positions_changed.emit(ordered[0])


func _compare_participants(
	a: RaceParticipantState,
	b: RaceParticipantState
) -> bool:

	# --------------------------------------------------------
	# Les participants arrivés sont devant ceux qui courent.
	# --------------------------------------------------------

	if a.finished != b.finished:

		return a.finished

	# --------------------------------------------------------
	# Deux participants arrivés :
	# ordre d'arrivée.
	# --------------------------------------------------------

	if a.finished and b.finished:

		return (
			a.finish_position
			<
			b.finish_position
		)

	# --------------------------------------------------------
	# Nombre de tours.
	# --------------------------------------------------------

	if a.current_lap != b.current_lap:

		return (
			a.current_lap
			>
			b.current_lap
		)

	# --------------------------------------------------------
	# Section atteinte.
	# --------------------------------------------------------

	if a.next_section != b.next_section:

		return (
			a.next_section
			>
			b.next_section
		)

	# --------------------------------------------------------
	# Même section :
	# celui qui l'a atteinte en premier est devant.
	# --------------------------------------------------------

	return (
		a.last_progress_time
		<
		b.last_progress_time
	)


# ============================================================
# FIN DE COURSE
# ============================================================

func _finish_race() -> void:
	
	print("Fin de la course")
	if race_state == RaceState.FINISHED:
		return

	race_state = RaceState.FINISHED

	timer_race_end.stop()
	
	for state in participants:

		if state.car != null:
			state.car.set_can_move(false)

	# On fige le classement final.
	_update_positions()

	GameManager.store_race_results(
		build_race_results()
	)
	
	race_finished.emit()

func build_race_results() -> Array[Dictionary]:

	var results: Array[Dictionary] = []

	for state in participants:

		results.append({
			"participant_id": state.participant_id,
			"nickname": state.nickname,
			"car_name": state.car.car_name,
			"is_ai": state.is_ai,

			"position": state.race_position,
			"finish_position": state.finish_position,

			"finished": state.finished,

			"lap_records": state.lap_records.duplicate(true),

			"best_lap_time": state.best_lap_time,

			"best_section_times": (
				state.best_section_times.duplicate()
			),

			"finish_time": state.finish_time,

			"lap_count": state.lap_records.size()
		})

	results.sort_custom(
		_compare_result_positions
	)

	return results

func _compare_result_positions(
	a: Dictionary,
	b: Dictionary
) -> bool:

	return int(a.get("position", 999)) < int(
		b.get("position", 999)
	)

# ============================================================
# RECHERCHE D'UN PARTICIPANT
# ============================================================
func _get_participant_state(
	car: Car
) -> RaceParticipantState:

	for state in participants:

		if state.car == car:
			return state

	return null

func get_participant_states() -> Array[RaceParticipantState]:
	return participants


func get_participant_state(
	participant_id: int
) -> RaceParticipantState:

	for state in participants:
		if state.participant_id == participant_id:
			return state

	return null


func get_participant_count() -> int:
	return participants.size()


func get_lap_count() -> int:
	if race_config == null:
		return 0

	return race_config.lap_count


# ============================================================
# NICKNAME
# ============================================================

func _get_participant_nickname(
	p_participant_id: int
) -> String:

	if race_config == null:
		return "?"

	for participant in race_config.participants:

		if int(
			participant.get(
				"participant_id",
				-1
			)
		) != p_participant_id:

			continue

		return String(
			participant.get(
				"nickname",
				"?"
			)
		)

	return "?"
