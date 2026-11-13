extends SceneTree

# ============================================================
# Variantes du circuit de Brissac (Track01) : même carte, autre
# cheminement des voitures.
#
#   godot --headless --path . -s tools/track/build_brissac_variants.gd
#
# Chaque variante est une scène qui intègre Track01 tel quel (nœud
# « Brissac ») et définit à sa racine ses propres Sections,
# SpawnPoints, PitStop et feux. Le tracé est calculé par A* sur les
# routes de la carte entre des points de passage ; les portes sont
# posées perpendiculairement au tracé, limitées à la chaussée (elles
# ne débordent pas sur une route voisine séparée par un vibreur).
# Une image de contrôle par variante est écrite dans
# level/track/variants/ (dossier ignoré par Godot).
# ============================================================

const BASE_SCENE := "res://level/track/Track01.tscn"
const PREVIEW_DIR := "res://level/track/variants/"

# Brissac : stand (voie des stands, à l'ouest de la ligne droite).
const PIT_POSITION := Vector2(100, 385)
const PIT_SIZE := Vector2(160, 2000)

# Une porte tous les ~4500 px de tracé (au moins 10).
const GATE_SPACING := 4500.0
# Une porte régulière trop proche d'une porte obligatoire est retirée.
const FORCED_GATE_CLEARANCE := 1500.0
const MIN_SECTIONS := 10
# Demi-largeur maximale d'une porte et marge au-delà de la chaussée.
const GATE_MAX_HALF := 700.0
const GATE_MARGIN := 32.0
const GATE_STEP := 8.0

const VARIANTS := [
	{
		"file": "Track05.tscn", "name": "TrackReverse",
		"route": "reverse",
		# Voie des stands interdite au calcul du tracé : il passe par la
		# ligne droite de départ, comme le Brissac d'origine.
		"blocked_rects": [Rect2(-500, -1300, 950, 3700)]
	},
	{
		"file": "Track02.tscn", "name": "TrackPaddock1",
		"route": "paddock1"
	},
	{
		"file": "Track03.tscn", "name": "TrackPaddock2",
		"route": "paddock2",
		# Porte obligatoire dans la voie des stands : prendre la ligne
		# droite à la place est un raccourci.
		"forced_gates": [Vector2(100, 385)]
	}
]

var base: Node2D
var progress: TrackProgress
var astar: AStarGrid2D
var brissac_paths: Array[PackedVector2Array] = []
var asphalt_cells: Dictionary = {}
var kerb_cells: Dictionary = {}


func _initialize() -> void:
	base = (load(BASE_SCENE) as PackedScene).instantiate() as Node2D
	root.add_child(base)

	progress = TrackProgress.new()

	var gates: Dictionary = {}

	for section in base.get_node("Sections").get_children():
		var shape: CollisionShape2D = section.get_node("CollisionShape2D")
		var segment := shape.shape as SegmentShape2D
		gates[section.section_id] = [shape.to_global(segment.a), shape.to_global(segment.b)]

	if not progress.build(base, gates):
		push_error("Brissac : " + progress.last_error)
		quit(1)
		return

	astar = progress.build_grid(base)

	for k in range(progress.section_count):
		brissac_paths.append(progress.get_path(k))

	_collect_surface_cells()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIR))

	for variant in VARIANTS:
		_build_variant(variant)

	base.free()
	quit()


# ------------------------------------------------------------
# Points de passage de chaque variante
# ------------------------------------------------------------

func _waypoints(route: String) -> PackedVector2Array:
	match route:
		"reverse":
			# Tour de Brissac à l'envers, départ sur la même ligne.
			var points := _brissac_loop()
			points.reverse()

			var kept := PackedVector2Array()

			for point in points:
				# Points du tracé de référence le long de la ligne droite et
				# de la voie des stands : remplacés par des points explicites.
				if point.x > -500.0 and point.x < 1350.0 and point.y > -1700.0 and point.y < 3300.0:
					continue
				kept.append(point)

			# Ordre explicite : départ sur la ligne droite de Brissac
			# (1347) vers le sud, puis le tour à l'envers à partir du bas
			# de la ligne droite, retour par le haut de la ligne droite.
			var lap := _rotate_to(_sample(kept, 6), Vector2(820, 3400))
			var result := PackedVector2Array([Vector2(820, 1347), Vector2(820, 2300)])
			result.append_array(lap)
			result.append(Vector2(820, -800))
			return result

		"paddock1":
			# Boucle des stands et de l'enclos : longue route ouest vers
			# le sud (départ), rond-point, retour par l'enclos, voie des
			# stands vers le nord, route ouest.
			return PackedVector2Array([
				Vector2(-4144, 1200),
				Vector2(-4144, 2840),
				Vector2(-2480, 2840),
				Vector2(-2224, 2160),
				Vector2(-1200, 2000),
				Vector2(100, 1500),
				Vector2(100, 385),
				Vector2(100, -700),
				Vector2(-480, -1000),
				Vector2(-4120, -1000),
				Vector2(-4144, 0)
			])

		"paddock2":
			# Tour de Brissac, la voie des stands remplaçant la ligne
			# droite de départ. Départ sur la ligne droite de retour.
			var points := PackedVector2Array()

			for k in range(brissac_paths.size()):
				for point in brissac_paths[k]:
					# Ligne droite de départ (x 500-1300) écartée entre la
					# bretelle des stands et leur sortie nord.
					if point.x > 450.0 and point.x < 1350.0 and point.y > -1700.0 and point.y < 2700.0:
						continue
					points.append(point)

				# Après le tronçon 13 (bas de la ligne droite) : les stands.
				if k == 13:
					pass

			# Insère la voie des stands là où la ligne droite a été retirée.
			var result := PackedVector2Array()
			var inserted := false

			for i in range(points.size()):
				result.append(points[i])

				if not inserted and i + 1 < points.size():
					var gap := points[i].distance_to(points[i + 1])

					if gap > 2000.0:
						result.append_array(PackedVector2Array([
							Vector2(450, 2650), Vector2(100, 1500),
							Vector2(100, 385), Vector2(100, -700)
						]))
						inserted = true

			if not inserted:
				result.append_array(PackedVector2Array([
					Vector2(450, 2650), Vector2(100, 1500),
					Vector2(100, 385), Vector2(100, -700)
				]))

			# Départ au milieu de la ligne droite de retour (tronçon 10).
			var start := brissac_paths[10][brissac_paths[10].size() / 2]
			return _rotate_to(_sample(result, 6), start)

	return PackedVector2Array()


## Insère `extra` au plus grand écart entre deux points consécutifs.
func _insert_at_gap(points: PackedVector2Array, extra: PackedVector2Array) -> PackedVector2Array:
	var best := 0

	for i in range(points.size() - 1):
		if points[i].distance_to(points[i + 1]) > points[best].distance_to(points[best + 1]):
			best = i

	var result := points.slice(0, best + 1)
	result.append_array(extra)
	result.append_array(points.slice(best + 1))
	return result


func _brissac_loop() -> PackedVector2Array:
	var points := PackedVector2Array()

	for path in brissac_paths:
		points.append_array(path)

	return points


func _sample(points: PackedVector2Array, every: int) -> PackedVector2Array:
	var result := PackedVector2Array()

	for i in range(0, points.size(), every):
		result.append(points[i])

	return result


func _rotate_to(points: PackedVector2Array, start: Vector2) -> PackedVector2Array:
	var best := 0

	for i in range(points.size()):
		if points[i].distance_to(start) < points[best].distance_to(start):
			best = i

	var result := points.slice(best)
	result.append_array(points.slice(0, best))
	return result


# ------------------------------------------------------------
# Tracé complet (A* entre points de passage, boucle fermée)
# ------------------------------------------------------------

func _route(waypoints: PackedVector2Array) -> PackedVector2Array:
	var route := PackedVector2Array()
	var count := waypoints.size()

	for i in range(count):
		var from := progress.world_to_cell(waypoints[i])
		var to := progress.world_to_cell(waypoints[(i + 1) % count])
		var cells := astar.get_id_path(_snap(from), _snap(to))

		if cells.is_empty():
			push_error("Pas de chemin entre %s et %s" % [waypoints[i], waypoints[(i + 1) % count]])
			continue

		for cell in cells:
			var point := progress.cell_to_world(cell)

			if route.is_empty() or route[route.size() - 1] != point:
				route.append(point)

	# Retire le point final s'il boucle sur le premier.
	if route.size() > 1 and route[route.size() - 1] == route[0]:
		route.remove_at(route.size() - 1)

	return route


func _snap(cell: Vector2i) -> Vector2i:
	for radius in range(12):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var candidate := cell + Vector2i(dx, dy)

				if progress.is_drivable_cell(astar, candidate):
					return candidate

	return cell


## Distance le long du tracé du point le plus proche de `point`.
func _distance_along(route: PackedVector2Array, lengths: PackedFloat32Array, point: Vector2) -> float:
	var best := 0

	for i in range(route.size()):
		if route[i].distance_to(point) < route[best].distance_to(point):
			best = i

	return lengths[best]


func _cumulative(route: PackedVector2Array) -> PackedFloat32Array:
	var lengths := PackedFloat32Array([0.0])

	for i in range(1, route.size() + 1):
		lengths.append(lengths[i - 1] + route[i - 1].distance_to(route[i % route.size()]))

	return lengths


func _point_at(route: PackedVector2Array, lengths: PackedFloat32Array, distance: float) -> Array:
	var total := lengths[lengths.size() - 1]
	distance = fposmod(distance, total)

	for i in range(route.size()):
		if lengths[i + 1] >= distance:
			var a := route[i]
			var b := route[(i + 1) % route.size()]
			var t := (distance - lengths[i]) / maxf(lengths[i + 1] - lengths[i], 0.001)
			# Direction lissée sur ~5 cases pour des portes bien
			# perpendiculaires même dans l'escalier du tracé A*.
			var before := route[posmod(i - 4, route.size())]
			var after := route[(i + 5) % route.size()]
			return [a.lerp(b, t), (after - before).normalized()]

	return [route[0], Vector2.RIGHT]


# ------------------------------------------------------------
# Surfaces : asphalte / vibreurs (pour borner les portes)
# ------------------------------------------------------------

func _collect_surface_cells() -> void:
	var map := base.get_node("Map")

	for child in map.get_children():
		var layer := child as TileMapLayer

		if layer == null:
			continue

		var lower := String(layer.name).to_lower()
		var target: Dictionary

		if lower.contains("asphalte"):
			target = asphalt_cells
		elif lower.contains("vibreur"):
			target = kerb_cells
		else:
			continue

		for cell in layer.get_used_cells():
			target[progress.world_to_cell(layer.to_global(layer.map_to_local(cell)))] = true


## Distance jusqu'au bord de la chaussée dans une direction : on
## traverse l'asphalte et un vibreur de bord, mais on s'arrête si de
## l'asphalte réapparaît après un vibreur (autre route voisine).
## stop_at_other_road = false : on ne s'arrête qu'en sortant des
## surfaces praticables (porte obligatoire couvrant toute une zone,
## ex. voie des stands + bande de l'enclos).
func _extent(center: Vector2, direction: Vector2, stop_at_other_road: bool = true) -> float:
	var distance := 0.0
	var crossed_kerb := false
	var last_good := 0.0

	while distance < GATE_MAX_HALF:
		distance += GATE_STEP
		var cell := progress.world_to_cell(center + direction * distance)

		if not progress.is_drivable_cell(astar, cell):
			break

		if kerb_cells.has(cell) and not asphalt_cells.has(cell):
			crossed_kerb = true
		elif crossed_kerb and stop_at_other_road:
			# Asphalte après un vibreur : une autre route commence.
			break

		last_good = distance

	return last_good + GATE_MARGIN


# ------------------------------------------------------------
# Construction de la scène
# ------------------------------------------------------------

func _build_variant(variant: Dictionary) -> void:
	var waypoints := _waypoints(variant["route"])

	# Zones interdites au calcul du tracé de cette variante.
	var blocked: Array[Vector2i] = []

	for rect in variant.get("blocked_rects", []):
		var c0 := progress.world_to_cell((rect as Rect2).position)
		var c1 := progress.world_to_cell((rect as Rect2).end)

		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				var cell := Vector2i(x, y)

				if progress.is_drivable_cell(astar, cell):
					astar.set_point_solid(cell, true)
					blocked.append(cell)

	var route := _route(waypoints)

	for cell in blocked:
		astar.set_point_solid(cell, false)
	var lengths := _cumulative(route)
	var total := lengths[lengths.size() - 1]
	var regular_count := maxi(MIN_SECTIONS, int(round(total / GATE_SPACING)))

	# Distances des portes le long du tracé : régulières + obligatoires.
	var forced: Array = []

	for point in variant.get("forced_gates", []):
		forced.append(_distance_along(route, lengths, point))

	var gate_distances: Array = []

	for k in range(regular_count):
		var distance := total * k / regular_count
		var keep := true

		for f in forced:
			var gap := absf(distance - f)
			gap = minf(gap, total - gap)

			if gap < FORCED_GATE_CLEARANCE and k != 0:
				keep = false

		if keep:
			gate_distances.append(distance)

	gate_distances.append_array(forced)
	gate_distances.sort()
	var section_count := gate_distances.size()

	var scene_root := Node2D.new()
	scene_root.name = variant["name"]

	# Feux de départ en premier : RaceStartLights prend le premier nœud
	# du groupe (ceux de Brissac, intégrés, restent décoratifs).
	var start_data := _point_at(route, lengths, 0.0)
	var lights := (load("res://level/scene/RaceStartLightsMap.tscn") as PackedScene).instantiate() as Node2D
	lights.name = "RaceStartLightsMap"
	lights.z_index = 3
	lights.position = (start_data[0] as Vector2) + Vector2(-145, -60)
	_add(scene_root, lights, scene_root)

	var map_instance := (load(BASE_SCENE) as PackedScene).instantiate()
	map_instance.name = "Brissac"
	_add(scene_root, map_instance, scene_root)

	# ---- Sections ----
	var sections := Node2D.new()
	sections.name = "Sections"
	_add(scene_root, sections, scene_root)

	var section_script := load("res://level/script/RaceSection.gd")
	var gate_lines: Array = []

	for k in range(section_count):
		var data := _point_at(route, lengths, gate_distances[k])
		var center: Vector2 = data[0]
		var direction: Vector2 = data[1]
		var normal := direction.orthogonal()
		var whole_area: bool = forced.has(gate_distances[k])
		var a := center + normal * _extent(center, normal, not whole_area)
		var b := center - normal * _extent(center, -normal, not whole_area)
		gate_lines.append([a, b])

		var area := Area2D.new()
		area.name = "Section%02d" % k
		area.set_script(section_script)
		area.set("section_id", k)
		area.collision_mask = 2
		area.position = center
		_add(sections, area, scene_root)

		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var segment := SegmentShape2D.new()
		segment.a = a - center
		segment.b = b - center
		shape.shape = segment
		_add(area, shape, scene_root)

		var respawn := Marker2D.new()
		respawn.name = "RespawnPoint"
		respawn.rotation = direction.angle()
		_add(area, respawn, scene_root)

	# ---- Grille de départ : derrière la ligne, en remontant le tracé ----
	var spawns := Node2D.new()
	spawns.name = "SpawnPoints"
	_add(scene_root, spawns, scene_root)

	var spawn_points: Array = []

	for slot in range(8):
		var data := _point_at(route, lengths, -(150.0 + slot * 190.0))
		var center: Vector2 = data[0]
		var direction: Vector2 = data[1]
		var normal := direction.orthogonal()
		# Le tracé A* longe les bords : on se recentre sur la chaussée.
		var left := _extent(center, normal) - GATE_MARGIN
		var right := _extent(center, -normal) - GATE_MARGIN
		var middle := center + normal * (left - right) / 2.0
		# Quinconce si la route est assez large, sinon file indienne.
		var lateral := clampf((left + right) / 2.0 - 70.0, 0.0, 110.0)
		var side := lateral if slot % 2 == 0 else -lateral

		var marker := Marker2D.new()
		marker.name = "Spawn%02d" % (slot + 1)
		marker.position = middle + normal * side
		marker.rotation = direction.angle()
		_add(spawns, marker, scene_root)
		spawn_points.append(marker.position)

	# ---- Stand (voie des stands de Brissac) ----
	var pit := Area2D.new()
	pit.name = "PitStop"
	pit.set_script(load("res://level/script/PitStop.gd"))
	pit.position = PIT_POSITION
	_add(scene_root, pit, scene_root)

	var pit_shape := CollisionShape2D.new()
	pit_shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = PIT_SIZE
	pit_shape.shape = rect
	_add(pit, pit_shape, scene_root)

	var packed := PackedScene.new()
	packed.pack(scene_root)
	var path: String = "res://level/track/" + variant["file"]
	var error := ResourceSaver.save(packed, path)

	print("%-14s -> %s : %s ; tour %d px (%d m), %d sections, %d points de passage" % [
		variant["name"], path, "OK" if error == OK else "erreur %d" % error,
		total, total / 34.0, section_count, waypoints.size()
	])

	_save_preview(variant["name"], route, gate_lines, spawn_points)
	scene_root.free()


func _add(parent: Node, child: Node, owner_node: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node


## Image de contrôle : routes (gris), tracé (jaune, du vert au rouge
## selon l'avancement), portes (rouge), grille (bleu).
func _save_preview(variant_name: String, route: PackedVector2Array, gates: Array, spawns: Array) -> void:
	var cell0 := Vector2i(-480, -380)
	var size := Vector2i(640, 580)
	var image := Image.create(size.x * 2, size.y * 2, false, Image.FORMAT_RGB8)
	image.fill(Color(0.18, 0.35, 0.18))

	var put := func(world: Vector2, color: Color) -> void:
		var cell := progress.world_to_cell(world) - cell0
		for dx in range(2):
			for dy in range(2):
				var p := cell * 2 + Vector2i(dx, dy)
				if p.x >= 0 and p.y >= 0 and p.x < image.get_width() and p.y < image.get_height():
					image.set_pixelv(p, color)

	for cell in asphalt_cells:
		put.call(progress.cell_to_world(cell), Color(0.5, 0.5, 0.53))
	for cell in kerb_cells:
		put.call(progress.cell_to_world(cell), Color(0.62, 0.45, 0.45))

	for i in range(route.size()):
		put.call(route[i], Color(1, 0.9, 0.2).lerp(Color(1, 0.3, 0.1), float(i) / route.size()))

	for gate in gates:
		for j in range(40):
			put.call((gate[0] as Vector2).lerp(gate[1], j / 39.0), Color(1, 0.15, 0.15))

	for spawn in spawns:
		put.call(spawn, Color(0.2, 0.8, 1))

	image.save_png(ProjectSettings.globalize_path(PREVIEW_DIR + variant_name + ".png"))
