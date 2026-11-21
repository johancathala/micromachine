extends SceneTree

# ============================================================
# Allure de référence à partir d'un fantôme
#
#   godot --headless --path . -s tools/ai/build_pace_hint.gd -- \
#       --track=res://level/track/Track02.tscn \
#       --ghost=user://ghosts/track1_clio_jo.ghost \
#       --reference=clio \
#       --output=/tmp/opencode/pace_hint.json
#
# Le profil de vitesse de l'IA (difficulté donnée) est plus optimiste
# que le tour du joueur dans certains virages : l'IA y arrive trop vite
# et sort. On en déduit, point par point, un facteur
# « vitesse du fantôme / vitesse visée par l'IA » et on l'écrit au
# format d'AILearning (position + facteur), comme un apprentissage
# préalable. Les facteurs sont calculés avec une voiture de référence
# (celle du fantôme) : ils restent relatifs, donc valables pour les
# autres voitures.
#
# Le fichier produit se fusionne dans le seed (voir merge_learning.py)
# ou se charge avec --seed=... dans tools/ai/train_ai.gd.
# ============================================================

# Marge : l'IA vise un peu moins vite que le joueur.
const PACE_MARGIN := 0.97
# Facteurs bornés comme AILearning.
const MIN_FACTOR := 0.35
const MAX_FACTOR := 1.0
# Facteurs ignorés au-dessus de ce seuil (aucun ralentissement).
const KEEP_BELOW := 0.995
# Lissage des vitesses du fantôme et des facteurs (points).
const SMOOTH := 2
const GHOST_STRIDE := 4

const DEFAULT_CARS := ["dacia", "f1", "ferrari", "laguna", "police", "clio"]


func _initialize() -> void:
	await process_frame

	var args := _parse_args()
	var track_path: String = args.get("track", "")
	var ghost_path: String = args.get("ghost", "")
	var output: String = args.get("output", "")
	var reference: String = args.get("reference", "clio")
	var difficulty: int = int(args.get("difficulty", 2))
	var cars: Array = args.get("cars", DEFAULT_CARS)

	if track_path.is_empty() or ghost_path.is_empty() or output.is_empty():
		printerr("Usage: godot --headless --path . -s tools/ai/build_pace_hint.gd -- --track=res://... --ghost=user://... [--output=...] [--reference=clio] [--cars=...]")
		quit(1)
		return

	var CarScene: PackedScene = load("res://perso/car/Car.tscn")
	var TrackProgressScript: GDScript = load("res://level/script/TrackProgress.gd")
	var RacingLineScript: GDScript = load("res://level/script/ai/RacingLine.gd")
	var AIDriverScript: GDScript = load("res://level/script/ai/AIDriver.gd")
	var AILearningScript: GDScript = load("res://level/script/ai/AILearning.gd")
	var CarCatalogScript: GDScript = load("res://perso/car/definition/CarCatalog.gd")
	var ColorCatalogScript: GDScript = load("res://perso/car/definition/ColorCatalog.gd")
	AILearningScript.save_path = ""

	var track_scene := load(track_path) as PackedScene
	var track := track_scene.instantiate() as Node2D
	root.add_child(track)
	await process_frame

	var gates := _gate_segments(track)
	var progress = TrackProgressScript.new()
	if not progress.build(track, gates):
		printerr("TrackProgress : " + progress.last_error)
		quit(1)
		return

	var line = RacingLineScript.from_track(track, progress)
	if not line.is_valid():
		printerr("Pas de trajectoire pour " + track_path)
		quit(1)
		return
	print("Trajectoire : %s (%d points, %d px)" % [line.source, line.points.size(), line.length])

	var ghost := _read_ghost(ghost_path)
	if ghost.size() < 16:
		printerr("Fantôme illisible : " + ghost_path)
		quit(1)
		return

	# Voiture de référence (celle du fantôme) : son profil sert d'échelle.
	var definition = CarCatalogScript.get_car(reference)
	if definition == null:
		printerr("Voiture de référence inconnue : " + reference)
		quit(1)
		return

	var car = CarScene.instantiate()
	root.add_child(car)
	var color_data = ColorCatalogScript.get_color("blue")
	car.setup_car(definition, color_data["color"], 0, true, "ai", -1, null)
	var driver = AIDriverScript.new(car, line, difficulty, track_path)
	var profile: PackedFloat32Array = driver.speed_profile

	var speeds := _ghost_speeds(ghost)
	var factors := PackedFloat32Array()
	factors.resize(line.points.size())

	var ghost_index := 0
	for i in range(line.points.size()):
		ghost_index = _nearest_ghost(ghost, line.points[i], ghost_index)
		var target: float = profile[i]
		var human: float = speeds[ghost_index]
		var factor := 1.0
		if target > 1.0:
			factor = clampf(human * PACE_MARGIN / target, MIN_FACTOR, MAX_FACTOR)
		factors[i] = factor

	factors = _smooth_factors(factors, SMOOTH)

	var entries := []
	for i in range(line.points.size()):
		if factors[i] < KEEP_BELOW:
			entries.append([
				snappedf(line.points[i].x, 0.1),
				snappedf(line.points[i].y, 0.1),
				snappedf(factors[i], 0.001),
			])

	var data := {}
	for car_id in cars:
		var key: String = AILearningScript.make_key(track_path, String(car_id))
		data[key] = entries

	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Écriture impossible : " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	var min_factor := 1.0
	for factor in factors:
		min_factor = minf(min_factor, factor)
	print("Allure : facteur min %.3f, %d points retenus, référence %s (difficulté %d)" % [
		min_factor, entries.size(), reference, difficulty,
	])
	print("Vitesse du fantôme : min %d, moy %d, max %d px/s" % [
		int(_min(speeds)), int(_average(speeds)), int(_max(speeds)),
	])
	print("Écrit : %s" % output)
	quit()


func _read_ghost(path: String) -> PackedVector2Array:
	var points := PackedVector2Array()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return points

	var data: Variant = file.get_var()
	file.close()
	if not data is Dictionary:
		return points

	var samples: PackedFloat32Array = (data as Dictionary).get("samples", PackedFloat32Array())
	for i in range(0, samples.size() - GHOST_STRIDE + 1, GHOST_STRIDE):
		points.append(Vector2(samples[i + 1], samples[i + 2]))
	return points


## Vitesse (px/s) à chaque échantillon, par différence centrée.
func _ghost_speeds(points: PackedVector2Array) -> PackedFloat32Array:
	var speeds := PackedFloat32Array()
	speeds.resize(points.size())
	for i in range(points.size()):
		var a := maxi(i - 1, 0)
		var b := mini(i + 1, points.size() - 1)
		# 1/30 s par échantillon (GhostManager enregistre à 30 Hz).
		var dt := float(b - a) / 30.0
		speeds[i] = points[a].distance_to(points[b]) / maxf(dt, 0.0001)
	return speeds


## Indice du fantôme le plus proche, autour de `hint` (suivi continu).
func _nearest_ghost(points: PackedVector2Array, target: Vector2, hint: int) -> int:
	var best := hint
	var best_distance := INF

	for offset in range(-40, 41):
		var i := posmod(hint + offset, points.size())
		var d := points[i].distance_squared_to(target)
		if d < best_distance:
			best_distance = d
			best = i

	# Le fantôme et la ligne peuvent se décaler : recherche complète si
	# le voisinage ne contient rien de proche.
	if best_distance > 150.0 * 150.0:
		for i in range(points.size()):
			var d := points[i].distance_squared_to(target)
			if d < best_distance:
				best_distance = d
				best = i

	return best


func _smooth_factors(factors: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(factors.size())
	for i in range(factors.size()):
		var sum := 0.0
		var weight := 0.0
		for offset in range(-radius, radius + 1):
			var w := float(radius + 1 - absi(offset))
			sum += factors[posmod(i + offset, factors.size())] * w
			weight += w
		result[i] = sum / weight
	return result


func _min(values: PackedFloat32Array) -> float:
	var result := INF
	for value in values:
		result = minf(result, value)
	return result


func _max(values: PackedFloat32Array) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, value)
	return result


func _average(values: PackedFloat32Array) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxf(values.size(), 1)


func _gate_segments(track: Node) -> Dictionary:
	var gates := {}
	var sections := track.get_node_or_null("Sections")
	if sections == null:
		return gates

	for section in sections.get_children():
		for child in section.get_children():
			if child is CollisionShape2D and child.shape is SegmentShape2D:
				var segment: SegmentShape2D = child.shape
				gates[section.section_id] = [child.to_global(segment.a), child.to_global(segment.b)]
	return gates


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("--") and text.contains("="):
			var key := text.substr(2, text.find("=") - 2)
			var value := text.substr(text.find("=") + 1)
			if key == "cars":
				result[key] = Array(value.split(",", false))
			else:
				result[key] = value
	return result
