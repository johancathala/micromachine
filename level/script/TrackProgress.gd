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

# Passages hors piste (herbe, gravier) : certains tracés en empruntent,
# balisés par des sacs de pneus (variantes Paddock). Le parcours n'y
# passe que s'il évite ainsi un grand détour (coût OFFROAD_WEIGHT par
# case) ; l'eau n'est jamais praticable.
const OFFROAD_KEYWORDS := {"herbe": "grass", "gravel": "gravel"}
const WATER_KEYWORD := "eau"
const OFFROAD_WEIGHT := 100.0

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
# Voie à vitesse limitée (nœud PitLane) : le tracé de course l'évite
# dès qu'une autre route existe.
const PIT_LIMITER_WEIGHT := 200.0
# Obstacles posés dans le circuit (balisage en sacs de pneus, souvent en
# pointillé) : épaissis de MARKER_DILATION cases pour le calcul du
# parcours, afin qu'une ligne de balisage forme une barrière continue.
const MARKER_DILATION := 2
# Autres obstacles durs : épaissis d'une case.
const HARD_DILATION := 1

var _cell_size := Vector2(32, 32)
var _reference_layer: TileMapLayer = null

# section_id -> chemin (PackedVector2Array) vers la section suivante.
var _paths: Dictionary = {}
# section_id -> longueurs cumulées le long du chemin.
var _cumulative: Dictionary = {}

var section_count := 0
# Portes des sections (section_id -> [a, b], coordonnées globales).
var gates: Dictionary = {}

# Grille praticable conservée après build() (axe de la chaussée pour l'IA).
var grid: AStarGrid2D = null
# Cases d'obstacles durs (murs, poteaux, objets), à distinguer de
# l'herbe (non praticable pour le parcours mais sans collision).
var hard_cells: Dictionary = {}
# Cases de route (asphalte, vibreur) ; les autres cases praticables de
# la grille sont hors piste (offroad_cells : case -> nom de surface).
var road_cells: Dictionary = {}
var offroad_cells: Dictionary = {}
# Outils de génération : grille limitée à la route.
var allow_offroad := true
# Physique du circuit (détection de surface, comme la voiture).
var _space: PhysicsDirectSpaceState2D = null
# Masque de détection du sol (GroundRay de Car.tscn).
const GROUND_PROBE_MASK := 1
# Cases de route fermées par l'épaississement des obstacles (rouvertes
# pour le trajet vers le stand, étroit par nature).
var _dilated_cells: Dictionary = {}

# Raison de l'échec de build(), pour le diagnostic.
var last_error := ""


## gate_segments : section_id -> [a, b] (porte de la section, en
## coordonnées globales). Retourne true si tous les tronçons ont un chemin.
func build(track: Node, gate_segments: Dictionary) -> bool:
	_paths.clear()
	_cumulative.clear()
	section_count = gate_segments.size()
	gates = gate_segments.duplicate()

	if section_count < 2:
		last_error = "moins de 2 sections"
		return false

	var astar := build_grid(track)

	if track is Node2D and (track as Node2D).is_inside_tree():
		_space = (track as Node2D).get_world_2d().direct_space_state

	if astar == null:
		return false

	grid = astar

	# Obstacles posés (barils, citerne...) : infranchissables, y compris
	# pour le parcours (un circuit peut en placer sur son tracé).
	_block_obstacles(track)

	# Points de passage possibles de chaque porte : une porte peut
	# couper plusieurs routes ; on garde chaque portion de route coupée.
	var candidates: Dictionary = {}

	for section_id in range(section_count):
		var segment: Array = gate_segments[section_id]
		candidates[section_id] = _gate_crossings(astar, segment[0], segment[1])

		if candidates[section_id].is_empty():
			last_error = "la porte de la section %d ne coupe aucune route" % section_id
			return false

	# Sens de franchissement de chaque porte (sens de la course) : une
	# porte se traverse, elle ne se longe pas. Le chemin part juste après
	# une porte et arrive juste avant la suivante, sans repasser par
	# l'une ou l'autre (une porte posée dans une trouée de mur impose
	# ainsi de sortir par cette trouée).
	var normals := _gate_normals(track, gate_segments)

	# Chemins entre points de passage de portes consécutives.
	# paths_between[k][[i, j]] = cellules du candidat i (porte k)
	# au candidat j (porte k+1).
	var paths_between: Dictionary = {}

	for section_id in range(section_count):
		var next_id := (section_id + 1) % section_count
		# Herbe et gravier permis, mais coûteux (OFFROAD_WEIGHT) : le
		# parcours n'y passe que pour éviter un grand détour.
		var table := _section_paths(astar, section_id, next_id, candidates, normals, not offroad_cells.is_empty())

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
						offroad_cells.erase(Vector2i(x, y))


## Portions de route coupées par la porte [a, b] : une case
## (milieu de la portion) par portion praticable.
func _gate_crossings(
	astar: AStarGrid2D,
	a: Vector2,
	b: Vector2,
	road_only: bool = true
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

		var walkable := road_cells.has(cell) if road_only else (road_cells.has(cell) or offroad_cells.has(cell))

		if walkable:
			run.append(cell)
		elif not run.is_empty():
			result.append(run[run.size() / 2])
			run.clear()

	if not run.is_empty():
		result.append(run[run.size() / 2])

	# Porte sans route (passage hors piste) : on passe sur l'herbe.
	if result.is_empty() and road_only:
		return _gate_crossings(astar, a, b, false)

	return result


## Grille A* des cases praticables du circuit (null si impossible).
## Le nœud « Map » peut être à la racine du circuit ou dans une carte
## intégrée (variantes de circuit réutilisant une autre carte) ; les
## couches de tuiles posées à la racine du circuit comptent aussi.
func build_grid(track: Node) -> AStarGrid2D:
	var map := track.get_node_or_null("Map")

	if map == null:
		map = track.find_child("Map", true, false)

	if map == null:
		last_error = "nœud Map absent"
		return null

	var drivable: Dictionary = {}
	var layers: Array[TileMapLayer] = []
	# Couches de la carte, plus celles posées directement dans le circuit
	# (sacs de pneus, décor propres à un tracé).
	var candidates: Array[Node] = map.get_children()

	if map.get_parent() != track:
		candidates.append_array(track.get_children())

	for child in candidates:
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

	# Cases hors piste (herbe, gravier), hors eau.
	var offroad: Dictionary = {}

	if allow_offroad:
		var water: Dictionary = {}

		for layer in layers:
			var lower_name := String(layer.name).to_lower()

			if lower_name.contains(WATER_KEYWORD):
				for cell in layer.get_used_cells():
					water[_to_grid(layer, cell)] = true

		for layer in layers:
			var lower_name := String(layer.name).to_lower()

			for keyword in OFFROAD_KEYWORDS:
				if lower_name.contains(keyword):
					for cell in layer.get_used_cells():
						var grid_cell := _to_grid(layer, cell)

						if not drivable.has(grid_cell) and not water.has(grid_cell):
							offroad[grid_cell] = OFFROAD_KEYWORDS[keyword]

	# Cases bloquées : tuiles avec collision, quelle que soit la couche.
	var blocked: Dictionary = {}
	var markers: Dictionary = {}

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

			if layer.get_parent() == track:
				markers[_to_grid(layer, cell)] = true

	hard_cells = blocked.duplicate()

	# Obstacles épaissis pour le calcul du parcours : pas de couloir plus
	# étroit qu'une voiture entre deux obstacles.
	for cell in hard_cells:
		var dilation := MARKER_DILATION if markers.has(cell) else HARD_DILATION

		for dx in range(-dilation, dilation + 1):
			for dy in range(-dilation, dilation + 1):
				blocked[cell + Vector2i(dx, dy)] = true

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

	road_cells.clear()
	offroad_cells.clear()

	_dilated_cells.clear()

	for cell in drivable:
		if not blocked.has(cell):
			astar.set_point_solid(cell, false)
			road_cells[cell] = true
		elif not hard_cells.has(cell):
			# Route fermée seulement par l'épaississement des obstacles.
			_dilated_cells[cell] = true

	# Cases hors piste fermées par défaut (voir _set_offroad_open).
	for cell in offroad:
		if not blocked.has(cell) and astar.is_in_boundsv(cell):
			offroad_cells[cell] = offroad[cell]

	_weight_pit_lane(track, astar)
	_weight_speed_limited(track, astar)

	return astar


## Cases de la voie à vitesse limitée (PitLane) : très coûteuses.
func _weight_speed_limited(track: Node, astar: AStarGrid2D, weight: float = PIT_LIMITER_WEIGHT) -> void:
	var lane := track.get_node_or_null("PitLane")

	if lane == null:
		return

	for child in lane.get_children():
		var shape := child as CollisionShape2D

		if shape == null or not shape.shape is RectangleShape2D or shape.disabled:
			continue

		var area := _shape_bounds(shape)
		var c0 := world_to_cell(area.position)
		var c1 := world_to_cell(area.end)

		for x in range(mini(c0.x, c1.x), maxi(c0.x, c1.x) + 1):
			for y in range(mini(c0.y, c1.y), maxi(c0.y, c1.y) + 1):
				var cell := Vector2i(x, y)

				if road_cells.has(cell) or _dilated_cells.has(cell):
					astar.set_point_weight_scale(cell, weight)


## Rend la voie des stands plus coûteuse (zone du nœud PitStop).
func _weight_pit_lane(track: Node, astar: AStarGrid2D, weight: float = PIT_LANE_WEIGHT) -> void:
	var pit := track.get_node_or_null("PitStop") as Node2D

	if pit == null:
		return

	for shape in _pit_shapes(pit):
		var area := _shape_bounds(shape).grow_individual(
			PIT_WEIGHT_MARGIN.x, PIT_WEIGHT_MARGIN.y,
			PIT_WEIGHT_MARGIN.x, PIT_WEIGHT_MARGIN.y
		)
		var c0 := world_to_cell(area.position)
		var c1 := world_to_cell(area.end)

		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				var cell := Vector2i(x, y)

				if road_cells.has(cell):
					astar.set_point_weight_scale(cell, weight)


## Zones d'arrêt du stand (rectangles ; un stand peut en avoir
## plusieurs, une par emplacement).
static func _pit_shapes(pit: Node) -> Array[CollisionShape2D]:
	var shapes: Array[CollisionShape2D] = []

	for child in pit.get_children():
		var shape := child as CollisionShape2D

		if shape != null and shape.shape is RectangleShape2D and not shape.disabled:
			shapes.append(shape)

	return shapes


## Rectangle englobant (coordonnées globales) d'une zone.
static func _shape_bounds(shape: CollisionShape2D) -> Rect2:
	var half := (shape.shape as RectangleShape2D).size / 2.0
	var area := Rect2(shape.to_global(-half), Vector2.ZERO)

	for corner in [Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
		area = area.expand(shape.to_global(corner))

	return area


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


## Distance (px) gardée par la trajectoire aux obstacles durs.
const HARD_MARGIN := 120.0


## Distance jusqu'à la première case bloquante (obstacle dur) dans une
## direction (max 700 px) ; l'herbe et le gravier ne l'arrêtent pas.
func _hard_extent(origin: Vector2, direction: Vector2) -> float:
	var distance := 0.0

	while distance < 700.0:
		if hard_cells.has(world_to_cell(origin + direction * (distance + 8.0))):
			break

		distance += 8.0

	return distance


## Marge (px) gardée aux extrémités d'une porte, et nombre de points
## de la trajectoire contraints de part et d'autre de la porte.
const GATE_MARGIN := 60.0
const GATE_CONSTRAINT_POINTS := 1


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
		# Bord de chaussée : `margin` ; obstacle dur (mur, bâtiment,
		# arbre...) : HARD_MARGIN, un écart y est fatal.
		left_room[i] = maxf(minf(_drivable_extent(center[i], normal) - margin, _hard_extent(center[i], normal) - HARD_MARGIN), 0.0)
		right_room[i] = maxf(minf(_drivable_extent(center[i], -normal) - margin, _hard_extent(center[i], -normal) - HARD_MARGIN), 0.0)

	# Portes des sections : la trajectoire doit les franchir (sinon le
	# passage compte comme un raccourci). Près de chaque porte, le
	# décalage est limité à la portion de porte praticable.
	var gate_low := PackedFloat32Array()
	var gate_high := PackedFloat32Array()
	gate_low.resize(count)
	gate_high.resize(count)
	gate_low.fill(-INF)
	gate_high.fill(INF)

	for section_id in gates:
		var a: Vector2 = gates[section_id][0]
		var b: Vector2 = gates[section_id][1]
		# Point où l'axe franchit la porte ; à défaut, le plus proche (une
		# longue porte peut passer près d'une autre portion de route :
		# la distance seule désignerait le mauvais endroit).
		var nearest := -1

		for i in range(count):
			if Geometry2D.segment_intersects_segment(center[i], center[(i + 1) % count], a, b) != null:
				nearest = i
				break

		if nearest < 0:
			var nearest_distance := INF

			for i in range(count):
				var distance := center[i].distance_squared_to(Geometry2D.get_closest_point_to_segment(center[i], a, b))

				if distance < nearest_distance:
					nearest_distance = distance
					nearest = i

		for k in range(-GATE_CONSTRAINT_POINTS, GATE_CONSTRAINT_POINTS + 1):
			var i := posmod(nearest + k, count)
			var t_a := (a - center[i]).dot(normals[i])
			var t_b := (b - center[i]).dot(normals[i])
			var low := minf(t_a, t_b) + GATE_MARGIN
			var high := maxf(t_a, t_b) - GATE_MARGIN

			if low > high:
				low = (t_a + t_b) / 2.0
				high = low

			gate_low[i] = maxf(gate_low[i], low)
			gate_high[i] = minf(gate_high[i], maxf(high, gate_low[i]))

	# Bornes finales : chaussée, et porte s'il y en a une (la porte
	# l'emporte si les deux sont incompatibles).
	var low_bound := PackedFloat32Array()
	var high_bound := PackedFloat32Array()
	low_bound.resize(count)
	high_bound.resize(count)

	for i in range(count):
		var low := -right_room[i]
		var high := left_room[i]

		if gate_low[i] > -INF:
			var clamped_low := maxf(low, gate_low[i])
			var clamped_high := minf(high, gate_high[i])

			if clamped_low <= clamped_high:
				low = clamped_low
				high = clamped_high
			else:
				low = gate_low[i]
				high = gate_high[i]

		low_bound[i] = low
		high_bound[i] = high

	# Décalage latéral par rapport à l'axe.
	var offsets := PackedFloat32Array()
	offsets.resize(count)

	for i in range(count):
		offsets[i] = clampf(0.0, low_bound[i], high_bound[i])

	for _iteration in range(iterations):
		for i in range(count):
			var previous := center[posmod(i - 1, count)] + normals[posmod(i - 1, count)] * offsets[posmod(i - 1, count)]
			var next := center[(i + 1) % count] + normals[(i + 1) % count] * offsets[(i + 1) % count]
			var middle := (previous + next) / 2.0
			# Projection du milieu sur la normale : nouveau décalage.
			var wanted := (middle - center[i]).dot(normals[i])
			offsets[i] = clampf(lerpf(offsets[i], wanted, 0.6), low_bound[i], high_bound[i])

	var line := PackedVector2Array()
	line.resize(count)

	for i in range(count):
		line[i] = center[i] + normals[i] * offsets[i]

	# Le lissage peut couper un coin à travers un obstacle : les points
	# trop proches d'un obstacle dur en sont écartés.
	line = _push_from_hard_cells(line, LINE_CLEARANCE, true)

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

	var shapes := _pit_shapes(pit)

	if shapes.is_empty():
		return {}

	# Voie des stands : ensemble des zones (alignées le long de la voie).
	var bounds := _shape_bounds(shapes[0])

	for shape in shapes:
		bounds = bounds.merge(_shape_bounds(shape))

	var size := bounds.size
	var center := bounds.get_center()
	var axis := Vector2.DOWN if size.y >= size.x else Vector2.RIGHT
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

	# Calcul sans surcoût de la voie des stands ni de la voie limitée,
	# obstacles à leur taille réelle (la voie des stands est étroite).
	_weight_pit_lane(track, grid, 1.0)
	_weight_speed_limited(track, grid, 1.0)

	for cell in _dilated_cells:
		grid.set_point_solid(cell, false)
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
	_weight_speed_limited(track, grid)

	for cell in _dilated_cells:
		grid.set_point_solid(cell, true)

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

	# Arrêt : premier point bien engagé dans une des zones d'arrêt.
	var stop_index := -1
	var inside_run := 0

	for i in range(points.size()):
		if _inside_pit_zone(shapes, points[i]):
			inside_run += 1

			if inside_run > PIT_STOP_ALIGNED:
				stop_index = i
				break
		else:
			inside_run = 0

	if stop_index < 0:
		return {}

	# Voie des stands à vitesse limitée (PitLane) : limite en chaque point
	# du trajet (0 : aucune).
	var speed_limits := PackedFloat32Array()
	speed_limits.resize(points.size())
	var pit_lane := track.get_node_or_null("PitLane") as PitLane

	for i in range(points.size()):
		speed_limits[i] = pit_lane.speed_limit if pit_lane != null and pit_lane.contains_point(points[i]) else 0.0

	return {
		"points": points,
		"entry_index": entry_index,
		"exit_index": exit_index,
		"stop_index": stop_index,
		"speed_limits": speed_limits
	}


static func _inside_pit_zone(shapes: Array[CollisionShape2D], point: Vector2) -> bool:
	for shape in shapes:
		var local := shape.global_transform.affine_inverse() * point
		var inner := (shape.shape as RectangleShape2D).size / 2.0 - Vector2(PIT_STOP_INSET, PIT_STOP_INSET)

		if absf(local.x) <= inner.x and absf(local.y) <= inner.y:
			return true

	return false


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
## Distance minimale (px) entre la trajectoire de course et un obstacle dur.
const LINE_CLEARANCE := 90.0


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
func _push_from_hard_cells(points: PackedVector2Array, clearance: float = HARD_CLEARANCE, closed: bool = false) -> PackedVector2Array:
	var result := points.duplicate()
	var reach := int(ceil(clearance / _cell_size.x))
	var first := 0 if closed else 1
	var last := result.size() if closed else result.size() - 1

	for _pass in range(3):
		for i in range(first, last):
			var origin := world_to_cell(result[i])
			var push := Vector2.ZERO

			for x in range(-reach, reach + 1):
				for y in range(-reach, reach + 1):
					var cell := origin + Vector2i(x, y)

					if not hard_cells.has(cell):
						continue

					var away := result[i] - _cell_to_world(cell)
					var distance := away.length()

					if distance < clearance and distance > 0.01:
						push += away / distance * (clearance - distance)

			result[i] += push.limit_length(clearance) * 0.5

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

				if is_road_cell(cell):
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
	# Sur la route : la chaussée. Dans un passage hors piste : le couloir
	# (herbe et route) jusqu'au balisage ou à un obstacle.
	var offroad := offroad_cells.has(world_to_cell(origin))

	while distance < 700.0:
		var cell := world_to_cell(origin + direction * (distance + 8.0))

		if not is_road_cell(cell) and not (offroad and offroad_cells.has(cell)):
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


## Case de route (asphalte, vibreur) non bloquée.
func is_road_cell(cell: Vector2i) -> bool:
	return road_cells.has(cell) and grid != null and not grid.is_point_solid(cell)


## Surface réellement roulée en un point, d'après les calques physiques
## présents (comme Car.get_surface_profile) ; aucun calque reconnu :
## profil DEFAULT, comme la voiture. Sans physique : d'après les cases.
func surface_at(world_position: Vector2) -> SurfaceProfile:
	if _space != null:
		# Tous les calques présents au point ; la route l'emporte (une
		# route est peinte par-dessus l'herbe).
		var query := PhysicsPointQueryParameters2D.new()
		query.position = world_position
		query.collision_mask = GROUND_PROBE_MASK
		var groups: Dictionary = {}

		for hit in _space.intersect_point(query, 16):
			var collider: Object = hit.get("collider")

			if collider is Node:
				for group in (collider as Node).get_groups():
					groups[String(group)] = true

		for profile in [
			["asphalt", SurfaceCatalog.ASPHALT], ["gravel", SurfaceCatalog.GRAVEL],
			["mud", SurfaceCatalog.MUD], ["ice", SurfaceCatalog.ICE], ["grass", SurfaceCatalog.GRASS]
		]:
			if groups.has(profile[0]):
				return profile[1]

		return SurfaceCatalog.DEFAULT

	var name: String = offroad_cells.get(world_to_cell(world_position), "")

	if name == "grass":
		return SurfaceCatalog.GRASS

	if name == "gravel":
		return SurfaceCatalog.GRAVEL

	return SurfaceCatalog.ASPHALT


## Normale de chaque porte, orientée dans le sens de la course (point de
## réapparition de la section, sinon vers la porte suivante).
func _gate_normals(track: Node, gate_segments: Dictionary) -> Dictionary:
	var directions: Dictionary = {}
	var sections := track.get_node_or_null("Sections")

	if sections != null:
		for section in sections.get_children():
			var marker := section.get_node_or_null("RespawnPoint") as Node2D

			if marker != null and section.get("section_id") != null:
				directions[int(section.get("section_id"))] = Vector2.RIGHT.rotated(marker.global_rotation)

	var normals: Dictionary = {}

	for section_id in gate_segments:
		var a: Vector2 = gate_segments[section_id][0]
		var b: Vector2 = gate_segments[section_id][1]
		var normal := (b - a).orthogonal().normalized()
		var wanted: Vector2 = directions.get(section_id, Vector2.ZERO)

		if wanted == Vector2.ZERO:
			var next: Array = gate_segments[(section_id + 1) % gate_segments.size()]
			wanted = ((next[0] + next[1]) / 2.0) - (a + b) / 2.0

		normals[section_id] = normal if normal.dot(wanted) >= 0.0 else -normal

	return normals


## Chemins du tronçon section_id -> next_id entre leurs points de
## passage : départ juste après la porte, arrivée juste avant la
## suivante, toutes les portes fermées entre-temps. `offroad` : herbe et
## gravier ouverts.
func _section_paths(
	astar: AStarGrid2D,
	section_id: int,
	next_id: int,
	candidates: Dictionary,
	normals: Dictionary,
	offroad: bool
) -> Dictionary:
	if offroad:
		_set_offroad_open(astar, true)

	var closed: Dictionary = {}

	# Toutes les portes fermées : un tronçon ne franchit aucune autre
	# porte (ce serait un raccourci, ou un retour en arrière).
	for id in gates:
		for cell in _gate_line_cells(gates[id][0], gates[id][1]):
			if astar.is_in_boundsv(cell) and not closed.has(cell):
				closed[cell] = astar.is_point_solid(cell)
				astar.set_point_solid(cell, true)

	var table: Dictionary = {}

	for i in range(candidates[section_id].size()):
		var from_cell: Vector2i = candidates[section_id][i]
		var start := _beside_gate(astar, from_cell, normals[section_id])

		for j in range(candidates[next_id].size()):
			var to_cell: Vector2i = candidates[next_id][j]
			var goal := _beside_gate(astar, to_cell, -normals[next_id])

			if start == NO_CELL or goal == NO_CELL:
				continue

			var cells := astar.get_id_path(start, goal)

			if cells.is_empty():
				continue

			var path: Array[Vector2i] = [from_cell]
			path.append_array(cells)
			path.append(to_cell)
			table[Vector2i(i, j)] = path

	for cell in closed:
		astar.set_point_solid(cell, closed[cell])

	if offroad:
		_set_offroad_open(astar, false)

	return table


const NO_CELL := Vector2i(-2147483648, 0)
## Distance (px) au-delà de la porte du point de départ / d'arrivée.
const GATE_STEP := 48.0


## Case praticable juste à côté d'une porte, du côté `side` ; NO_CELL
## si aucune (porte au bord d'un obstacle).
func _beside_gate(astar: AStarGrid2D, cell: Vector2i, side: Vector2) -> Vector2i:
	var origin := _cell_to_world(cell)

	for step in [GATE_STEP, GATE_STEP * 1.5, GATE_STEP * 2.0]:
		var beside := world_to_cell(origin + side * step)

		if astar.is_in_boundsv(beside) and not astar.is_point_solid(beside):
			return beside

	return NO_CELL


## Cases de la grille sous le segment d'une porte, prolongé de
## GATE_END_EXTENSION px à chaque bout (on ne contourne pas une porte).
const GATE_END_EXTENSION := 96.0

func _gate_line_cells(a: Vector2, b: Vector2) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var along := (b - a).normalized()
	a -= along * GATE_END_EXTENSION
	b += along * GATE_END_EXTENSION
	var steps := maxi(int(a.distance_to(b) / (_cell_size.x * 0.5)), 1)

	for k in range(steps + 1):
		var cell := world_to_cell(a.lerp(b, float(k) / steps))

		if cells.is_empty() or cells[cells.size() - 1] != cell:
			cells.append(cell)

	return cells


## Ouvre (ou referme) les cases hors piste au calcul de chemin.
func _set_offroad_open(astar: AStarGrid2D, open: bool) -> void:
	for cell in offroad_cells:
		astar.set_point_solid(cell, not open)

		if open:
			astar.set_point_weight_scale(cell, OFFROAD_WEIGHT)


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
