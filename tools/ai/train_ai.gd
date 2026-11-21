extends SceneTree

# Entraînement headless des IA sur un circuit : elles roulent, les
# chocs en solo ralentissent les virages fautifs (AILearning), puis le
# résultat est écrit dans le fichier d'apprentissage fourni.

# Chargés à l'exécution (et non en preload) : en mode -s, les autoloads
# ne sont enregistrés pour le compilateur qu'après la première frame.
var CarScene: PackedScene
var TrackProgressScript: GDScript
var RacingLineScript: GDScript
var AIDriverScript: GDScript
var AILearningScript: GDScript
var AIStyleScript: GDScript
var CarCatalogScript: GDScript
var ColorCatalogScript: GDScript

const DEFAULT_CARS := ["dacia", "f1", "ferrari", "laguna", "police", "clio"]
const COLOR := "blue"


func _initialize() -> void:
	await process_frame
	CarScene = load("res://perso/car/Car.tscn")
	TrackProgressScript = load("res://level/script/TrackProgress.gd")
	RacingLineScript = load("res://level/script/ai/RacingLine.gd")
	AIDriverScript = load("res://level/script/ai/AIDriver.gd")
	AILearningScript = load("res://level/script/ai/AILearning.gd")
	AIStyleScript = load("res://level/script/ai/AIStyle.gd")
	CarCatalogScript = load("res://perso/car/definition/CarCatalog.gd")
	ColorCatalogScript = load("res://perso/car/definition/ColorCatalog.gd")

	var args := _parse_args()
	var track_path: String = args.get("track", "")
	var cars: Array = args.get("cars", DEFAULT_CARS)
	var laps: int = int(args.get("laps", 12))
	var difficulty: int = int(args.get("difficulty", 2))
	var output: String = args.get("output", "res://level/script/ai/ai_learning.json")
	var seed_path: String = args.get("seed", "")
	var learn: bool = String(args.get("learn", "1")) != "0"
	var styles: Array = args.get("styles", _all_styles())

	if track_path.is_empty():
		printerr("Usage: godot --headless --fixed-fps 60 --path . -s tools/ai/train_ai.gd -- --track=res://level/track/Track02.tscn [--cars=dacia,f1] [--styles=equilibre,agressif] [--laps=12] [--difficulty=2] [--output=res://level/script/ai/ai_learning.json]")
		quit(1)
		return

	# Écrit dans le fichier cible (seed), pas dans les données du joueur.
	# save_path vide pendant le chargement : évite de fusionner deux fois
	# le seed quand la sortie est le seed lui-même.
	AILearningScript.save_path = ""
	if seed_path.is_empty():
		AILearningScript.reset(true)
	else:
		AILearningScript.reset(false)
		AILearningScript._merge_file(seed_path)
	AILearningScript.save_path = output

	var track_scene := load(track_path) as PackedScene
	if track_scene == null:
		printerr("Circuit introuvable : " + track_path)
		quit(1)
		return

	var track := track_scene.instantiate() as Node2D
	var world := Node2D.new()
	world.name = "World"
	root.add_child(world)

	var track_root := Node2D.new()
	track_root.name = "Track"
	world.add_child(track_root)
	track_root.add_child(track)

	var cars_root := Node2D.new()
	cars_root.name = "Cars"
	world.add_child(cars_root)

	var skid_marks := Node2D.new()
	skid_marks.name = "SkidMarks"
	world.add_child(skid_marks)

	var progress = TrackProgressScript.new()
	var gates := _gate_segments(track)
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
	print("Styles : %s | tours : %d | difficulté : %d" % [", ".join(PackedStringArray(styles)), laps, difficulty])

	var spawn := _spawn_transform(track)
	var target_distance := float(laps) * float(line.length)
	var track_name := track_path.get_file().get_basename()

	for car_id in cars:
		car_id = String(car_id).strip_edges()
		if car_id.is_empty():
			continue

		var total_crashes := 0
		var total_learned := 0
		var total_driven := 0.0
		var total_frames := 0

		for style_id in styles:
			style_id = String(style_id).strip_edges()
			if style_id.is_empty():
				continue
			if not AIStyleScript.has_style(style_id):
				printerr("Style inconnu : " + style_id)
				continue

			# Graine stable : même style = même trajectoire d'un essai à l'autre.
			var style_seed := hash("%s|%s" % [car_id, style_id]) & 0x7fffffff
			var stats: Dictionary = await _train_car(
				track_path, cars_root, skid_marks, line, car_id, style_id,
				style_seed, spawn, target_distance, difficulty, laps, learn
			)

			total_crashes += int(stats["crashes"])
			total_learned += int(stats["learned"])
			total_driven += float(stats["driven"])
			total_frames += int(stats["frames"])

			print("[%s] %s / %s : %d chocs, %d appris, %d/%d tours, %d frames, garde-fou %s, blocages %d" % [
				track_name, car_id, style_id,
				int(stats["crashes"]), int(stats["learned"]),
				int(round(float(stats["driven"]) / line.length)), laps,
				int(stats["frames"]),
				"ATTEINT" if bool(stats["guard_hit"]) else "non",
				int(stats["stuck_resets"]),
			])

		print("[%s] %s : total %d chocs, %d appris, %.1f tours, %d frames" % [
			track_name, car_id, total_crashes, total_learned,
			total_driven / line.length, total_frames,
		])

	# Force une dernière sauvegarde (record_crash sauvegarde déjà).
	AILearningScript._save()
	var point_count := 0
	for key in AILearningScript._data:
		point_count += (AILearningScript._data[key] as Array).size()
	print("Apprentissage écrit dans : %s (%d clés, %d points)" % [output, AILearningScript._data.size(), point_count])
	quit()


func _train_car(
	track_path: String,
	cars_root: Node,
	skid_marks: Node,
	line,
	car_id: String,
	style_id: String,
	style_seed: int,
	spawn: Transform2D,
	target_distance: float,
	difficulty: int,
	laps: int,
	learn: bool
) -> Dictionary:
	var definition = CarCatalogScript.get_car(car_id)
	if definition == null:
		printerr("Voiture inconnue : " + car_id)
		return _empty_stats()

	var color_data = ColorCatalogScript.get_color(COLOR)
	var car = CarScene.instantiate()
	cars_root.add_child(car)
	car.global_position = spawn.origin
	car.global_rotation = spawn.get_rotation()
	car.setup_car(definition, color_data["color"], 0, true, "ai", -1, skid_marks)
	# Départ immédiat : dans le jeu, la course appelle set_can_move(true)
	# après le compte à rebours. Sans cela l'IA ne roule pas.
	car.set_colision(true)
	car.set_can_move(true)

	var driver = AIDriverScript.new(car, line, difficulty, track_path)
	driver.learning_key = AILearningScript.make_key(track_path, car_id) if learn else ""
	driver.lap_count = 0
	driver.set_style(style_id, style_seed)
	car.ai_driver = driver

	car.respawn_requested.connect(func(_c): _respawn(car, driver, spawn))

	var key: String = driver.learning_key
	var version_before: int = AILearningScript.version(key)
	var driven := 0.0
	var last_pos: Vector2 = car.global_position
	var stuck_frames := 0
	var stuck_resets := 0
	var frames := 0
	# Garde-fou : 4 px/frame au minimum, et 20 min simulées de marge.
	var max_frames := int(maxf(target_distance / 4.0, 60.0 * 60.0 * 20.0))

	for _f in range(max_frames):
		await physics_frame
		frames += 1
		_fix_headless_animations(cars_root)
		var step: float = car.global_position.distance_to(last_pos)
		if step < 200.0:
			driven += step
		last_pos = car.global_position

		if driven >= target_distance:
			break

		# Garde-fou : si totalement immobile longtemps, forcer une réapparition.
		if car.velocity.length() < 5.0 and car.visible:
			stuck_frames += 1
			if stuck_frames > 60 * 15:
				# Bloquée : comme le fait AIDriver lui-même, apprendre à
				# ralentir là où elle s'est coincée.
				driver.on_crash()
				car.explosion()
				stuck_resets += 1
				stuck_frames = 0
		else:
			stuck_frames = 0

	var stats := {
		"crashes": int(driver.crash_count),
		"learned": AILearningScript.version(key) - version_before,
		"driven": driven,
		"frames": frames,
		"guard_hit": driven < target_distance,
		"stuck_resets": stuck_resets,
	}
	car.ai_driver = null
	car.queue_free()
	await physics_frame
	return stats


func _empty_stats() -> Dictionary:
	return {
		"crashes": 0, "learned": 0, "driven": 0.0,
		"frames": 0, "guard_hit": false, "stuck_resets": 0,
	}


func _respawn(car, driver, spawn: Transform2D) -> void:
	if not is_instance_valid(car):
		return
	var spd: float = car.velocity.length()
	var prof := -1.0
	if int(driver._line_loss_index) >= 0 and int(driver._line_loss_index) < driver.speed_profile.size():
		prof = driver.speed_profile[int(driver._line_loss_index)]
	print("[choc] pos=%s idx=%d last_on=%d loss=%d vitesse=%.0f profil=%.0f" % [
		car.global_position, int(driver._index),
		int(driver._last_on_line_index), int(driver._line_loss_index),
		spd, prof,
	])
	driver.reset_tracking()
	car.respawn_at(spawn)


func _fix_headless_animations(cars_root: Node) -> void:
	# Sans fenêtre, l'audio des animations ne finit jamais : on force la fin.
	for node in cars_root.get_parent().find_children("*", "CarAnimation", true, false):
		if node.has_method("_on_audio_finished"):
			node.call("_on_audio_finished")


func _gate_segments(track: Node) -> Dictionary:
	var gates := {}
	var sections := track.get_node_or_null("Sections")
	if sections == null:
		return gates
	for section in sections.get_children():
		for child in section.get_children():
			if child is CollisionShape2D and child.shape is SegmentShape2D:
				var seg: SegmentShape2D = child.shape
				gates[section.section_id] = [child.to_global(seg.a), child.to_global(seg.b)]
	return gates


func _spawn_transform(track: Node) -> Transform2D:
	var spawns := track.get_node_or_null("SpawnPoints")
	if spawns != null and spawns.get_child_count() > 0:
		var m := spawns.get_child(0) as Node2D
		if m != null:
			return m.global_transform
	return Transform2D.IDENTITY


func _all_styles() -> Array:
	var ids := []
	for style in AIStyleScript.get_styles():
		ids.append(String(style["id"]))
	return ids


func _parse_args() -> Dictionary:
	var out := {}
	var raw := OS.get_cmdline_user_args()
	for a in raw:
		if not a.begins_with("--"):
			continue
		var body := a.substr(2)
		var parts := body.split("=", true, 1)
		var key: String = parts[0]
		var value: String = parts[1] if parts.size() > 1 else "true"
		if key == "cars" or key == "styles":
			out[key] = value.split(",", false)
		elif key == "laps" or key == "difficulty":
			out[key] = int(value)
		else:
			out[key] = value
	return out
