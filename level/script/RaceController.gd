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

# Un participant a coupé : il a franchi une section plus loin que celle
# qu'il devait passer. Il explose et réapparaît à la section sautée.
signal shortcut_detected(state: RaceParticipantState, missed_section: int)

# Départ : résultats de réaction au feu vert (humains).
# Chaque entrée : {state, reaction, effect} ; effect > 0 bonus, < 0 malus.
signal start_reactions_judged(results: Array)

signal quit_race()

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
var controls_instance: Control = null

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

# Position de chaque section (section_id -> Vector2), pour mesurer
# la progression continue entre deux sections.
var _section_positions: Dictionary = {}

# Sections du circuit (section_id -> RaceSection).
var _sections: Dictionary = {}

# Portes des sections (section_id -> [a, b] en coordonnées globales).
var _gate_segments: Dictionary = {}

# Distance maximale (px) entre la voiture et la porte pour valider un
# passage : écarte les contacts « fantômes » signalés juste après une
# réapparition, alors que la voiture est déjà ailleurs.
const GATE_MAX_DISTANCE := 300.0

# Progression mesurée le long de la route (chemin réel entre deux
# sections). null si le circuit ne permet pas de la calculer :
# on retombe alors sur l'estimation à vol d'oiseau.
var track_progress: TrackProgress = null

# Cache : progression calculée une fois par image physique.
var _progress_cache: Dictionary = {}
var _progress_cache_frame: int = -1

# ============================================================
# CLASSEMENT EN CONTINU
# ============================================================
# Le classement est recalculé régulièrement (pas seulement au
# franchissement d'une section) : les dépassements apparaissent
# en temps réel.
const POSITION_UPDATE_INTERVAL := 0.2

# ============================================================
# RÉACTION AU DÉPART
# ============================================================
# Réaction (s) en dessous de laquelle le bonus est maximal.
const START_REACTION_PERFECT := 0.12
# Réaction (s) au-delà de laquelle il n'y a plus de bonus.
const START_REACTION_WINDOW := 0.40
# Bonus de puissance maximal (+60 %).
const START_BONUS_MAX := 0.6
# Faux départ : malus de puissance de 50 % (juste avant le vert)
# à 85 % (0,6 s d'avance ou plus).
const START_MALUS_MIN := 0.5
const START_MALUS_MAX := 0.85
const START_EARLY_FULL := 0.6
# Durée de l'effet (il s'estompe progressivement).
const START_EFFECT_DURATION := 1.5

var _judging_start := false

var _position_update_timer: float = 0.0
var _last_order: Array[int] = []

# ============================================================
# CHRONOMÉTRAGE
# ============================================================

# Temps monotone utilisé comme origine de la course.
#
# Time.get_ticks_usec() est préférable à un cumul de delta
# pour un chronométrage précis.
var race_start_usec: int = 0
var pause_start_usec: int = 0
var pause_end_usec: int = 0


# ============================================================
# DÉPART
# ============================================================
@onready var timer_race_end: Timer = $TimerRaceEnd

var start_lights: RaceStartLights = null

# ============================================================
# MODE ÉLIMINATION
# ============================================================
# Créé uniquement si race_config.is_elimination().
var elimination_rules: EliminationRules = null

# Usure des pneus et arrêts au stand (option de course classique).
var pit_stops: PitStopManager = null

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
	pause_overlay.quit_pressed.connect(_on_pause_quit_pressed)
	pause_overlay.controls_pressed.connect(_on_pause_controls_pressed)
	pause_overlay.main_menu_pressed.connect(_on_pause_main_menu_pressed)

	print("Initialisation des sections")
	if not _initialize_sections():
		return false

	print("Initialisation des participants")
	if not _initialize_participants():
		return false

	if race_config.is_elimination():
		_initialize_elimination()

	if race_config.uses_tire_wear():
		pit_stops = PitStopManager.new()
		pit_stops.name = "PitStopManager"
		add_child(pit_stops)
		pit_stops.setup(self)

	return true


func _initialize_elimination() -> void:
	elimination_rules = EliminationRules.new()
	elimination_rules.name = "EliminationRules"
	add_child(elimination_rules)

	elimination_rules.setup(
		self,
		race_world.race_camera as RaceCamera,
		race_config.target_score
	)

	# Le classement affiché suit les points.
	elimination_rules.round_finished.connect(
		func(_ranking, _awarded): _update_positions()
	)


func is_elimination_mode() -> bool:
	return elimination_rules != null


## Fin de partie en mode élimination (score cible atteint).
func finish_elimination_race() -> void:
	_finish_race()


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

	_section_positions.clear()

	var gate_segments: Dictionary = {}

	for child in sections_root.get_children():
		var section := child as RaceSection
		_section_positions[section.section_id] = section.global_position
		_sections[section.section_id] = section
		gate_segments[section.section_id] = _get_gate_segment(section)
		_gate_segments[section.section_id] = gate_segments[section.section_id]

	track_progress = TrackProgress.new()

	if not track_progress.build(race_world.current_track, gate_segments):
		push_warning(
			"RaceController : progression le long de la route indisponible (%s), "
			% track_progress.last_error
			+ "estimation à vol d'oiseau utilisée."
		)
		track_progress = null

	return true


## Porte d'une section : son SegmentShape2D en coordonnées globales
## (ou un segment nul à la position de la section).
func _get_gate_segment(section: RaceSection) -> Array:
	for child in section.get_children():
		var shape := child as CollisionShape2D

		if shape != null and shape.shape is SegmentShape2D:
			var segment := shape.shape as SegmentShape2D
			return [shape.to_global(segment.a), shape.to_global(segment.b)]

	return [section.global_position, section.global_position]


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
		
		if not car.respawn_requested.is_connected(
			_on_car_respawn_requested
		):
			car.respawn_requested.connect(
				_on_car_respawn_requested
			)
		
		var spawn := race_world.get_spawn_point(car.participant_id)
		update_respawn_point(state,spawn)

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

	# Suivi de l'accélérateur des joueurs pendant les feux.
	_judging_start = true

	for state in participants:
		state.start_reaction_time = NAN
		state.start_judged = state.is_ai
		state.start_press_usec = -1

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
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return

	if event.is_echo():
		return

	if not can_pause or race_state == RaceState.FINISHED:
		return

	if race_is_paused:
		resume_race()
	else:
		pause_race()

	get_viewport().set_input_as_handled()


func pause_race() -> void:
	if race_is_paused:
		return
	if not timer_race_end.is_stopped():
		timer_race_end.paused = true
	race_is_paused = true

	pause_overlay.open()
	
	pause_start_usec = Time.get_ticks_usec()
	get_tree().paused = true


func resume_race() -> void:
	if not race_is_paused:
		return
	if not timer_race_end.is_stopped():
		timer_race_end.paused = false
	if is_instance_valid(controls_instance):
		controls_instance.queue_free()

	race_is_paused = false

	pause_end_usec = Time.get_ticks_usec()
	race_start_usec += pause_end_usec - pause_start_usec
	get_tree().paused = false

	pause_overlay.close()


func _on_pause_resume_pressed() -> void:
	resume_race()


func _on_pause_quit_pressed() -> void:
	_on_quit_race()


func _on_pause_controls_pressed() -> void:
	open_controls()


func _on_pause_main_menu_pressed() -> void:
	_on_return_to_main_menu()

func open_controls() -> void:
	if is_instance_valid(controls_instance):
		return

	controls_instance = CONTROLS_SCENE.instantiate()
	controls_instance.name = "Controls"

	# Afficher Controls au-dessus du menu de pause.
	pause_overlay.get_parent().add_child(controls_instance)

	# Facultatif : mémoriser l'origine pour gérer le retour.
	controls_instance.set_meta("opened_from_pause", true)
	#controls_scene.opened_from_pause = true
	controls_instance.quit_control.connect(_on_quit_controlt)

func _on_quit_controlt() -> void:
	pause_overlay.get_focus()


func _on_quit_race() -> void:
	race_is_paused = false
	get_tree().paused = false
	
	timer_race_end.stop()
	
	for state in participants:

		if state.car != null:
			state.car.set_can_move(false)

	# On fige le classement final.
	_update_positions()
	
	#pause_overlay.close()
	
	quit_race.emit()


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

	# Accélérateur déjà enfoncé au vert : faux départ.
	_track_start_throttle()

	for state in participants:
		if state.start_judged or state.start_press_usec < 0:
			continue

		_judge_start(
			state,
			float(state.start_press_usec - race_start_usec) / 1_000_000.0
		)
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

	if is_elimination_mode():
		elimination_rules.start_round()


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
## trusted : appel du jeu lui-même (validation après un raccourci),
## sans contrôle de distance à la porte.
func on_car_entered_section(
	car: Car,
	section_id: int,
	respawn_point: Marker2D,
	trusted: bool = false
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
	if not trusted and not _is_car_near_gate(state.car, section_id):
		return

	if section_id != state.next_section:
		if _is_shortcut(state, section_id):
			_punish_shortcut(state)
		return

	var current_time := get_race_time()

	# ========================================================
	# PREMIER PASSAGE SUR LA LIGNE DE DÉPART
	# ========================================================
	if not state.has_started_lap:
		if section_id != 0:
			return
		
		update_respawn_point(state, respawn_point)

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
	
	update_respawn_point(state, respawn_point)

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
# MISE A JOUR DU POINT DE RESPAWN
# ============================================================
func update_respawn_point(
	state: RaceParticipantState,
	marker: Marker2D
) -> void:
	if state == null:
		print("updateRespawn: erreur state")
		return
	if marker == null:
		print("updateRespawn: erreur marker")
		return

	state.respawn_transform = marker.global_transform
	state.has_respawn_point = true

func _on_car_respawn_requested(car: Car) -> void:
	print("respawn demandé")
	request_respawn(car)

func request_respawn(car: Car) -> void:
	if race_state != RaceState.RUNNING:
		print("respawn: la course est finie")
		return

	if race_is_paused:
		print("respawn: en pause")
		return

	var state := _get_participant_state(car)

	if state == null:
		print("respawn: voiture introuvable")
		return

	if state.finished:
		print("respawn: voiture a fini la course")
		return

	# Élimination : jamais de réapparition (accident = élimination,
	# le joueur attend le restart de la manche).
	if is_elimination_mode():
		return

	if not state.has_respawn_point:
		push_warning(
			"Respawn impossible : aucun point enregistré pour %s."
			% state.nickname
		)
		return

	if not is_instance_valid(state.car):
		print("respawn: voiture invalide")
		return
	
	print("respawn: destruction en cours ? "+str(state.car._destruction_started))
	if state.car._destruction_started == false:
		state.car.respawn_at(state.respawn_transform)

		# Après un raccourci : la section sautée est validée à la
		# réapparition (la voiture y est replacée).
		if state.pending_section_validation >= 0:
			var section_id := state.pending_section_validation
			state.pending_section_validation = -1
			var section: RaceSection = _sections.get(section_id)

			if section != null:
				on_car_entered_section(state.car, section_id, section.respawn_point, true)


# ============================================================
# RACCOURCIS
# ============================================================

## La voiture franchit une section située plus loin (au plus un
## demi-tour) que celle qu'elle devait passer. Repasser une section
## déjà franchie (tête-à-queue, retour en arrière) n'est pas un
## raccourci.
func _is_shortcut(state: RaceParticipantState, section_id: int) -> bool:
	if race_state != RaceState.RUNNING or section_count < 2:
		return false

	if not is_instance_valid(state.car):
		return false

	if state.car._destruction_started or state.car._respawning:
		return false

	if state.pending_section_validation >= 0:
		return false

	var ahead := posmod(section_id - state.next_section, section_count)

	return ahead >= 1 and ahead <= section_count / 2


func _is_car_near_gate(car: Car, section_id: int) -> bool:
	var gate: Array = _gate_segments.get(section_id, [])

	if gate.is_empty() or not is_instance_valid(car):
		return true

	var closest := Geometry2D.get_closest_point_to_segment(
		car.global_position, gate[0], gate[1]
	)

	return car.global_position.distance_to(closest) <= GATE_MAX_DISTANCE


## Explosion, puis réapparition à la section sautée.
func _punish_shortcut(state: RaceParticipantState) -> void:
	var missed := state.next_section
	var section: RaceSection = _sections.get(missed)

	if section != null and section.respawn_point != null:
		state.respawn_transform = section.respawn_point.global_transform
		state.has_respawn_point = true
		state.pending_section_validation = missed

	shortcut_detected.emit(state, missed)
	state.car.explosion()


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
	# En élimination, la partie se termine au score, pas aux tours.
	if (
		not is_elimination_mode()
		and state.current_lap >= race_config.lap_count
	):
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

	if is_instance_valid(state.car):
		# Laisse le contrôleur enregistrer le résultat et le classement
		# avant de déclencher la destruction visuelle.
		state.car.explosion()

	participant_finished.emit(state)

	_update_positions()

	print("{nickname} a fini la course en {position} position".format({"nickname": state.nickname, "position": state.race_position}))
	print("{nb} participants ont fini la course".format({"nb": state.finish_position}))
	# --------------------------------------------------------
	# Le premier arrivé déclenche le délai de fin de course.
	# --------------------------------------------------------
	if _get_finished_count() == 1:
		AudioManager.play_finish_event()
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

func _physics_process(delta: float) -> void:
	if _judging_start:
		_update_start_judging()

	if race_state != RaceState.RUNNING or race_is_paused:
		return

	_position_update_timer += delta

	if _position_update_timer < POSITION_UPDATE_INTERVAL:
		return

	_position_update_timer = 0.0

	# Signal seulement si l'ordre a changé.
	_update_positions(false)


# ============================================================
# RÉACTION AU DÉPART
# ============================================================

## Mémorise le début de l'appui en cours sur l'accélérateur.
func _track_start_throttle() -> void:
	var now := Time.get_ticks_usec()

	for state in participants:
		if state.start_judged or state.car == null:
			continue

		var input := InputManager.get_player_input(
			state.car.input_device_type,
			state.car.input_device_id
		)

		if input.throttle > 0.5:
			if state.start_press_usec < 0:
				state.start_press_usec = now
		else:
			state.start_press_usec = -1


func _update_start_judging() -> void:
	_track_start_throttle()

	# Avant le vert : on se contente de suivre les appuis.
	if race_start_usec <= 0:
		return

	var elapsed := float(Time.get_ticks_usec() - race_start_usec) / 1_000_000.0

	for state in participants:
		if state.start_judged:
			continue

		# Appui commencé après le vert : temps de réaction.
		if state.start_press_usec >= race_start_usec:
			_judge_start(
				state,
				float(state.start_press_usec - race_start_usec) / 1_000_000.0
			)
		# Trop tard pour un bonus : départ neutre.
		elif elapsed > START_REACTION_WINDOW:
			_judge_start(state, INF)

	for state in participants:
		if not state.start_judged:
			return

	_judging_start = false

	var results: Array = []

	for state in participants:
		if state.is_ai:
			continue

		results.append({
			"state": state,
			"reaction": state.start_reaction_time,
			"effect": get_start_effect(state.start_reaction_time)
		})

	start_reactions_judged.emit(results)


## Bonus (> 0) / malus (< 0) de puissance selon la réaction (s).
## reaction < 0 : accélérateur enfoncé avant le vert.
static func get_start_effect(reaction: float) -> float:
	if is_nan(reaction) or is_inf(reaction):
		return 0.0

	if reaction < 0.0:
		var early := clampf(-reaction / START_EARLY_FULL, 0.0, 1.0)
		return -lerpf(START_MALUS_MIN, START_MALUS_MAX, early)

	var quality := 1.0 - clampf(
		(reaction - START_REACTION_PERFECT)
		/ (START_REACTION_WINDOW - START_REACTION_PERFECT),
		0.0,
		1.0
	)

	return START_BONUS_MAX * quality


func _judge_start(state: RaceParticipantState, reaction: float) -> void:
	state.start_judged = true
	state.start_reaction_time = reaction

	var effect := get_start_effect(reaction)

	if effect != 0.0 and is_instance_valid(state.car):
		state.car.apply_start_effect(
			effect,
			START_EFFECT_DURATION,
			effect < 0.0
		)


## always_emit = false : n'émet positions_changed que si l'ordre change.
func _update_positions(always_emit: bool = true) -> void:

	var ordered := (
		participants.duplicate()
	)
	ordered.sort_custom(
		_compare_participants
	)

	var order: Array[int] = []

	for i in range(
		ordered.size()
	):
		ordered[i].race_position = i + 1
		order.append(ordered[i].participant_id)

	if not always_emit and order == _last_order:
		return

	_last_order = order

	positions_changed.emit(ordered[0])


## Progression continue sur la course, en « sections » :
## tours x sections + sections franchies dans le tour + fraction
## parcourue vers la prochaine section (0 à 1).
##
## Corrige l'ancien classement où, après la dernière section
## (next_section revenu à 0), une voiture en fin de tour passait
## derrière celles encore en milieu de tour.
func get_progress(state: RaceParticipantState) -> float:
	if section_count <= 0:
		return 0.0

	# Même valeur pour tous les appels d'une image (classement, caméras).
	var frame := Engine.get_physics_frames()

	if frame != _progress_cache_frame:
		_progress_cache.clear()
		_progress_cache_frame = frame

	if _progress_cache.has(state):
		return _progress_cache[state]

	var progress := _compute_progress(state)
	_progress_cache[state] = progress
	return progress


func _compute_progress(state: RaceParticipantState) -> float:

	# Avant le premier passage sur la ligne : on approche la section 0.
	if not state.has_started_lap:
		return -1.0 + _get_fraction_to_section(state, 0, -1)

	# next_section = 0 : il ne reste que la ligne d'arrivée,
	# c'est le dernier segment du tour (pas le premier).
	var segment_index := state.next_section

	if segment_index == 0:
		segment_index = section_count

	var target := state.next_section
	var previous := (target - 1 + section_count) % section_count

	# Distance réellement parcourue le long de la route dans le tronçon.
	if track_progress != null and is_instance_valid(state.car):
		return (
			float(state.current_lap * section_count)
			+ float(segment_index - 1)
			+ track_progress.get_fraction(previous, state.car.global_position)
		)

	return (
		float(state.current_lap * section_count)
		+ float(segment_index - 1)
		+ _get_fraction_to_section(state, target, previous)
	)


## Fraction (0 à 1) du segment previous -> target déjà parcourue,
## estimée à vol d'oiseau. previous = -1 : distance seule.
func _get_fraction_to_section(
	state: RaceParticipantState,
	target: int,
	previous: int
) -> float:

	if state.car == null or not is_instance_valid(state.car):
		return 0.0

	var target_position: Variant = _section_positions.get(target)

	if target_position == null:
		return 0.0

	var distance := state.car.global_position.distance_to(target_position)

	var previous_position: Variant = _section_positions.get(previous)

	if previous_position == null:
		# Plus on est proche, plus on est avancé (reste < 1).
		return 1.0 / (1.0 + distance / 1000.0)

	var segment_length: float = maxf(
		(previous_position as Vector2).distance_to(target_position),
		1.0
	)

	return clampf(1.0 - distance / segment_length, 0.0, 0.999)


func _compare_participants(
	a: RaceParticipantState,
	b: RaceParticipantState
) -> bool:
	# --------------------------------------------------------
	# Élimination : classement aux points.
	# --------------------------------------------------------
	if is_elimination_mode() and a.points != b.points:
		return a.points > b.points

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
	# Progression continue (tours, sections, fraction du segment).
	# --------------------------------------------------------
	var progress_a := get_progress(a)
	var progress_b := get_progress(b)

	if not is_equal_approx(progress_a, progress_b):
		return progress_a > progress_b

	# --------------------------------------------------------
	# Égalité parfaite : celui qui a progressé en premier.
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
			state.car.explosion()

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

			"points": state.points,

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


func get_participant_state_by_id(
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
