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

# La voie des stands (zone PitStop du circuit) coûte plus cher au calcul
# du parcours : il préfère la piste, sauf quand une porte impose les
# stands (ex. variantes « Paddock »).
const PIT_LANE_WEIGHT := 4.0
# La zone d'arrêt ne couvre que la voie centrale : on pondère aussi les
# bandes voisines des stands (sans atteindre la piste, plus loin).
const PIT_WEIGHT_MARGIN := Vector2(350, 600)

var _cell_size := Vector2(32, 32)
var _reference_layer: TileMapLayer = null

# section_id -> chemin (PackedVector2Array) vers la section suivante.
var _paths: Dictionary = {}
# section_id -> longueurs cumulées le long du chemin.
var _cumulative: Dictionary = {}

var section_count := 0

# Grille praticable conservée après build() (axe de la chaussée pour l'IA).
var grid: AStarGrid2D = null
# Cases d'obstacles durs (murs, poteaux, objets), à distinguer de
# l'herbe (non praticable pour le parcours mais sans collision).
var hard_cells: Dictionary = {}

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

	grid = astar

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

					var total: float = cost[i] + _path_cost(astar, cells)

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

	# Pour l'IA (trajectoire, passage au stand) : les obstacles posés
	# sur la carte (barils, citerne...) deviennent infranchissables.
	# Après le calcul du parcours, qui n'en dépend pas.
	_block_obstacles(track)

	return true


## Marge autour des obstacles posés sur la carte (px).
const OBSTACLE_MARGIN := 40.0


## Cases couvertes par les corps statiques (hors tuiles) qui bloquent
## les voitures, avec une marge : rendues infranchissables dans la grille.
func _block_obstacles(track: Node) -> void:
	for node in track.find_children("*", "StaticBody2D", true, false):
		var body := node as StaticBody2D

		if body == null or body.collision_layer & BLOCKING_COLLISION_MASK == 0:
			continue

		for child in body.get_children():
			var shape := child as CollisionShape2D

			if shape == null or shape.shape == null:
				continue

			var rect := shape.shape.get_rect()
			var area := Rect2(shape.to_global(rect.position), Vector2.ZERO)

			for corner in [Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
				area = area.expand(shape.to_global(corner))

			area = area.grow(OBSTACLE_MARGIN)
			var c0 := world_to_cell(area.position)
			var c1 := world_to_cell(area.end)

			for x in range(c0.x, c1.x + 1):
				for y in range(c0.y, c1.y + 1):
					if grid.is_in_boundsv(Vector2i(x, y)):
						grid.set_point_solid(Vector2i(x, y), true)
						hard_cells[Vector2i(x, y)] = true


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

	hard_cells = blocked

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

	_weight_pit_lane(track, astar)

	return astar


## Rend la voie des stands plus coûteuse (zone du nœud PitStop).
func _weight_pit_lane(track: Node, astar: AStarGrid2D, weight: float = PIT_LANE_WEIGHT) -> void:
	var pit := track.get_node_or_null("PitStop") as Node2D

	if pit == null:
		return

	for child in pit.get_children():
		var shape := child as CollisionShape2D

		if shape == null or not shape.shape is RectangleShape2D:
			continue

		var half := (shape.shape as RectangleShape2D).size / 2.0
		var corners := [
			shape.to_global(Vector2(-half.x, -half.y)), shape.to_global(Vector2(half.x, -half.y)),
			shape.to_global(Vector2(half.x, half.y)), shape.to_global(Vector2(-half.x, half.y))
		]
		var area := Rect2(corners[0], Vector2.ZERO)

		for corner in corners:
			area = area.expand(corner)

		area = area.grow_individual(
			PIT_WEIGHT_MARGIN.x, PIT_WEIGHT_MARGIN.y,
			PIT_WEIGHT_MARGIN.x, PIT_WEIGHT_MARGIN.y
		)
		var c0 := world_to_cell(area.position)
		var c1 := world_to_cell(area.end)

		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				var cell := Vector2i(x, y)

				if astar.is_in_boundsv(cell) and not astar.is_point_solid(cell):
					astar.set_point_weight_scale(cell, weight)


## Coût d'un chemin : somme des poids des cases (voie des stands plus chère).
func _path_cost(astar: AStarGrid2D, cells: Variant) -> float:
	var total := 0.0

	for cell in cells:
		total += astar.get_point_weight_scale(cell)

	return total


## Axe de la chaussée sur tout le tour : milieu de la route en chaque
## point du parcours (le parcours A* longe l'intérieur des virages),
## lissé puis rééchantillonné tous les `spacing` px. Base de la
## trajectoire de l'IA quand le circuit n'en définit pas.
func build_centerline(spacing: float = 32.0) -> PackedVector2Array:
	var route := PackedVector2Array()

	for section_id in range(section_count):
		route.append_array(get_path(section_id))

	if route.size() < 8 or grid == null:
		return route

	var count := route.size()
	var centers := PackedVector2Array()
	centers.resize(count)

	for i in range(count):
		var before := route[posmod(i - 3, count)]
		var after := route[(i + 3) % count]
		var normal := (after - before).normalized().orthogonal()
		var left := _drivable_extent(route[i], normal)
		var right := _drivable_extent(route[i], -normal)
		centers[i] = route[i] + normal * (left - right) / 2.0

	# Lissage (moyenne glissante, plusieurs passes).
	for _pass in range(4):
		var smoothed := PackedVector2Array()
		smoothed.resize(count)

		for i in range(count):
			var sum := Vector2.ZERO

			for offset in range(-4, 5):
				sum += centers[posmod(i + offset, count)]

			smoothed[i] = sum / 9.0

		centers = smoothed

	return resample_closed(centers, spacing)


## Trajectoire de course : l'axe de la chaussée est « tendu »
## (relaxation qui réduit la courbure : extérieur, corde, extérieur),
## sans sortir de la chaussée (marge `margin` px de chaque bord).
func build_racing_line(spacing: float = 32.0, margin: float = 75.0, iterations: int = 400) -> PackedVector2Array:
	var center := build_centerline(spacing)
	var count := center.size()

	if count < 8 or grid == null:
		return center

	# Bords de la chaussée en chaque point de l'axe.
	var normals := PackedVector2Array()
	var left_room := PackedFloat32Array()
	var right_room := PackedFloat32Array()
	normals.resize(count)
	left_room.resize(count)
	right_room.resize(count)

	for i in range(count):
		var normal := (center[(i + 2) % count] - center[posmod(i - 2, count)]).normalized().orthogonal()
		normals[i] = normal
		left_room[i] = maxf(_drivable_extent(center[i], normal) - margin, 0.0)
		right_room[i] = maxf(_drivable_extent(center[i], -normal) - margin, 0.0)

	# Décalage latéral par rapport à l'axe.
	var offsets := PackedFloat32Array()
	offsets.resize(count)

	for _iteration in range(iterations):
		for i in range(count):
			var previous := center[posmod(i - 1, count)] + normals[posmod(i - 1, count)] * offsets[posmod(i - 1, count)]
			var next := center[(i + 1) % count] + normals[(i + 1) % count] * offsets[(i + 1) % count]
			var middle := (previous + next) / 2.0
			# Projection du milieu sur la normale : nouveau décalage.
			var wanted := (middle - center[i]).dot(normals[i])
			offsets[i] = clampf(lerpf(offsets[i], wanted, 0.6), -right_room[i], left_room[i])

	var line := PackedVector2Array()
	line.resize(count)

	for i in range(count):
		line[i] = center[i] + normals[i] * offsets[i]

	return resample_closed(line, spacing)


# ------------------------------------------------------------
# Passage au stand (IA)
# ------------------------------------------------------------

## Distance au-delà de la zone d'arrêt où la voie des stands est
## rejointe / quittée (px).
const PIT_ROUTE_END_MARGIN := 60.0
## Arrêt visé : premier point du trajet précédé de PIT_STOP_ALIGNED
## points tous dans la zone d'arrêt (rétrécie de PIT_STOP_INSET px) :
## la voiture y est alignée dans la voie, bien dans la zone.
const PIT_STOP_ALIGNED := 6
const PIT_STOP_INSET := 30.0
## Un chemin A* « direct » ne dépasse pas cette longueur relative.
const PIT_DIRECT_RATIO := 1.25
## Points de la trajectoire repris avant et après le trajet du stand.
const PIT_ROUTE_JOIN_POINTS := 8


## Trajet de passage au stand pour l'IA, depuis la trajectoire `line`
## (boucle fermée, points espacés de `spacing`) :
##   quitte la ligne avant l'entrée des stands, traverse la zone d'arrêt
##   (nœud PitStop) dans le sens de la course, puis rejoint la ligne.
## Résultat : {points, entry_index, exit_index, stop_index}, vide si le
## circuit n'a pas de stand ou si le trajet est introuvable.
func build_pit_route(track: Node, line: PackedVector2Array, spacing: float = 32.0) -> Dictionary:
	var pit := track.get_node_or_null("PitStop") as Node2D

	if pit == null or grid == null or line.size() < 8:
		return {}

	var shape: CollisionShape2D = null

	for child in pit.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape is RectangleShape2D:
			shape = child
			break

	if shape == null:
		return {}

	var size := (shape.shape as RectangleShape2D).size
	var center := shape.global_position
	var axis := shape.global_transform.y.normalized() if size.y >= size.x else shape.global_transform.x.normalized()
	var half_length := maxf(size.x, size.y) / 2.0
	var count := line.size()

	# Point de la trajectoire le plus proche de la zone, et sens de course.
	var center_index := 0

	for i in range(count):
		if line[i].distance_squared_to(center) < line[center_index].distance_squared_to(center):
			center_index = i

	var line_direction := line[(center_index + 2) % count] - line[posmod(center_index - 2, count)]

	if axis.dot(line_direction) < 0.0:
		axis = -axis

	var lane_in := _nearest_drivable(center - axis * (half_length + PIT_ROUTE_END_MARGIN))
	var lane_out := _nearest_drivable(center + axis * (half_length + PIT_ROUTE_END_MARGIN))
	if lane_in == Vector2.INF or lane_out == Vector2.INF:
		return {}

	# Calcul sans surcoût de la voie des stands.
	_weight_pit_lane(track, grid, 1.0)
	var restore := _weight_near_hard_cells()

	var route := PackedVector2Array()
	var entry_index := -1
	var exit_index := -1

	# Entrée : dernier point de la ligne (en remontant) d'où la voie des
	# stands s'atteint directement, sans faire demi-tour.
	for back in range(4, count / 2, 2):
		var index := posmod(center_index - back, count)
		var path := _grid_path(line[index], lane_in)

		if _is_direct(path, line[index], lane_in):
			entry_index = index
			route.append_array(path)
			break

	var lane := _grid_path(lane_in, lane_out)
	route.append_array(lane)

	for forward in range(4, count / 2, 2):
		var index := (center_index + forward) % count
		var path := _grid_path(lane_out, line[index])

		if _is_direct(path, lane_out, line[index]):
			exit_index = index
			route.append_array(path)
			break

	for cell in restore:
		grid.set_point_weight_scale(cell, restore[cell])

	_weight_pit_lane(track, grid, PIT_LANE_WEIGHT)

	if entry_index < 0 or exit_index < 0 or lane.is_empty():
		return {}

	# Raccord sur la ligne, quelques points avant et après : le virage
	# d'entrée / de sortie est ainsi mesuré depuis la trajectoire.
	var head := PackedVector2Array()

	for k in range(PIT_ROUTE_JOIN_POINTS, -1, -1):
		head.append(line[posmod(entry_index - k, count)])

	route = head + route

	for k in range(PIT_ROUTE_JOIN_POINTS + 1):
		route.append(line[(exit_index + k) % count])

	entry_index = posmod(entry_index - PIT_ROUTE_JOIN_POINTS, count)
	exit_index = (exit_index + PIT_ROUTE_JOIN_POINTS) % count

	# Lissage (le chemin A* longe les bords).
	var smooth := _push_from_hard_cells(_smooth_open(route, 3, 3))
	var points := resample_open(smooth, spacing)

	var stop_index := -1
	var inside_run := 0
	var inverse := shape.global_transform.affine_inverse()
	var inner := size / 2.0 - Vector2(PIT_STOP_INSET, PIT_STOP_INSET)

	for i in range(points.size()):
		var local := inverse * points[i]

		if absf(local.x) <= inner.x and absf(local.y) <= inner.y:
			inside_run += 1

			if inside_run > PIT_STOP_ALIGNED:
				stop_index = i
				break
		else:
			inside_run = 0

	if stop_index < 0:
		return {}

	return {
		"points": points,
		"entry_index": entry_index,
		"exit_index": exit_index,
		"stop_index": stop_index
	}


func _grid_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	var from_cell := world_to_cell(from)
	var to_cell := world_to_cell(to)

	if not is_drivable_cell(grid, from_cell) or not is_drivable_cell(grid, to_cell):
		return result

	for cell in grid.get_id_path(from_cell, to_cell):
		result.append(_cell_to_world(cell))

	return result


func _is_direct(path: PackedVector2Array, from: Vector2, to: Vector2) -> bool:
	if path.size() < 2:
		return false

	var length := 0.0

	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])

	return length <= from.distance_to(to) * PIT_DIRECT_RATIO + 64.0


## Rayon (cases) et surcoût des cases proches d'un obstacle dur, et
## distance (px) gardée par le trajet du stand après lissage.
const HARD_CLEARANCE_CELLS := 2
const HARD_CLEARANCE_WEIGHT := 6.0
const HARD_CLEARANCE := 60.0


## Rend coûteuses les cases praticables proches d'un obstacle dur ;
## renvoie les poids d'origine pour les rétablir.
func _weight_near_hard_cells() -> Dictionary:
	var original: Dictionary = {}

	for hard in hard_cells:
		for x in range(-HARD_CLEARANCE_CELLS, HARD_CLEARANCE_CELLS + 1):
			for y in range(-HARD_CLEARANCE_CELLS, HARD_CLEARANCE_CELLS + 1):
				var cell: Vector2i = hard + Vector2i(x, y)

				if original.has(cell) or not is_drivable_cell(grid, cell):
					continue

				original[cell] = grid.get_point_weight_scale(cell)
				grid.set_point_weight_scale(cell, original[cell] * HARD_CLEARANCE_WEIGHT)

	return original


## Éloigne les points des obstacles durs (le lissage coupe les angles).
func _push_from_hard_cells(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	var reach := int(ceil(HARD_CLEARANCE / _cell_size.x))

	for _pass in range(3):
		for i in range(1, result.size() - 1):
			var origin := world_to_cell(result[i])
			var push := Vector2.ZERO

			for x in range(-reach, reach + 1):
				for y in range(-reach, reach + 1):
					var cell := origin + Vector2i(x, y)

					if not hard_cells.has(cell):
						continue

					var away := result[i] - _cell_to_world(cell)
					var distance := away.length()

					if distance < HARD_CLEARANCE and distance > 0.01:
						push += away / distance * (HARD_CLEARANCE - distance)

			result[i] += push.limit_length(HARD_CLEARANCE) * 0.5

	return result


## Case praticable la plus proche (recherche en carrés croissants).
func _nearest_drivable(world_position: Vector2) -> Vector2:
	var origin := world_to_cell(world_position)

	for radius in range(0, 12):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue

				var cell := origin + Vector2i(x, y)

				if is_drivable_cell(grid, cell):
					return _cell_to_world(cell)

	return Vector2.INF


## Moyenne glissante d'une polyligne ouverte (extrémités conservées).
static func _smooth_open(points: PackedVector2Array, window: int, passes: int) -> PackedVector2Array:
	var current := points

	for _pass in range(passes):
		var next := current.duplicate()

		for i in range(1, current.size() - 1):
			var total := Vector2.ZERO
			var weight := 0

			for k in range(maxi(i - window, 0), mini(i + window, current.size() - 1) + 1):
				total += current[k]
				weight += 1

			next[i] = total / weight

		current = next

	return current


## Polyligne ouverte rééchantillonnée à pas constant (dernier point gardé).
static func resample_open(points: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var result := PackedVector2Array()

	if points.size() < 2:
		return points

	result.append(points[0])
	var carry := 0.0

	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)

		if length <= 0.0001:
			continue

		var d := spacing - carry

		while d <= length:
			result.append(a.lerp(b, d / length))
			d += spacing

		carry = length - (d - spacing)

	if result[result.size() - 1].distance_to(points[points.size() - 1]) > spacing * 0.3:
		result.append(points[points.size() - 1])

	return result


func drivable_extent(origin: Vector2, direction: Vector2) -> float:
	return _drivable_extent(origin, direction)


## Distance praticable depuis `origin` dans une direction (max 700 px).
func _drivable_extent(origin: Vector2, direction: Vector2) -> float:
	var distance := 0.0

	while distance < 700.0:
		if not is_drivable_cell(grid, world_to_cell(origin + direction * (distance + 8.0))):
			break

		distance += 8.0

	return distance


## Polyligne fermée rééchantillonnée à pas constant.
static func resample_closed(points: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var count := points.size()

	if count < 2:
		return points

	result.append(points[0])
	var carry := 0.0

	for i in range(count):
		var a := points[i]
		var b := points[(i + 1) % count]
		var length := a.distance_to(b)

		if length <= 0.0001:
			continue

		var d := spacing - carry

		while d <= length:
			result.append(a.lerp(b, d / length))
			d += spacing

		carry = length - (d - spacing)

	if result.size() > 1 and result[result.size() - 1].distance_to(result[0]) < spacing * 0.5:
		result.remove_at(result.size() - 1)

	return result


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
