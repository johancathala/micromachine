extends Node2D
class_name RaceStartLights


# ============================================================
# SIGNAUX
# ============================================================

signal start_sequence_started()
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


# ============================================================
# ÉTAT
# ============================================================

var lights: Array[RaceStartLight] = []

var sequence_running: bool = false


# ============================================================
# INITIALISATION
# ============================================================

func _ready() -> void:

	_collect_lights()

	reset()


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


# ============================================================
# RESET
# ============================================================

func reset() -> void:

	sequence_running = false

	for light in lights:

		light.set_orange()


# ============================================================
# SÉQUENCE DE DÉPART
# ============================================================

func start_sequence() -> void:

	if sequence_running:
		return

	if lights.is_empty():
		push_error("RaceStartLights : aucun feu disponible.")
		return

	reset()
	
	sequence_running = true

	start_sequence_started.emit()

	await _run_red_sequence()

	if not sequence_running:
		return

	await _wait_before_green()

	if not sequence_running:
		return

	_set_all_green()

	sequence_running = false

	start_sequence_finished.emit()


# ============================================================
# SÉQUENCE ORANGE → ROUGE
# ============================================================
func _run_red_sequence() -> void:

	await get_tree().create_timer(
			LIGHT_INTERVAL
		).timeout

	for light in lights:
		if not sequence_running:
			return
			
		light.set_red()

		_play_light_sound()

		await get_tree().create_timer(
			LIGHT_INTERVAL
		).timeout


# ============================================================
# ATTENTE AVANT LE VERT
# ============================================================

func _wait_before_green() -> void:

	var delay := randf_range(
		GREEN_DELAY_MIN,
		GREEN_DELAY_MAX
	)

	print(
		"RaceStartLights : délai avant vert = %.3f s"
		% delay
	)

	await get_tree().create_timer(
		delay
	).timeout


# ============================================================
# PASSAGE AU VERT
# ============================================================

func _set_all_green() -> void:

	for light in lights:

		light.set_green()

	_play_green_sound()


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
