extends Node2D
class_name RaceStartLights

#const MAP := preload("res://level/track/Track01.tscn")

# ============================================================
# SIGNAUX
# ============================================================
signal start_sequence_finished()


# ============================================================
# CONFIGURATION
# ============================================================
const LIGHT_INTERVAL := 1.3

const GREEN_DELAY_MIN := 0.5
const GREEN_DELAY_MAX := 4.0


# ============================================================
# NŒUDS
# ============================================================
@onready var sound_light: AudioStreamPlayer = $SoundLight
@onready var sound_green: AudioStreamPlayer = $SoundGreen
@onready var sequence_timer: Timer = $SequenceTimer


# ============================================================
# ÉTAT
# ============================================================
var start_lights_map: Node2D = null
var lights: Array[RaceStartLight] = []
var lights_map: Array[RaceStartLight] = []

var sequence_running: bool = false


# ============================================================
# INITIALISATION
# ============================================================
func _ready() -> void:
	sequence_running = false

func _collect_lights() -> void:

	lights.clear()

	for child in get_children():

		var light := child as RaceStartLight

		if light != null:
			lights.append(light)

	print(
		"RaceStartLights : %d feu(x) trouvé(s)."
		% lights.size()
	)


func _collect_lights_map() -> void:

	var race_start_light_map := _get_start_lights_map()
	
	lights_map.clear()

	for child in race_start_light_map.get_children():

		var light := child as RaceStartLight

		if light != null:
			lights_map.append(light)

	print(
		"RaceStartLights_map : %d feu(x) trouvé(s)."
		% lights_map.size()
	)

func _get_start_lights_map() -> Node2D:

	var node := get_tree().get_first_node_in_group(
		"race_start_lights_map"
	)

	return node as Node2D

# ============================================================
# RESET
# ============================================================
func reset() -> void:

	print("RaceStartLights : reset des lights")
	
	sequence_timer.stop()
	sequence_running = false

	for light in lights:

		light.set_orange()
	
	for light in lights_map:

		light.set_orange()
	
	show()


# ============================================================
# SÉQUENCE DE DÉPART
# ============================================================
func start_sequence() -> void:

	_collect_lights()
	_collect_lights_map()
	
	if sequence_running:
		push_error("Une sequence de démarrage est déjà en cours")
		return

	if lights.is_empty():
		push_error("RaceStartLights : aucun feu disponible.")
		return
	
	if lights_map.is_empty():
		push_error("RaceStartLights_map : aucun feu disponible sur la map.")

	reset()
	
	sequence_running = true

	await _run_red_sequence()

	if not sequence_running:
		push_error("RaceStartLights_map : la séquence a été coupée")
		return

	await _wait_before_green()

	if not sequence_running:
		push_error("RaceStartLights_map : la séquence a été coupée")
		return

	_set_all_green()

	sequence_running = false

	start_sequence_finished.emit()


# ============================================================
# SÉQUENCE ORANGE → ROUGE
# ============================================================

func _run_red_sequence() -> void:
	print("RED SEQUENCE : début")

	if not sequence_running:
		push_error("Séquence annulée")
		return

	await _wait_seconds(LIGHT_INTERVAL)

	var id_light := 0
	for light in lights:
		if not sequence_running:
			return

		_play_light_sound()
		light.set_red()
		lights_map[id_light].set_red()

		await _wait_seconds(LIGHT_INTERVAL)
		id_light += 1


# ============================================================
# ATTENTE AVANT LE VERT
# ============================================================
func _wait_before_green() -> void:

	print("RaceStartLights : démarrage attente green sequence")
	var delay := randf_range(
		GREEN_DELAY_MIN,
		GREEN_DELAY_MAX
	)

	await _wait_seconds(delay)


# ============================================================
# PASSAGE AU VERT
# ============================================================
func _set_all_green() -> void:

	print("RaceStartLights : passage au vert")
	var id_light = 0
	for light in lights:

		light.set_green()
		lights_map.get(id_light).set_green()
		id_light += 1

	_play_green_sound()
	
	await _wait_seconds(2.0)
	
	hide()


# ============================================================
# Gestion du Timer
# ============================================================
func _wait_seconds(duration: float) -> void:
	print("TIMER : demande de démarrage, durée = ", duration)

	sequence_timer.stop()
	sequence_timer.wait_time = duration
	sequence_timer.one_shot = true

	sequence_timer.start()

	print("TIMER : en cours = ", sequence_timer.time_left > 0.0)

	await sequence_timer.timeout

	print("TIMER : coroutine reprise")


# ============================================================
# SONS
# ============================================================
func _play_light_sound() -> void:

	if sound_light == null:
		return

	sound_light.play()


func _play_green_sound() -> void:

	if sound_green == null:
		return

	sound_green.play()


# ============================================================
# ANNULATION
# ============================================================

func cancel_sequence() -> void:

	sequence_running = false
