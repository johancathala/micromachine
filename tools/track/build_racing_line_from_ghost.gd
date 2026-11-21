extends SceneTree

# ============================================================
# Trajectoire d'IA à partir d'un tour enregistré (fantôme)
#
#   godot --headless --path . -s tools/track/build_racing_line_from_ghost.gd -- \
#       --track=res://level/track/Track02.tscn \
#       --ghost=user://ghosts/track1_clio_jo.ghost \
#       --output=res://level/track/lines/Track02_racing_line.tres
#
# Le fantôme (contre-la-montre) contient la position de la voiture à
# chaque échantillon. On en tire une boucle fermée, lissée et
# rééchantillonnée, puis simplifiée en une Curve2D : RacingLine la
# reconnaît (Path2D nommé « RacingLine ») et l'IA la suit.
#
# Le fichier .tres est autonome (aucun lien vers les données du joueur).
# Relancer la conversion après un nouveau meilleur tour, puis
# render_track_previews.gd pour l'aperçu du menu.
# ============================================================

# Écart maximal (px) toléré entre le fantôme et la ligne simplifiée.
# 0 : aucun raccourci (tous les points rééchantillonnés sont conservés).
const DEFAULT_TOLERANCE := 1.0
# Lissage du fantôme avant rééchantillonnage (rayon en échantillons).
const SMOOTH_RADIUS := 1
# Pas de la trajectoire (comme RacingLine.SPACING).
const SPACING := 32.0
# Pas de cuisson de la Curve2D.
const BAKE_INTERVAL := 8.0
# Données du fantôme : temps + position, 4 flottants par échantillon.
const GHOST_STRIDE := 4


func _initialize() -> void:
	await process_frame

	var args := _parse_args()
	var track_path: String = args.get("track", "")
	var ghost_path: String = args.get("ghost", "")
	var output: String = args.get("output", "")
	var tolerance: float = float(args.get("tolerance", DEFAULT_TOLERANCE))

	if track_path.is_empty() or ghost_path.is_empty() or output.is_empty():
		printerr("Usage: godot --headless --path . -s tools/track/build_racing_line_from_ghost.gd -- --track=res://... --ghost=user://... --output=res://...")
		quit(1)
		return

	var TrackProgressScript := load("res://level/script/TrackProgress.gd")

	# Point de départ du parcours (ligne de départ), pour aligner la boucle.
	var track_scene := load(track_path) as PackedScene
	var track := track_scene.instantiate() as Node2D
	root.add_child(track)
	await process_frame

	var gates := _gate_segments(track)
	var progress = TrackProgressScript.new()
	var start := Vector2.ZERO
	if progress.build(track, gates) and progress.section_count > 0:
		start = progress.get_path(0)[0]
	else:
		push_warning("TrackProgress : %s (départ non aligné)" % progress.last_error)
		if not gates.is_empty():
			var first: Array = gates[gates.keys()[0]]
			start = (Vector2(first[0]) + Vector2(first[1])) * 0.5

	var raw := _read_ghost(ghost_path)
	if raw.size() < 16:
		printerr("Fantôme illisible ou trop court : " + ghost_path)
		quit(1)
		return

	var smooth := _smooth_closed(raw, SMOOTH_RADIUS)
	var loop: PackedVector2Array = TrackProgressScript.resample_closed(smooth, SPACING)
	loop = _start_at(loop, start)
	var simplified: PackedVector2Array = loop
	if tolerance > 0.0:
		simplified = _simplify_closed(loop, tolerance)

	var curve := Curve2D.new()
	curve.bake_interval = BAKE_INTERVAL
	for point in simplified:
		curve.add_point(point)

	var error := _loop_error(loop, _resample_curve(curve, TrackProgressScript))
	var dir := output.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var err := ResourceSaver.save(curve, output)
	if err != OK:
		printerr("Écriture impossible : %s (erreur %d)" % [output, err])
		quit(1)
		return

	print("Fantôme : %d échantillons, %d px" % [raw.size(), _loop_length(raw)])
	print("Ligne : %d points (simplifiés depuis %d), %d px, écart max %.1f px" % [
		simplified.size(), loop.size(), loop.size() * SPACING, error,
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


## Rotation de la boucle : commencer au point le plus proche de la ligne
## de départ (le fantôme démarre sur la grille, un peu avant).
func _start_at(points: PackedVector2Array, target: Vector2) -> PackedVector2Array:
	if points.is_empty():
		return points

	var best := 0
	var best_distance := INF
	for i in range(points.size()):
		var d := points[i].distance_squared_to(target)
		if d < best_distance:
			best_distance = d
			best = i

	var result := PackedVector2Array()
	for i in range(points.size()):
		result.append(points[(best + i) % points.size()])
	return result


func _simplify_closed(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if points.size() < 4:
		return points

	# Deux chaînes entre les points les plus éloignés : RDP sur chacune.
	var far := 0
	var far_distance := 0.0
	for i in range(1, points.size()):
		var d := points[0].distance_squared_to(points[i])
		if d > far_distance:
			far_distance = d
			far = i

	var first := points.slice(0, far + 1)
	var second := points.slice(far, points.size())
	second.append(points[0])

	var a := _rdp(first, tolerance)
	var b := _rdp(second, tolerance)
	b.remove_at(0)
	b.remove_at(b.size() - 1)

	var result := PackedVector2Array()
	result.append_array(a)
	result.append_array(b)
	return result


func _rdp(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if points.size() < 3:
		return points

	var a := points[0]
	var b := points[points.size() - 1]
	var index := -1
	var max_distance := 0.0

	for i in range(1, points.size() - 1):
		var d := _segment_distance(points[i], a, b)
		if d > max_distance:
			max_distance = d
			index = i

	if max_distance <= tolerance or index < 0:
		return PackedVector2Array([a, b])

	var left := _rdp(points.slice(0, index + 1), tolerance)
	var right := _rdp(points.slice(index, points.size()), tolerance)
	left.remove_at(left.size() - 1)
	left.append_array(right)
	return left


func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _resample_curve(curve: Curve2D, TrackProgressScript: GDScript) -> PackedVector2Array:
	return TrackProgressScript.resample_closed(curve.get_baked_points(), SPACING)


## Écart max (px) entre deux boucles, mesuré de la première vers la seconde.
func _loop_error(reference: PackedVector2Array, tested: PackedVector2Array) -> float:
	var result := 0.0
	for p in reference:
		var best := INF
		for i in range(tested.size()):
			var a := tested[i]
			var b := tested[(i + 1) % tested.size()]
			best = minf(best, _segment_distance(p, a, b))
		result = maxf(result, best)
	return result


func _loop_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(points.size()):
		total += points[i].distance_to(points[(i + 1) % points.size()])
	return total


func _smooth_closed(points: PackedVector2Array, radius: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	var count := points.size()
	result.resize(count)

	for i in range(count):
		var sum := Vector2.ZERO
		var weight := 0.0
		for offset in range(-radius, radius + 1):
			var w := float(radius + 1 - absi(offset))
			sum += points[posmod(i + offset, count)] * w
			weight += w
		result[i] = sum / weight

	return result


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
			result[text.substr(2, text.find("=") - 2)] = text.substr(text.find("=") + 1)
	return result
