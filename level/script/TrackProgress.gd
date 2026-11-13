extends RefCounted
class_name TrackProgress

# ============================================================
# PROGRESSION LE LONG DE LA ROUTE
# ============================================================
#
# Au chargement du circuit, calcule pour chaque tronçon
# (section k -> section k+1) le chemin réel sur la route, par A*
# sur une grille de tuiles praticables :
#   - praticable : couches dont le nom contient « asphalte » ou
#     « vibreur » ;
#   - bloquant : toute tuile possédant une collision (murs, pneus,
#     bâtiments...).
#
# La progression d'une voiture dans un tronçon est sa position
# projetée sur le chemin de CE tronçon (distance parcourue / longueur),
# ce qui suit les épingles et évite toute confusion avec une portion
# de route voisine ou qui se croise.
#
# Convention pour les futurs circuits : nommer les couches de route
# avec « asphalte » / « vibreur » dans le nom.
# ============================================================

const DRIVABLE_KEYWORDS := ["asphalte", "vibreur"]

# Les tuiles de sol ont une collision (détection de surface) : seules
# bloquent celles dont la couche de collision touche le masque des
# voitures (Car.collision_mask = 14 : Player, Interact, Obstacle).
const BLOCKING_COLLISION_MASK := 0b1110

var _cell_size := Vector2(32, 32)
var _reference_layer: TileMapLayer = null

# section_id -> chemin (PackedVector2Array) vers la section suivante.
var _paths: Dictionary = {}
# section_id -> longueurs cumulées le long du chemin.
var _cumulative: Dictionary = {}

var section_count := 0

# Raison de l'échec de build(), pour le diagnostic.
var last_error := ""


## gate_segments : section_id -> [a, b] (porte de la section, en
## coordonnées globales). Retourne true si tous les tronçons ont un chemin.
func build(track: Node, gate_segments: Dictionary) -> bool:
	_paths.clear()
	_cumulative.clear()
	section_count = gate_segments.size()

	if section_count < 2:
		last_error = "moins de 2 sections"
		return false

	var astar := build_grid(track)

	if astar == null:
		return false

	# Points de passage possibles de chaque porte : une porte peut
	# couper plusieurs routes ; on garde chaque portion de route coupée.
	var candidates: Dictionary = {}

	for section_id in range(section_count):
		var segment: Array = gate_segments[section_id]
		candidates[section_id] = _gate_crossings(astar, segment[0], segment[1])

		if candidates[section_id].is_empty():
			last_error = "la porte de la section %d ne coupe aucune route" % section_id
			return false

	# Chemins entre points de passage de portes consécutives.
	# paths_between[k][[i, j]] = cellules du candidat i (porte k)
	# au candidat j (porte k+1).
	var paths_between: Dictionary = {}

	for section_id in range(section_count):
		var next_id := (section_id + 1) % section_count
		var table: Dictionary = {}

		for i in range(candidates[section_id].size()):
			for j in range(candidates[next_id].size()):
				var cells := astar.get_id_path(
					candidates[section_id][i],
					candidates[next_id][j]
				)

				if not cells.is_empty():
					table[Vector2i(i, j)] = cells

		paths_between[section_id] = table

	# Enchaînement cohérent le plus court sur le tour complet
	# (programmation dynamique sur le cycle des portes).
	var best_total := INF
	var best_choice: Array[int] = []

	for start_choice in range(candidates[0].size()):
		# cost[j] / choice[j] : meilleur coût pour arriver au candidat j
		# de la porte courante en partant du candidat `start_choice` de la porte 0.
		var cost: Dictionary = {start_choice: 0.0}
		var history: Array[Dictionary] = []

		for section_id in range(section_count):
			var next_id := (section_id + 1) % section_count
			var next_cost: Dictionary = {}
			var parent: Dictionary = {}

			for i in cost:
				for j in range(candidates[next_id].size()):
					if next_id == 0 and j != start_choice:
						continue

					var cells: Variant = paths_between[section_id].get(Vector2i(i, j))

					if cells == null:
						continue

					var total: float = cost[i] + float((cells as Array).size())

					if total < float(next_cost.get(j, INF)):
						next_cost[j] = total
						parent[j] = i

			history.append(parent)
			cost = next_cost

		if cost.has(start_choice) and float(cost[start_choice]) < best_total:
			best_total = cost[start_choice]
			# Remonte les choix depuis la fin.
			var choice: Array[int] = []
			choice.resize(section_count)
			var current: int = start_choice

			for step in range(section_count - 1, -1, -1):
				var previous: int = history[step][current]
				choice[step] = previous
				current = previous

			best_choice = choice

	if best_choice.is_empty():
		last_error = "aucun enchaînement de chemins sur le tour"
		return false

	for section_id in range(section_count):
		var next_id := (section_id + 1) % section_count
		var i: int = best_choice[section_id]
		var j: int = best_choice[next_id]
		var cells: Array = paths_between[section_id][Vector2i(i, j)]

		var points := PackedVector2Array()

		for cell in cells:
			points.append(_cell_to_world(cell))

		var cumulative := PackedFloat32Array()
		var total := 0.0
		cumulative.append(0.0)

		for k in range(1, points.size()):
			total += points[k - 1].distance_to(points[k])
			cumulative.append(total)

		_paths[section_id] = points
		_cumulative[section_id] = cumulative

	return true


## Portions de route coupées par la porte [a, b] : une case
## (milieu de la portion) par portion praticable.
func _gate_crossings(
	astar: AStarGrid2D,
	a: Vector2,
	b: Vector2
) -> Array[Vector2i]:

	var result: Array[Vector2i] = []
	var run: Array[Vector2i] = []
	var steps := maxi(int(a.distance_to(b) / (_cell_size.x * 0.5)), 1)
	var last_cell := Vector2i(2147483647, 0)

	for i in range(steps + 1):
		var point := a.lerp(b, float(i) / steps)
		var cell := _reference_layer.local_to_map(
			_reference_layer.to_local(point)
		)

		if cell == last_cell:
			continue

		last_cell = cell

		var walkable := astar.is_in_boundsv(cell) and not astar.is_point_solid(cell)

		if walkable:
			run.append(cell)
		elif not run.is_empty():
			result.append(run[run.size() / 2])
			run.clear()

	if not run.is_empty():
		result.append(run[run.size() / 2])

	return result


## Grille A* des cases praticables du circuit (null si impossible).
## Le nœud « Map » peut être à la racine du circuit ou dans une carte
## intégrée (variantes de circuit réutilisant une autre carte).
func build_grid(track: Node) -> AStarGrid2D:
	var map := track.get_node_or_null("Map")

	if map == null:
		map = track.find_child("Map", true, false)

	if map == null:
		last_error = "nœud Map absent"
		return null

	var drivable: Dictionary = {}
	var layers: Array[TileMapLayer] = []

	for child in map.get_children():
		var layer := child as TileMapLayer

		if layer == null or layer.tile_set == null:
			continue

		layers.append(layer)

		var lower_name := String(layer.name).to_lower()

		for keyword in DRIVABLE_KEYWORDS:
			if lower_name.contains(keyword):
				if _reference_layer == null:
					_reference_layer = layer
					_cell_size = Vector2(layer.tile_set.tile_size)
				break

	if _reference_layer == null:
		last_error = "aucune couche « asphalte » / « vibreur »"
		return null

	# Cases praticables (grille de la couche de référence).
	for layer in layers:
		var lower_name := String(layer.name).to_lower()
		var is_drivable := false

		for keyword in DRIVABLE_KEYWORDS:
			if lower_name.contains(keyword):
				is_drivable = true

		if not is_drivable:
			continue

		for cell in layer.get_used_cells():
			drivable[_to_grid(layer, cell)] = true

	# Cases bloquées : tuiles avec collision, quelle que soit la couche.
	var blocked: Dictionary = {}

	for layer in layers:
		if layer.tile_set.get_physics_layers_count() == 0:
			continue

		var collision_layer := layer.tile_set.get_physics_layer_collision_layer(0)

		if collision_layer & BLOCKING_COLLISION_MASK == 0:
			continue

		for cell in layer.get_used_cells():
			# Certaines cases peuvent pointer vers une tuile absente du
			# jeu de tuiles (ex. Track01) : on les ignore sans erreur.
			var source := layer.tile_set.get_source(layer.get_cell_source_id(cell)) if layer.tile_set.has_source(layer.get_cell_source_id(cell)) else null

			if not source is TileSetAtlasSource:
				continue

			var coords := layer.get_cell_atlas_coords(cell)
			var alternative := layer.get_cell_alternative_tile(cell)

			if not (source as TileSetAtlasSource).has_tile(coords):
				continue

			if not (source as TileSetAtlasSource).has_alternative_tile(coords, alternative):
				continue

			var data := layer.get_cell_tile_data(cell)

			if data == null or data.get_collision_polygons_count(0) == 0:
				continue

			blocked[_to_grid(layer, cell)] = true

	if drivable.is_empty():
		return null

	var region := Rect2i()
	var first := true

	for cell in drivable:
		if first:
			region = Rect2i(cell, Vector2i.ONE)
			first = false
		else:
			region = region.expand(cell).expand(cell + Vector2i.ONE)

	var astar := AStarGrid2D.new()
	astar.region = region.grow(1)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	astar.fill_solid_region(astar.region, true)

	for cell in drivable:
		if not blocked.has(cell):
			astar.set_point_solid(cell, false)

	return astar


func is_drivable_cell(astar: AStarGrid2D, cell: Vector2i) -> bool:
	return astar.is_in_boundsv(cell) and not astar.is_point_solid(cell)


func world_to_cell(world_position: Vector2) -> Vector2i:
	return _reference_layer.local_to_map(_reference_layer.to_local(world_position))


func cell_to_world(cell: Vector2i) -> Vector2:
	return _cell_to_world(cell)


func is_ready() -> bool:
	return _paths.size() == section_count and section_count > 0


## Fraction (0 à 1) du tronçon from_section -> suivante déjà parcourue.
func get_fraction(from_section: int, world_position: Vector2) -> float:
	var points: PackedVector2Array = _paths.get(from_section, PackedVector2Array())

	if points.size() < 2:
		return 0.0

	var cumulative: PackedFloat32Array = _cumulative[from_section]
	var total: float = cumulative[cumulative.size() - 1]

	if total <= 0.0:
		return 0.0

	var best_distance := INF
	var best_offset := 0.0

	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var closest := Geometry2D.get_closest_point_to_segment(
			world_position, a, b
		)
		var distance := world_position.distance_squared_to(closest)

		if distance < best_distance:
			best_distance = distance
			best_offset = cumulative[i] + a.distance_to(closest)

	return clampf(best_offset / total, 0.0, 0.999)


func get_path(from_section: int) -> PackedVector2Array:
	return _paths.get(from_section, PackedVector2Array())


func get_lap_length() -> float:
	var total := 0.0

	for cumulative in _cumulative.values():
		total += cumulative[cumulative.size() - 1]

	return total


# ------------------------------------------------------------
# Grille
# ------------------------------------------------------------

func _to_grid(layer: TileMapLayer, cell: Vector2i) -> Vector2i:
	if layer == _reference_layer:
		return cell

	var world := layer.to_global(layer.map_to_local(cell))
	return _reference_layer.local_to_map(_reference_layer.to_local(world))


func _cell_to_world(cell: Vector2i) -> Vector2:
	return _reference_layer.to_global(_reference_layer.map_to_local(cell))
