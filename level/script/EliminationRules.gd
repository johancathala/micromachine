extends Node
class_name EliminationRules

# ============================================================
# MODE ÉLIMINATION HORS ÉCRAN
# ============================================================
#
# - Écran partagé, joueurs humains uniquement.
# - Un joueur dont la voiture sort de l'écran explose et est éliminé
#   de la manche.
# - Quand il ne reste qu'un joueur, la manche est terminée :
#   avec N joueurs, le survivant marque N-1 points, le dernier
#   éliminé N-2, ..., le premier éliminé 0.
# - Si personne n'a atteint le score cible, la course repart à la
#   position du survivant, en grille inversée : le premier éliminé
#   devant, le survivant derrière.
# ============================================================

signal player_eliminated(state: RaceParticipantState)
signal round_finished(ranking: Array, awarded_points: Array)
signal round_restarting()
signal round_started()
signal winner_found(state: RaceParticipantState)

# Marge (px) au-delà du bord de l'écran avant élimination :
# la voiture doit être entièrement sortie.
const OFFSCREEN_MARGIN := 80.0

# Pas d'élimination juste après un départ.
const START_GRACE_TIME := 1.5

# Laisse le temps à l'explosion et au message de manche.
const ROUND_END_DELAY := 2.5
const DESTRUCTION_WAIT_TIMEOUT := 5.0

# Voitures immobilisées sur la grille avant de repartir.
const RESTART_FREEZE_TIME := 2.0

# Grille en quinconce : écart longitudinal et latéral (px).
# Une voiture mesure ~141 px de long et ~53 px de large.
const GRID_SLOT_SPACING := 110.0
const GRID_LATERAL_OFFSET := 40.0

# Trace des positions récentes de chaque voiture, pour placer la grille
# le long du chemin réellement parcouru par le leader.
const TRAIL_SAMPLE_DISTANCE := 20.0
const TRAIL_MAX_POINTS := 300


var controller: RaceController = null
var camera: RaceCamera = null
var target_score: int = 10

var round_active := false
var round_number := 0

# Joueurs éliminés pendant la manche, dans l'ordre.
var elimination_order: Array[RaceParticipantState] = []

var _grace_time := 0.0

# participant_id -> PackedVector2Array (le plus récent en dernier).
var _trails: Dictionary = {}

# Position des sections du circuit (section_id -> Vector2).
var _section_positions: Dictionary = {}


func setup(
	p_controller: RaceController,
	p_camera: RaceCamera,
	p_target_score: int
) -> void:

	controller = p_controller
	camera = p_camera
	target_score = p_target_score

	_section_positions.clear()

	var track := controller.race_world.current_track
	var sections_root := track.get_node_or_null("Sections") if track else null

	if sections_root != null:
		for child in sections_root.get_children():
			var section := child as RaceSection

			if section != null:
				_section_positions[section.section_id] = (
					section.global_position
				)


# ============================================================
# MANCHE
# ============================================================

func start_round() -> void:
	round_number += 1
	round_active = true
	elimination_order.clear()
	_grace_time = START_GRACE_TIME

	for state in controller.participants:
		state.eliminated = false

		if is_instance_valid(state.car):
			state.car.manual_respawn_enabled = false

	round_started.emit()


func _physics_process(delta: float) -> void:
	if controller == null or camera == null:
		return

	if controller.race_state != RaceController.RaceState.RUNNING:
		return

	if controller.race_is_paused or get_tree().paused:
		return

	_record_trails()

	if not round_active:
		return

	# Un accident (explosion, chute dans l'eau...) élimine directement :
	# pas de réapparition, le joueur serait de toute façon trop loin.
	_check_crashed_players()

	if _grace_time > 0.0:
		_grace_time -= delta
	else:
		_check_offscreen_players()

	if get_alive_states().size() <= 1:
		_end_round()


func _check_crashed_players() -> void:
	for state in get_alive_states():
		if get_alive_states().size() <= 1:
			break

		var car := state.car

		if car._destruction_started and not car._respawning:
			_eliminate(state)


func _check_offscreen_players() -> void:
	var view := camera.get_visible_world_rect().grow(OFFSCREEN_MARGIN)

	# Le plus en retard d'abord, pour un ordre d'élimination cohérent
	# si plusieurs voitures sortent dans la même frame.
	var candidates := get_alive_states()
	candidates.sort_custom(func(a, b): return _is_ahead(b, a))

	for state in candidates:
		if get_alive_states().size() <= 1:
			break

		var car := state.car

		# Une voiture en cours de destruction / réapparition
		# (eau, obstacle...) n'est pas jugée tant qu'elle n'est pas revenue.
		if car._destruction_started or car._respawning:
			continue

		if not view.has_point(car.global_position):
			_eliminate(state)


func _eliminate(state: RaceParticipantState) -> void:
	state.eliminated = true
	elimination_order.append(state)

	if is_instance_valid(state.car):
		state.car.explosion()

	player_eliminated.emit(state)


func _end_round() -> void:
	if not round_active:
		return

	round_active = false

	var alive := get_alive_states()

	# Classement de la manche : survivant, puis éliminés du dernier
	# au premier.
	var ranking: Array[RaceParticipantState] = []
	ranking.append_array(alive)

	for i in range(elimination_order.size() - 1, -1, -1):
		ranking.append(elimination_order[i])

	var player_count := ranking.size()
	var awarded: Array[int] = []

	for i in range(player_count):
		var points := player_count - 1 - i
		ranking[i].points += points
		awarded.append(points)

	round_finished.emit(ranking, awarded)

	var survivor: RaceParticipantState = (
		ranking[0] if not ranking.is_empty() else null
	)

	_after_round(survivor)


func _after_round(survivor: RaceParticipantState) -> void:
	await get_tree().create_timer(ROUND_END_DELAY, false).timeout

	# Attendre la fin des explosions : une voiture dont l'effet se
	# termine demande une réapparition, qu'on ne veut pas après le
	# placement sur la grille.
	var waited := 0.0

	while _any_car_destroying() and waited < DESTRUCTION_WAIT_TIMEOUT:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()

	if controller.race_state != RaceController.RaceState.RUNNING:
		return

	var winner := get_score_leader()

	if winner != null and winner.points >= target_score:
		winner_found.emit(winner)
		controller.finish_elimination_race()
		return

	await _restart_round(survivor)


# ============================================================
# RESTART EN GRILLE INVERSÉE
# ============================================================

func _restart_round(survivor: RaceParticipantState) -> void:
	if survivor == null or not is_instance_valid(survivor.car):
		return

	round_restarting.emit()

	# Grille : premier éliminé devant, survivant derrière.
	var grid: Array[RaceParticipantState] = []
	grid.append_array(elimination_order)
	grid.append(survivor)

	var trail: PackedVector2Array = _trails.get(
		survivor.participant_id,
		PackedVector2Array()
	)

	var leader_transform := survivor.car.global_transform

	for slot in range(grid.size()):
		var state := grid[slot]

		var slot_transform := _get_grid_transform(
			trail,
			leader_transform,
			slot
		)

		state.car.place_for_restart(slot_transform)
		state.eliminated = false

		# Même progression que le survivant pour tous.
		state.current_lap = survivor.current_lap
		state.next_section = survivor.next_section
		state.has_started_lap = survivor.has_started_lap
		state.lap_start_time = survivor.lap_start_time
		state.respawn_transform = survivor.respawn_transform
		state.has_respawn_point = survivor.has_respawn_point
		state.last_progress_time = (
			survivor.last_progress_time + slot * 0.001
		)

	_trails.clear()

	await get_tree().create_timer(RESTART_FREEZE_TIME, false).timeout

	if controller.race_state != RaceController.RaceState.RUNNING:
		return

	for state in grid:
		if is_instance_valid(state.car):
			state.car.set_can_move(true)

	start_round()


## Position d'une place de grille : la place 0 est à la position du
## leader, les suivantes reculent le long de son chemin, en quinconce.
func _get_grid_transform(
	trail: PackedVector2Array,
	leader_transform: Transform2D,
	slot: int
) -> Transform2D:

	var distance_back := slot * GRID_SLOT_SPACING
	var lateral := (
		-GRID_LATERAL_OFFSET if slot % 2 == 0 else GRID_LATERAL_OFFSET
	)

	var origin := leader_transform.origin
	var forward := leader_transform.x.normalized()

	# Remonter le chemin parcouru.
	if trail.size() >= 2:
		var remaining := distance_back
		var i := trail.size() - 1

		origin = trail[i]

		while i > 0:
			var segment := trail[i] - trail[i - 1]
			var length := segment.length()

			if length <= 0.001:
				i -= 1
				continue

			forward = segment / length

			if remaining <= length:
				origin = trail[i] - forward * remaining
				remaining = 0.0
				break

			remaining -= length
			i -= 1
			origin = trail[i]

		# Trace trop courte : on continue tout droit.
		if remaining > 0.0:
			origin -= forward * remaining
	else:
		origin -= forward * distance_back

	var right := forward.orthogonal()

	return Transform2D(
		forward.angle(),
		origin + right * lateral
	)


func _record_trails() -> void:
	for state in controller.participants:
		if state.is_ai or state.eliminated:
			continue

		var car := state.car

		if not is_instance_valid(car):
			continue

		if car._destruction_started or car._respawning:
			continue

		var trail: PackedVector2Array = _trails.get(
			state.participant_id,
			PackedVector2Array()
		)

		var car_position := car.global_position

		if trail.size() > 0:
			var last := trail[trail.size() - 1]

			# Téléportation (réapparition) : on repart d'une trace neuve.
			if last.distance_to(car_position) > 400.0:
				trail.clear()
			elif last.distance_to(car_position) < TRAIL_SAMPLE_DISTANCE:
				continue

		trail.append(car_position)

		if trail.size() > TRAIL_MAX_POINTS:
			trail = trail.slice(trail.size() - TRAIL_MAX_POINTS)

		_trails[state.participant_id] = trail


# ============================================================
# REQUÊTES
# ============================================================

func get_alive_states() -> Array[RaceParticipantState]:
	var result: Array[RaceParticipantState] = []

	for state in controller.participants:
		if state.is_ai or state.eliminated:
			continue

		if not is_instance_valid(state.car):
			continue

		result.append(state)

	return result


## Joueur non éliminé le plus avancé sur le circuit (suivi par la caméra).
func get_leader_state() -> RaceParticipantState:
	var leader: RaceParticipantState = null

	for state in get_alive_states():
		if state.car._destruction_started or state.car._respawning:
			continue

		if leader == null or _is_ahead(state, leader):
			leader = state

	return leader


## Joueur avec le plus de points (null en cas d'égalité en tête).
func get_score_leader() -> RaceParticipantState:
	var best: RaceParticipantState = null
	var tie := false

	for state in controller.participants:
		if state.is_ai:
			continue

		if best == null or state.points > best.points:
			best = state
			tie = false
		elif state.points == best.points:
			tie = true

	return null if tie else best


func _any_car_destroying() -> bool:
	for state in controller.participants:
		if not is_instance_valid(state.car):
			continue

		if state.car._destruction_started or state.car._respawning:
			return true

	return false


## Progression : tours, sections franchies, puis distance à la
## prochaine section (plus proche = plus avancé).
func _is_ahead(a: RaceParticipantState, b: RaceParticipantState) -> bool:
	var progress_a := _get_progress(a)
	var progress_b := _get_progress(b)

	if progress_a != progress_b:
		return progress_a > progress_b

	return (
		_distance_to_next_section(a)
		< _distance_to_next_section(b)
	)


func _get_progress(state: RaceParticipantState) -> int:
	if not state.has_started_lap:
		return -1

	var section_count := controller.section_count

	# next_section vaut 0 quand il ne reste que la ligne d'arrivée :
	# c'est la fin du tour, pas le début.
	var section_index := state.next_section

	if section_index == 0:
		section_index = section_count

	return state.current_lap * (section_count + 1) + section_index


func _distance_to_next_section(state: RaceParticipantState) -> float:
	var target: Variant = _section_positions.get(state.next_section)

	if target == null or not is_instance_valid(state.car):
		return INF

	return state.car.global_position.distance_to(target)
