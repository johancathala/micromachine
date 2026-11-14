extends SceneTree

# ============================================================
# Portes des sections : couvrir toute la largeur de la route
#
#   godot --headless --path . -s tools/track/widen_gates.gd
#
# Une porte plus courte que la route laisse passer une voiture à côté :
# la porte suivante compte alors comme un raccourci (explosion). Comme
# sur Brissac (Track01, référence), chaque porte est étendue dans sa
# direction à toute la route qu'elle coupe, puis à travers le bas-côté
# (vibreur, herbe, gravier) jusqu'au premier obstacle dur (arbre,
# barrière, mur, bâtiment, eau, baril). Si une autre portion de route
# commence avant l'obstacle, la porte s'arrête à mi-chemin, pour ne
# jamais couper une autre partie du circuit. Une porte n'est jamais
# raccourcie. À relancer après build_brissac_variants.gd.
# ============================================================

# Brissac (Track01) sert de référence : ses portes ne sont pas touchées.
const TRACKS := [
	"res://level/track/Track02.tscn",
	"res://level/track/Track03.tscn",
	"res://level/track/Track05.tscn"
]

const STEP := 8.0
const MAX_HALF := 700.0
# Largeur maximale de bas-côté traversée de chaque côté.
const VERGE_MAX := 500.0
# Distance gardée avant un obstacle.
const OBSTACLE_MARGIN := 8.0
# Rayon des obstacles posés (barils, citerne...).
const BODY_RADIUS := 48.0
# Déplacement toléré du point de passage du parcours sur une porte.
const CROSSING_TOLERANCE := 150.0
# Variation tolérée de la longueur du tour (fraction).
const MAX_LENGTH_CHANGE := 0.02
# Recherche de l'asphalte le long de la porte, depuis son milieu.
const SEED_SEARCH := 240.0


func _initialize() -> void:
	for path in TRACKS:
		_widen(path)

	quit()


func _widen(path: String) -> void:
	var packed := load(path) as PackedScene
	var track := packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as Node2D
	root.add_child(track)

	var map := track.find_child("Map", true, false)
	var asphalt: TileMapLayer = null

	for child in map.get_children():
		if child is TileMapLayer and String(child.name).to_lower().contains("asphalte"):
			asphalt = child

	# Obstacles durs : tuiles avec collision des couches « 0_... », eau.
	_hard_layers.clear()
	_water_layers.clear()

	for child in map.get_children():
		var layer := child as TileMapLayer

		if layer == null or layer == asphalt:
			continue

		var name := String(layer.name).to_lower()

		if name.contains("eau"):
			_water_layers.append(layer)
		elif name.begins_with("0_"):
			_hard_layers.append(layer)

	# Obstacles posés (barils, citerne...).
	_bodies.clear()

	for body in track.find_children("*", "StaticBody2D", true, false):
		if not body is TileMapLayer:
			_bodies.append((body as Node2D).global_position)

	var before := _crossings(track)
	_asphalt = asphalt
	_kerb = null

	for child in map.get_children():
		if child is TileMapLayer and String(child.name).to_lower().contains("vibreur"):
			_kerb = child
	var originals: Dictionary = {}
	var changed := 0

	for section in track.get_node("Sections").get_children():
		for child in section.get_children():
			var shape_node := child as CollisionShape2D

			if shape_node == null or not shape_node.shape is SegmentShape2D:
				continue

			var segment := shape_node.shape as SegmentShape2D
			var a := shape_node.to_global(segment.a)
			var b := shape_node.to_global(segment.b)
			var middle := (a + b) / 2.0
			var direction := (b - a).normalized()
			var seed := _find_asphalt(middle, direction, asphalt)

			if seed == Vector2.INF:
				continue

			# Route coupée par la porte, réunie à la porte d'origine.
			var to_b := _extent(seed, direction, asphalt)
			var to_a := _extent(seed, -direction, asphalt)
			var reach_b := maxf((seed - middle).dot(direction) + to_b, (b - middle).dot(direction))
			var reach_a := maxf(-(seed - middle).dot(direction) + to_a, (middle - a).dot(direction))
			var new_a := middle - direction * reach_a
			var new_b := middle + direction * reach_b

			if new_a.distance_to(new_b) <= a.distance_to(b) + 1.0:
				continue

			originals[shape_node] = shape_node.shape

			# Ressource propre à cette porte (pas de partage involontaire).
			var widened := SegmentShape2D.new()
			widened.a = shape_node.to_local(new_a)
			widened.b = shape_node.to_local(new_b)
			shape_node.shape = widened
			changed += 1
			print("  %s porte %s : %d -> %d px" % [path.get_file(), String(section.name), a.distance_to(b), new_a.distance_to(new_b)])

	# Vérification : le parcours ne doit pas changer. Une porte élargie
	# qui offre un autre point de passage (carrefour, route voisine)
	# reprend sa longueur d'origine.
	for _round in range(5):
		var after := _crossings(track)
		var reverted := 0

		for shape_node: CollisionShape2D in originals.keys():
			var section_id := int(shape_node.get_parent().get("section_id"))

			if not before.has(section_id) or not after.has(section_id):
				continue

			var old_point: Vector2 = before[section_id]
			var new_point: Vector2 = after[section_id]
			var length_change := absf(float(after["length"]) / float(before["length"]) - 1.0)

			# Point de passage déplacé : accepté s'il reste sur la même
			# route (asphalte continu) et si le tour ne change pas.
			if (
				old_point.distance_to(new_point) > CROSSING_TOLERANCE
				and (not _same_road(old_point, new_point) or length_change > MAX_LENGTH_CHANGE)
			):
				shape_node.shape = originals[shape_node]
				originals.erase(shape_node)
				changed -= 1
				reverted += 1
				print("  %s porte %d : longueur d'origine gardée (autre point de passage)" % [path.get_file(), section_id])

		if reverted == 0:
			break

	if changed > 0:
		track.get_parent().remove_child(track)

		if packed.pack(track) != OK or ResourceSaver.save(packed, path) != OK:
			push_error("Échec de l'enregistrement de " + path)

	print("%s : %d porte(s) élargie(s)" % [path, changed])
	track.free()


## Point de passage du parcours sur chaque porte (section_id -> point).
func _crossings(track: Node) -> Dictionary:
	var gates: Dictionary = {}

	for section in track.get_node("Sections").get_children():
		for child in section.get_children():
			var shape_node := child as CollisionShape2D

			if shape_node != null and shape_node.shape is SegmentShape2D:
				var segment := shape_node.shape as SegmentShape2D
				gates[int(section.get("section_id"))] = [shape_node.to_global(segment.a), shape_node.to_global(segment.b)]

	var progress = load("res://level/script/TrackProgress.gd").new()
	var result: Dictionary = {}

	if not progress.build(track, gates):
		push_error("Parcours introuvable : " + progress.last_error)
		return result

	var length := 0.0

	for section_id in gates:
		var path: PackedVector2Array = progress.get_path(section_id)

		if not path.is_empty():
			result[section_id] = path[0]

		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])

	result["length"] = length
	return result


var _asphalt: TileMapLayer = null
var _kerb: TileMapLayer = null


## Route continue (asphalte ou vibreur) entre deux points.
func _same_road(from: Vector2, to: Vector2) -> bool:
	var steps := int(from.distance_to(to) / STEP)

	for k in range(steps + 1):
		var point := from.lerp(to, float(k) / maxf(steps, 1))

		if not _has(_asphalt, point) and (_kerb == null or not _has(_kerb, point)):
			return false

	return true


## Premier point d'asphalte le long de la porte, au plus près du milieu.
func _find_asphalt(middle: Vector2, direction: Vector2, asphalt: TileMapLayer) -> Vector2:
	var offset := 0.0

	while offset <= SEED_SEARCH:
		for sign in [1.0, -1.0]:
			var point: Vector2 = middle + direction * offset * sign

			if _has(asphalt, point):
				return point

		offset += STEP

	return Vector2.INF


## Étendue de la porte depuis `origin` (sur l'asphalte) dans une
## direction : la route, puis le bas-côté jusqu'au premier obstacle dur ;
## à mi-chemin si une autre route commence avant.
func _extent(origin: Vector2, direction: Vector2, asphalt: TileMapLayer) -> float:
	var distance := 0.0

	while distance < MAX_HALF:
		var point := origin + direction * (distance + STEP)

		if not _has(asphalt, point) or _is_hard(point):
			break

		distance += STEP

	var road_end := distance
	var verge := 0.0
	var left_road := false

	while verge < VERGE_MAX:
		var point := origin + direction * (road_end + verge + STEP)

		if _is_hard(point):
			return road_end + maxf(verge - OBSTACLE_MARGIN, 0.0)

		if _has(asphalt, point):
			# Une autre route (après un bas-côté) : on s'arrête à mi-chemin.
			if left_road:
				return road_end + verge / 2.0

		else:
			left_road = true

		verge += STEP

	return road_end + verge


var _hard_layers: Array[TileMapLayer] = []
var _water_layers: Array[TileMapLayer] = []
var _bodies: PackedVector2Array = []


func _has(layer: TileMapLayer, point: Vector2) -> bool:
	return layer.get_cell_source_id(layer.local_to_map(layer.to_local(point))) != -1


func _is_hard(point: Vector2) -> bool:
	for layer in _water_layers:
		if _has(layer, point):
			return true

	for layer in _hard_layers:
		var data := layer.get_cell_tile_data(layer.local_to_map(layer.to_local(point)))

		if data != null and layer.tile_set.get_physics_layers_count() > 0 and data.get_collision_polygons_count(0) > 0:
			return true

	for body in _bodies:
		if body.distance_to(point) < BODY_RADIUS:
			return true

	return false
