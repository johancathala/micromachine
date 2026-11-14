extends SceneTree

# ============================================================
# Portes des sections : couvrir toute la largeur de la route
#
#   godot --headless --path . -s tools/track/widen_gates.gd
#
# Une porte plus courte que la route laisse passer une voiture à côté :
# la porte suivante compte alors comme un raccourci (explosion). Chaque
# porte est étendue, dans sa direction, à toute la largeur de la route
# qu'elle coupe : l'asphalte, plus le vibreur de bordure (au plus
# KERB_MAX px), sans jamais déborder sur une route voisine (arrêt si
# l'asphalte reprend derrière un vibreur, sur l'herbe ou un obstacle).
# Une porte n'est jamais raccourcie. À relancer après
# build_brissac_variants.gd.
# ============================================================

const TRACKS := [
	"res://level/track/Track01.tscn",
	"res://level/track/Track02.tscn",
	"res://level/track/Track03.tscn",
	"res://level/track/Track05.tscn"
]

const STEP := 8.0
const MAX_HALF := 700.0
const KERB_MAX := 96.0
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

	var blocking: Array[TileMapLayer] = []

	for child in map.get_children():
		var layer := child as TileMapLayer

		if layer == null or layer == asphalt:
			continue

		var name := String(layer.name).to_lower()

		# Vibreurs, eau et couches d'obstacles (« 0_... ») bornent la porte.
		if name.contains("vibreur") or name.contains("eau") or name.begins_with("0_"):
			blocking.append(layer)

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
			var to_b := _extent(seed, direction, asphalt, blocking)
			var to_a := _extent(seed, -direction, asphalt, blocking)
			var reach_b := maxf((seed - middle).dot(direction) + to_b, (b - middle).dot(direction))
			var reach_a := maxf(-(seed - middle).dot(direction) + to_a, (middle - a).dot(direction))
			var new_a := middle - direction * reach_a
			var new_b := middle + direction * reach_b

			if new_a.distance_to(new_b) <= a.distance_to(b) + 1.0:
				continue

			# Ressource propre à cette porte (pas de partage involontaire).
			var widened := SegmentShape2D.new()
			widened.a = shape_node.to_local(new_a)
			widened.b = shape_node.to_local(new_b)
			shape_node.shape = widened
			changed += 1
			print("  %s porte %s : %d -> %d px" % [path.get_file(), String(section.name), a.distance_to(b), new_a.distance_to(new_b)])

	if changed > 0:
		track.get_parent().remove_child(track)

		if packed.pack(track) != OK or ResourceSaver.save(packed, path) != OK:
			push_error("Échec de l'enregistrement de " + path)

	print("%s : %d porte(s) élargie(s)" % [path, changed])
	track.free()


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


## Largeur de route depuis `origin` (sur l'asphalte) dans une direction :
## l'asphalte, puis le vibreur de bordure s'il n'est pas suivi d'une
## autre route.
func _extent(origin: Vector2, direction: Vector2, asphalt: TileMapLayer, blocking: Array[TileMapLayer]) -> float:
	var distance := 0.0

	while distance < MAX_HALF:
		var point := origin + direction * (distance + STEP)

		if not _has(asphalt, point) or _blocked(point, blocking):
			break

		distance += STEP

	var road_end := distance
	var kerb := 0.0

	while kerb < KERB_MAX:
		var point := origin + direction * (road_end + kerb + STEP)

		# Une autre route derrière le vibreur : on s'arrête à la nôtre.
		if _has(asphalt, point) and not _blocked(point, blocking):
			return road_end

		if not _is_kerb(point, blocking):
			break

		kerb += STEP

	return road_end + kerb


func _has(layer: TileMapLayer, point: Vector2) -> bool:
	return layer.get_cell_source_id(layer.local_to_map(layer.to_local(point))) != -1


func _blocked(point: Vector2, blocking: Array[TileMapLayer]) -> bool:
	for layer in blocking:
		if not String(layer.name).to_lower().contains("vibreur") and _has(layer, point):
			return true

	return false


func _is_kerb(point: Vector2, blocking: Array[TileMapLayer]) -> bool:
	for layer in blocking:
		if String(layer.name).to_lower().contains("vibreur") and _has(layer, point):
			return true

	return false
