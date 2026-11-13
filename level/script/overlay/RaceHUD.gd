extends Control
class_name RaceHUD

const PARTICIPANT_ROW_SCENE := preload(
    "res://level/scene/RaceParticipantHUD.tscn"
)

@onready var lap_label: Label = $MarginContainer/HBoxContainer/LeftPanel/Top/Lap
@onready var first_participant_label: Label = $MarginContainer/HBoxContainer/LeftPanel/Top/FirstParticipant
@onready var best_lap_label: Label = $MarginContainer/HBoxContainer/LeftPanel/Top/BestLap
@onready var race_time_label: Label = $MarginContainer/HBoxContainer/LeftPanel/Top/RaceTime
@onready var message_label: Label = $MarginContainer/MessageLayer/MessageLabel
@onready var light_start: Node2D = $MarginContainer/FeuLayer/FeuDepart

@onready var participant_list: VBoxContainer = $MarginContainer/HBoxContainer/RightPanel

var participant_rows: Dictionary = {}

var race_controller: RaceController = null
var race_world: RaceWorld = null

var displayed_participant_id: int = -1
var displayed_car: Car = null

var race_started: bool = false
var best_lap : float = 0.0

# Évite qu'un ancien message masque un message plus récent.
var _message_id: int = 0

func initialize(
	controller: RaceController,
	world: RaceWorld
) -> void:

	race_controller = controller
	race_world = world

	_select_displayed_participant()
	_connect_controller_signals()

	_update_static_values()
	
	_build_participant_rows()
	
	start_message()


func _process(_delta: float) -> void:
	if race_controller == null:
		return

	_update_race_time()
	_update_displayed_car()
	
	for state in race_controller.get_participant_states():

		var row = participant_rows.get(
			state.participant_id
		)

		if row == null:
			continue
		
		row.refresh()


func _connect_controller_signals() -> void:

	if not race_controller.race_started.is_connected(
		_on_race_started
	):
		race_controller.race_started.connect(
			_on_race_started
		)

	if not race_controller.participant_lap_completed.is_connected(
		_on_participant_lap_completed
	):
		race_controller.participant_lap_completed.connect(
			_on_participant_lap_completed
		)

	if not race_controller.participant_finished.is_connected(
		_on_participant_finished
	):
		race_controller.participant_finished.connect(
			_on_participant_finished
		)

	if not race_controller.positions_changed.is_connected(
		_on_positions_changed
	):
		race_controller.positions_changed.connect(
			_on_positions_changed
	)

	if not race_controller.race_finished.is_connected(
		_on_race_finished
	):
		race_controller.race_finished.connect(
			_on_race_finished
	)

	race_controller.start_reactions_judged.connect(
		_on_start_reactions_judged
	)

	if race_controller.pit_stops != null:
		var pits := race_controller.pit_stops

		pits.box_requested.connect(_on_box_requested)
		pits.pit_started.connect(_on_pit_changed.bind(""))
		pits.pit_progress.connect(func(state, _i): _on_pit_changed(state, []))
		pits.pit_error.connect(func(state): _on_pit_changed(state, [], "ERREUR ! On recommence"))
		pits.pit_finished.connect(_on_pit_finished)

	if race_controller.is_elimination_mode():
		var rules := race_controller.elimination_rules

		rules.player_eliminated.connect(_on_player_eliminated)
		rules.round_finished.connect(_on_round_finished)
		rules.round_restarting.connect(_on_round_restarting)
		rules.winner_found.connect(_on_winner_found)


# ------------------------------------------------------------------
# MODE ÉLIMINATION
# ------------------------------------------------------------------
func _show_message(text: String, duration: float = 0.0) -> void:
	_message_id += 1
	var id := _message_id

	message_label.text = text
	message_label.show()

	if duration <= 0.0:
		return

	await get_tree().create_timer(duration, false).timeout

	if id == _message_id:
		message_label.hide()


# ------------------------------------------------------------------
# USURE DES PNEUS / STAND
# ------------------------------------------------------------------
var _qte_label: Label = null


func _on_box_requested(state: RaceParticipantState, wear: float) -> void:
	_show_message(
		"%s : BOX, BOX ! (pneus usés à %d %%)" % [
			state.nickname.to_upper(),
			int(wear * 100.0)
		],
		3.0
	)


func _get_qte_label() -> Label:
	if _qte_label == null:
		_qte_label = Label.new()
		_qte_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_qte_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_qte_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_qte_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_qte_label.offset_bottom = -60.0
		_qte_label.add_theme_font_size_override("font_size", 40)
		_qte_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_qte_label.add_theme_constant_override("outline_size", 10)
		add_child(_qte_label)

	return _qte_label


## Une ligne par joueur au stand : directions réussies entre
## crochets, direction attendue soulignée par des chevrons.
func _refresh_qte_label(notice: Dictionary = {}) -> void:
	var lines: PackedStringArray = []

	for state in race_controller.get_participant_states():
		var qte := race_controller.pit_stops.get_qte(state)

		if qte.is_empty():
			continue

		var parts: PackedStringArray = []
		var sequence: Array = qte["sequence"]

		for i in range(sequence.size()):
			var symbol: String = PitStopManager.DIRECTION_SYMBOLS[sequence[i]]

			if i < qte["index"]:
				parts.append("[%s]" % symbol)
			elif i == qte["index"]:
				parts.append("> %s <" % symbol)
			else:
				parts.append(symbol)

		var line := "%s AU STAND :  %s" % [state.nickname.to_upper(), "  ".join(parts)]

		if notice.has(state):
			line += "   " + String(notice[state])

		lines.append(line)

	var label := _get_qte_label()
	label.text = "\n".join(lines)
	label.visible = not lines.is_empty()


func _on_pit_changed(state: RaceParticipantState, _sequence: Variant, notice: String = "") -> void:
	_refresh_qte_label({state: notice} if not notice.is_empty() else {})


func _on_pit_finished(state: RaceParticipantState) -> void:
	_refresh_qte_label()
	_show_message("%s : PNEUS NEUFS !" % state.nickname.to_upper(), 2.0)


func _on_start_reactions_judged(results: Array) -> void:
	var parts: PackedStringArray = []

	for result in results:
		var state: RaceParticipantState = result["state"]
		var reaction: float = result["reaction"]
		var effect: float = result["effect"]
		var text := state.nickname + " : "

		if effect < 0.0:
			text += "FAUX DÉPART (%.2f s trop tôt)" % -reaction
		elif effect >= RaceController.START_BONUS_MAX * 0.75:
			text += "DÉPART CANON ! %.2f s" % reaction
		elif effect > 0.0:
			text += "bon départ %.2f s" % reaction
		else:
			text += "départ lent"

		parts.append(text)

	_show_message("\n".join(parts), 3.0)


func _on_player_eliminated(state: RaceParticipantState) -> void:
	_show_message("%s ÉLIMINÉ !" % state.nickname.to_upper(), 1.5)


func _on_round_finished(ranking: Array, awarded_points: Array) -> void:
	var parts: PackedStringArray = []

	for i in range(ranking.size()):
		parts.append("%s +%d" % [ranking[i].nickname, awarded_points[i]])

	_show_message(
		"MANCHE %d : %s" % [
			race_controller.elimination_rules.round_number,
			"  ·  ".join(parts)
		]
	)


func _on_round_restarting() -> void:
	_show_message("RESTART : GRILLE INVERSÉE !", 2.0)


func _on_winner_found(state: RaceParticipantState) -> void:
	_show_message(
		"%s GAGNE AVEC %d POINTS !" % [
			state.nickname.to_upper(),
			state.points
		]
	)


# ------------------------------------------------------------------
# INITIALISATION
# ------------------------------------------------------------------
func _select_displayed_participant() -> void:
	if race_controller == null:
		return

	var states: Array[RaceParticipantState] = (
		race_controller.get_participant_states()
	)

	if states.is_empty():
		return

	# 1. Priorité au clavier.
	for state in states:
		if state.input_device_type == "keyboard":
			displayed_participant_id = state.participant_id
			return

	# 2. Premier joueur humain.
	for state in states:
		if not state.is_ai:
			displayed_participant_id = state.participant_id
			return

	# 3. Cas de secours : premier participant.
	displayed_participant_id = states[0].participant_id


func _update_displayed_car() -> void:
	if race_world == null:
		return

	var cars_root := race_world.get_cars_root()

	if cars_root == null:
		return

	for child in cars_root.get_children():
		var car := child as Car

		if car == null:
			continue

		if car.participant_id == displayed_participant_id:
			displayed_car = car
			return

func _build_participant_rows() -> void:

	# Nettoyage éventuel
	for child in participant_list.get_children():
		child.queue_free()

	participant_rows.clear()

	for state in race_controller.get_participant_states():

		var row := PARTICIPANT_ROW_SCENE.instantiate()

		participant_list.add_child(row)

		row.setup(state,race_controller)

		participant_rows[state.participant_id] = row

func start_message() -> void:
	message_label.text = "PREPAREZ VOUS AU DEPART !"
	message_label.show()
	await get_tree().create_timer(3).timeout
	message_label.text = "N'ACCELEREZ PAS AVANT LES FEUX VERTS !"
	await get_tree().create_timer(4).timeout
	message_label.hide()
	

# ------------------------------------------------------------------
# COURSE
# ------------------------------------------------------------------
func _update_race_time() -> void:
	if race_controller == null:
		return

	if not race_started:
		return

	var race_time := race_controller.get_race_time()

	race_time_label.text = (
		"Temps de course : %s"
		% _format_time(race_time)
	)


func _update_first_participant_values(state: RaceParticipantState) -> void:
	if race_controller == null:
		return
	
	var current_lap = state.current_lap

	var lap_count : int = race_controller.get_lap_count()

	lap_label.text = (
		"Tour %d/%d"
		% [
			current_lap,
			lap_count
		]
	)
	
	first_participant_label.text = "Leader de la course : "+state.nickname

	if race_controller.is_elimination_mode():
		lap_label.text = "Élimination : %d points pour gagner" % (
			race_controller.elimination_rules.target_score
		)
		first_participant_label.text = "En tête aux points : %s (%d)" % [
			state.nickname,
			state.points
		]

func _update_best_lap(state: RaceParticipantState) -> void:
	if race_controller == null:
		return
	
	var lap_time = state.best_lap_time
	if lap_time >= best_lap && best_lap > 0.0:
		return
	
	best_lap = state.best_lap_time

	best_lap_label.text = (
		"Meilleur temps : %s"
		% _format_time(best_lap)
	)

# ------------------------------------------------------------------
# ÉVÉNEMENTS DE COURSE
# ------------------------------------------------------------------
func _on_race_started() -> void:
	race_started = true

func _on_participant_finished(
	state: RaceParticipantState
) -> void:

	if state.participant_id != displayed_participant_id:
		return


func _on_positions_changed(state: RaceParticipantState) -> void:
	_update_first_participant_values(state)

func _on_participant_lap_completed(state: RaceParticipantState) -> void:
	_update_best_lap(state)


func _on_race_finished() -> void:
	race_started = false

	# En élimination, le message du vainqueur reste affiché.
	if race_controller.is_elimination_mode():
		return

	message_label.text = "FIN DE LA COURSE !"
	message_label.show()


# ------------------------------------------------------------------
# INFORMATIONS STATIQUES
# ------------------------------------------------------------------

func _update_static_values() -> void:
	if race_controller == null:
		return

	var lap_count : int = race_controller.get_lap_count()

	lap_label.text = "Tour 0/%d" % lap_count

	if race_controller.is_elimination_mode():
		lap_label.text = "Élimination : %d points pour gagner" % (
			race_controller.elimination_rules.target_score
		)
	race_time_label.text = "Temps de course : 0.00"


func _format_time(time_seconds: float) -> String:

	if time_seconds <= 0.0:
		return "--:--.--"

	var minutes := int(time_seconds / 60)
	var seconds := int(time_seconds) % 60

	var centiseconds := int(
		(time_seconds - floor(time_seconds)) * 100.0
	)

	return "%02d:%02d.:%02d" % [
		minutes,
		seconds,
		centiseconds
	]
