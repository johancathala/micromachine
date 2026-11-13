extends Node
class_name GhostManager

# ============================================================
# FANTÔMES (mode contre-la-montre)
# ============================================================
#
# - Chaque tour du joueur est enregistré (position + orientation,
#   30 fois par seconde, temps relatif au début du tour).
# - Un fantôme par circuit, par voiture et par joueur (pseudo),
#   sauvegardé dans user://ghosts/. Le « meilleur fantôme » est le plus
#   rapide de tous les joueurs pour ce circuit et cette voiture.
# - Fantômes affichés selon le choix du joueur : le meilleur, le sien,
#   ou les deux (un seul si le record est le sien).
# - Chaque fantôme (voiture semi-transparente, sans collision, avec son
#   nom et son temps) refait son tour à chaque début de tour du joueur.
# - Un tour avec explosion ou réapparition n'est pas retenu.
# ============================================================

signal new_record(state: RaceParticipantState, lap_time: float, previous_time: float, absolute: bool)

enum GhostMode { BOTH, BEST, OWN }

const GHOST_DIR := "user://ghosts/"
const SAMPLE_INTERVAL := 1.0 / 30.0
const GHOST_ALPHA := 0.45
const BEST_GHOST_COLOR := Color("#ffd54f")
# Valeurs par échantillon : temps, x, y, orientation.
const STRIDE := 4

var controller: RaceController = null
var state: RaceParticipantState = null
var track_id := -1
var car_id := ""
var car_color := Color.WHITE
var mode: GhostMode = GhostMode.BOTH

# Fantômes : meilleur de tous, et celui du joueur.
var best_ghost: Dictionary = {}
var own_ghost: Dictionary = {}

# Fantômes affichés : [{data, node, label}].
var _shown: Array[Dictionary] = []

# Enregistrement du tour en cours.
var _samples := PackedFloat32Array()
var _lap_start := -1.0
var _next_sample_time := 0.0
var _lap_valid := true
var _laps_done := 0


func setup(p_controller: RaceController, p_mode: int) -> void:
	controller = p_controller
	mode = p_mode as GhostMode
	track_id = int(controller.race_config.track.get("id", -1))

	for participant_state in controller.participants:
		if not participant_state.is_ai:
			state = participant_state
			break

	if state == null or not is_instance_valid(state.car):
		return

	car_id = state.car.definition.id if state.car.definition else ""

	for participant in controller.race_config.participants:
		if int(participant.get("participant_id", -1)) == state.participant_id:
			var color_data := ColorCatalog.get_color(String(participant.get("color_id", "")))
			car_color = color_data.get("color", Color.WHITE)

	own_ghost = load_ghost_file(ghost_path(track_id, car_id, state.nickname))
	best_ghost = load_best_ghost(track_id, car_id)
	_refresh_shown_ghosts()


# ------------------------------------------------------------
# Fichiers
# ------------------------------------------------------------

static func player_key(nickname: String) -> String:
	var key := ""

	for character in nickname.strip_edges().to_lower():
		key += character if (character >= "a" and character <= "z") or (character >= "0" and character <= "9") else "_"

	return key if not key.is_empty() else "joueur"


static func ghost_path(p_track_id: int, p_car_id: String, nickname: String) -> String:
	return GHOST_DIR + "track%d_%s_%s.ghost" % [p_track_id, p_car_id, player_key(nickname)]


static func load_ghost_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return {}

	var data: Variant = file.get_var()

	if not data is Dictionary or not (data as Dictionary).has("samples"):
		return {}

	return data


## Fantôme le plus rapide, tous joueurs confondus, pour ce circuit et
## cette voiture.
static func load_best_ghost(p_track_id: int, p_car_id: String) -> Dictionary:
	var best: Dictionary = {}
	var prefix := "track%d_%s_" % [p_track_id, p_car_id]
	var directory := DirAccess.open(GHOST_DIR)

	if directory == null:
		return best

	for file_name in directory.get_files():
		if not file_name.begins_with(prefix) or not file_name.ends_with(".ghost"):
			continue

		var data := load_ghost_file(GHOST_DIR + file_name)

		if data.is_empty():
			continue

		if best.is_empty() or float(data["lap_time"]) < float(best["lap_time"]):
			best = data

	return best


func _save_ghost(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GHOST_DIR))

	var path := ghost_path(track_id, car_id, state.nickname)
	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		push_warning("Fantôme : impossible d'enregistrer " + path)
		return

	file.store_var(data)


# ------------------------------------------------------------
# Enregistrement
# ------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if controller == null or state == null or not is_instance_valid(state.car):
		return

	if controller.race_state == RaceController.RaceState.COUNTDOWN:
		return

	if not state.has_started_lap:
		return

	# Tour terminé : candidat au record.
	if state.lap_records.size() > _laps_done:
		_laps_done = state.lap_records.size()
		var lap_time := float(state.lap_records[_laps_done - 1].get("lap_time", 0.0))

		if _lap_valid and _samples.size() >= STRIDE * 2 and lap_time > 0.0:
			_consider_lap(lap_time)

	# Nouveau tour : nouvel enregistrement.
	if not is_equal_approx(state.lap_start_time, _lap_start):
		_lap_start = state.lap_start_time
		_samples = PackedFloat32Array()
		_next_sample_time = 0.0
		_lap_valid = true

	var car := state.car

	if car._destruction_started or car._respawning:
		_lap_valid = false

	var lap_time_now := controller.get_race_time() - state.lap_start_time

	if not state.finished and lap_time_now >= _next_sample_time:
		_samples.append_array(PackedFloat32Array([
			lap_time_now, car.global_position.x, car.global_position.y, car.global_rotation
		]))
		_next_sample_time += SAMPLE_INTERVAL

	for shown in _shown:
		_update_ghost(shown, lap_time_now)


func _consider_lap(lap_time: float) -> void:
	var previous_own := float(own_ghost.get("lap_time", INF))

	if lap_time >= previous_own:
		return

	var previous_best := float(best_ghost.get("lap_time", INF))

	var data := {
		"lap_time": lap_time,
		"nickname": state.nickname,
		"car_id": car_id,
		"color": car_color.to_html(),
		"track_id": track_id,
		"samples": _samples
	}

	_save_ghost(data)
	own_ghost = data

	var absolute := lap_time < previous_best

	if absolute:
		best_ghost = data

	new_record.emit(state, lap_time, previous_own, absolute)

	# Les fantômes affichés au tour suivant tiennent compte du record.
	_refresh_shown_ghosts()


# ------------------------------------------------------------
# Affichage
# ------------------------------------------------------------

## Fantômes à afficher selon le mode (un seul si le meilleur est celui
## du joueur).
func _wanted_ghosts() -> Array[Dictionary]:
	var wanted: Array[Dictionary] = []
	var best_is_own := (
		not best_ghost.is_empty()
		and player_key(String(best_ghost.get("nickname", ""))) == player_key(state.nickname)
	)

	if mode != GhostMode.OWN and not best_ghost.is_empty():
		wanted.append(best_ghost)

	if mode != GhostMode.BEST and not own_ghost.is_empty() and not (best_is_own and mode == GhostMode.BOTH):
		wanted.append(own_ghost)

	return wanted


func _refresh_shown_ghosts() -> void:
	for shown in _shown:
		(shown["node"] as Node).queue_free()

	_shown.clear()

	for data in _wanted_ghosts():
		var is_best := data == best_ghost
		var node := _create_ghost_node(data, is_best)

		if node != null:
			_shown.append({"data": data, "node": node})


func get_shown_ghosts() -> Array[Dictionary]:
	return _shown


func _update_ghost(shown: Dictionary, lap_time_now: float) -> void:
	var node: Node2D = shown["node"]
	var samples: PackedFloat32Array = shown["data"]["samples"]
	var count := samples.size() / STRIDE

	# Fantôme visible pendant son tour, puis il attend le tour suivant.
	if state.finished or count < 2 or lap_time_now > samples[(count - 1) * STRIDE]:
		node.hide()
		return

	# Recherche dichotomique de l'échantillon.
	var low := 0
	var high := count - 1

	while high - low > 1:
		var middle := (low + high) / 2

		if samples[middle * STRIDE] <= lap_time_now:
			low = middle
		else:
			high = middle

	var t0 := samples[low * STRIDE]
	var t1 := samples[high * STRIDE]
	var weight := clampf((lap_time_now - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0)

	var a := Vector2(samples[low * STRIDE + 1], samples[low * STRIDE + 2])
	var b := Vector2(samples[high * STRIDE + 1], samples[high * STRIDE + 2])

	node.global_position = a.lerp(b, weight)
	(node.get_node("Body") as Node2D).global_rotation = lerp_angle(
		samples[low * STRIDE + 3], samples[high * STRIDE + 3], weight
	)
	node.show()


## Voiture fantôme : modèle de la voiture, semi-transparent, sans
## collision ni son, avec le nom et le temps au-dessus.
func _create_ghost_node(data: Dictionary, is_best: bool) -> Node2D:
	var definition := CarCatalog.get_car(String(data.get("car_id", car_id)))

	if definition == null or definition.model_scene == null:
		return null

	var node := Node2D.new()
	node.name = "BestGhost" if is_best else "OwnGhost"
	node.z_index = 1

	# Le corps tourne avec la voiture, l'étiquette reste droite.
	var body := Node2D.new()
	body.name = "Body"
	node.add_child(body)

	var model := definition.model_scene.instantiate()
	body.add_child(model)

	for sound in model.find_children("*", "AudioStreamPlayer2D", true, false):
		sound.queue_free()

	var color := BEST_GHOST_COLOR if is_best else Color.from_string(String(data.get("color", "")), car_color)
	body.modulate = Color(color.r, color.g, color.b, GHOST_ALPHA)

	var label := Label.new()
	label.text = "%s %s  %s" % [
		"★" if is_best else "",
		String(data.get("nickname", "")),
		_format_time(float(data.get("lap_time", 0.0)))
	]
	label.position = Vector2(-110, -120)
	label.custom_minimum_size = Vector2(220, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(color, 0.85))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 8)
	node.add_child(label)

	node.hide()
	controller.race_world.get_cars_root().add_child(node)
	return node


static func _format_time(seconds: float) -> String:
	return "%d:%05.2f" % [int(seconds / 60.0), fmod(seconds, 60.0)]
