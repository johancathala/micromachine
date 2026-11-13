extends SceneTree

# ============================================================
# Construit level/track/TrackAles.tscn à partir des données de
# tools/track/make_ales_masks.py (level/track/ales/build/).
#
# Usage (depuis la racine du projet) :
#   python3 -I tools/track/make_ales_masks.py .
#   godot --headless --path . -s tools/track/build_ales_track.gd
#
# Même organisation que Track01 : couches de tuiles (herbe, gravier,
# asphalte, vibreurs, pneus), Sections, SpawnPoints,
# RaceStartLightsMap, PitStop.
# ============================================================

const BUILD_DIR := "res://level/track/ales/build/"
const OUTPUT := "res://level/track/TrackAles.tscn"

# Toutes les tuiles et leurs orientations sont reprises de Track01
# (mêmes jeux de tuiles, mêmes assemblages) : rien n'est inventé.

const FLIP_H := 4096
const FLIP_V := 8192
const TRANSPOSE := 16384

# Asphalte : tuile de piste de Track01 (source 17).
const ASPHALT_RACING := Vector2i(53, 61)
# Bord de piste (Chaussée 45,2 : bordure claire sur le côté gauche),
# orienté vers l'extérieur comme dans Track01.
const EDGE_TILE := Vector2i(45, 2)
const EDGE_WEST := 0
const EDGE_EAST := FLIP_H | FLIP_V
const EDGE_NORTH := TRANSPOSE | FLIP_H
const EDGE_SOUTH := TRANSPOSE | FLIP_V

# Vibreurs : bandes de la tuile de piste (source 17), colonnes 49
# (vibreur gauche) et 57 (vibreur droit), lignes 58 à 67 enchaînées.
const KERB_LEFT_COLUMN := 49
const KERB_RIGHT_COLUMN := 57
const KERB_FIRST_ROW := 58
const KERB_ROWS := 10

const GRASS_TILES := [Vector2i(53, 2), Vector2i(52, 2)]
const GRASS_ALTERNATIVES := [FLIP_H, 0, FLIP_H, 0, TRANSPOSE, TRANSPOSE | FLIP_V]

# Gravier : bloc 34-40 x 34-39 de la tuile de piste (source 17).
const GRAVEL_COLUMNS := [34, 40]
const GRAVEL_ROWS := [34, 39]

# Barrière : bloc de pneus 2x2 (source 1, tuiles de 16 px).
const TIRE_BLOCK := [
	[Vector2i(0, 0), Vector2i(3, 4)], [Vector2i(1, 0), Vector2i(4, 4)],
	[Vector2i(0, 1), Vector2i(3, 5)], [Vector2i(1, 1), Vector2i(4, 5)]
]

# Couleur moyenne des tuiles d'herbe.
const GRASS_BACKGROUND := Color8(71, 151, 87)

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 2002  # ouverture du circuit : rendu reproductible

	var data: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(BUILD_DIR + "track.json")
	)

	var origin := Vector2i(int(data["grid_origin"][0]), int(data["grid_origin"][1]))

	var root := Node2D.new()
	root.name = "TrackAles"

	# Fond couleur herbe très étendu : évite le vide autour de la zone
	# de tuiles quand la caméra partagée dézoome.
	var background := Polygon2D.new()
	background.name = "Background"
	background.z_index = -10
	background.color = GRASS_BACKGROUND
	var far := 200000.0
	background.polygon = PackedVector2Array([
		Vector2(-far, -far), Vector2(far, -far), Vector2(far, far), Vector2(-far, far)
	])
	_add(root, background, root)

	var map := Node2D.new()
	map.name = "Map"
	_add(root, map, root)

	var grass := _layer(map, root, "res://level/sprite/tilemap/_4_herbe.tscn", "-4_Herbe")
	var gravel := _layer(map, root, "res://level/sprite/tilemap/_3_gravel.tscn", "-3_Gravel")
	var asphalt := _layer(map, root, "res://level/sprite/tilemap/_2_asphalte.tscn", "-2_asphalte")
	var kerbs := _layer(map, root, "res://level/sprite/tilemap/_1_vibreur.tscn", "-1_vibreur")
	var tires := _layer(map, root, "res://level/sprite/tilemap/pneu_sac.tscn", "0_Pneu_sac")

	var asphalt_img := _mask("asphalt")
	var gravel_img := _mask("gravel")
	var kerb_img := _mask("kerb")
	var barrier_img := _mask("barrier")

	var grass_source := grass.tile_set.get_source_id(0)
	var tire_source := tires.tile_set.get_source_id(0)
	var size := asphalt_img.get_size()

	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y) + origin

			# Herbe partout (variantes et orientations de Track01).
			grass.set_cell(
				cell, grass_source,
				GRASS_TILES[_rng.randi() % GRASS_TILES.size()],
				GRASS_ALTERNATIVES[_rng.randi() % GRASS_ALTERNATIVES.size()]
			)

			var outward := _outward(asphalt_img, x, y)

			if _on(asphalt_img, x, y):
				if outward != Vector2i.ZERO:
					asphalt.set_cell(cell, 0, EDGE_TILE, _edge_alternative(outward))
				else:
					# Comme sur la piste de Track01 : tuile de piste uniquement
					# (les variantes « Chaussée », d'une autre teinte, y
					# servent aux zones annexes).
					asphalt.set_cell(cell, 17, ASPHALT_RACING)
			elif _on(gravel_img, x, y):
				gravel.set_cell(cell, 17, Vector2i(
					_rng.randi_range(GRAVEL_COLUMNS[0], GRAVEL_COLUMNS[1]),
					_rng.randi_range(GRAVEL_ROWS[0], GRAVEL_ROWS[1])
				))

			if _on(kerb_img, x, y) and outward != Vector2i.ZERO:
				_set_kerb(kerbs, cell, outward)

			# Barrière : bloc de pneus 2x2 (tuiles de 16 px) par case.
			if _on(barrier_img, x, y):
				for part in TIRE_BLOCK:
					tires.set_cell(cell * 2 + part[0], tire_source, part[1])

	# ---- Sections ----
	var sections := Node2D.new()
	sections.name = "Sections"
	_add(root, sections, root)

	var section_script := load("res://level/script/RaceSection.gd")

	for section_data in data["sections"]:
		var center := _vec(section_data["center"])
		var area := Area2D.new()
		area.name = "Section%02d" % int(section_data["id"])
		area.set_script(section_script)
		area.set("section_id", int(section_data["id"]))
		area.collision_mask = 2
		area.position = center
		_add(sections, area, root)

		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var segment := SegmentShape2D.new()
		segment.a = _vec(section_data["a"]) - center
		segment.b = _vec(section_data["b"]) - center
		shape.shape = segment
		_add(area, shape, root)

		var respawn := Marker2D.new()
		respawn.name = "RespawnPoint"
		respawn.rotation = float(section_data["heading"])
		_add(area, respawn, root)

	# ---- Grille de départ ----
	var spawns := Node2D.new()
	spawns.name = "SpawnPoints"
	_add(root, spawns, root)

	var slot := 1

	for spawn_data in data["spawns"]:
		var marker := Marker2D.new()
		marker.name = "Spawn%02d" % slot
		marker.position = _vec(spawn_data["pos"])
		marker.rotation = float(spawn_data["heading"])
		_add(spawns, marker, root)
		slot += 1

	# ---- Feux de départ (portique au-dessus de la ligne) ----
	var lights := (load("res://level/scene/RaceStartLightsMap.tscn") as PackedScene).instantiate() as Node2D
	lights.name = "RaceStartLightsMap"
	lights.z_index = 3
	lights.position = _vec(data["start"]["pos"]) + Vector2(-145, -60)
	_add(root, lights, root)

	# ---- Stand ----
	var pit := Area2D.new()
	pit.name = "PitStop"
	pit.set_script(load("res://level/script/PitStop.gd"))
	pit.position = _vec(data["pit_zone"]["center"])
	pit.rotation = float(data["pit_zone"]["heading"])
	_add(root, pit, root)

	var pit_shape := CollisionShape2D.new()
	pit_shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = _vec(data["pit_zone"]["size"])
	pit_shape.shape = rect
	_add(pit, pit_shape, root)

	var packed := PackedScene.new()
	var error := packed.pack(root)

	if error != OK:
		push_error("Échec de l'empaquetage : %d" % error)
		quit(1)
		return

	error = ResourceSaver.save(packed, OUTPUT)
	print("TrackAles : ", "enregistré" if error == OK else "erreur %d" % error, " -> ", OUTPUT)
	print("  asphalte=%d gravier=%d vibreurs=%d pneus=%d herbe=%d" % [
		asphalt.get_used_cells().size(), gravel.get_used_cells().size(),
		kerbs.get_used_cells().size(), tires.get_used_cells().size(),
		grass.get_used_cells().size()
	])
	root.free()
	quit()


func _on(image: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return false

	return image.get_pixel(x, y).r > 0.5


## Direction vers l'extérieur de la piste pour une case de bord
## (axe dominant), ou ZERO si la case n'est pas un bord.
func _outward(image: Image, x: int, y: int) -> Vector2i:
	if not _on(image, x, y):
		return Vector2i.ZERO

	var sum := Vector2i.ZERO

	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dy != 0) and not _on(image, x + dx, y + dy):
				sum += Vector2i(dx, dy)

	if sum == Vector2i.ZERO:
		return Vector2i.ZERO

	if absi(sum.x) >= absi(sum.y):
		return Vector2i(signi(sum.x), 0)

	return Vector2i(0, signi(sum.y))


func _edge_alternative(outward: Vector2i) -> int:
	match outward:
		Vector2i.LEFT:
			return EDGE_WEST
		Vector2i.RIGHT:
			return EDGE_EAST
		Vector2i.UP:
			return EDGE_NORTH
		_:
			return EDGE_SOUTH


## Bande de vibreur de Track01, orientée selon le bord : la bande
## verticale est tournée (transposée) pour les bords horizontaux, et
## les lignes s'enchaînent le long du bord.
func _set_kerb(layer: TileMapLayer, cell: Vector2i, outward: Vector2i) -> void:
	var along := cell.y if outward.x != 0 else cell.x
	var row := KERB_FIRST_ROW + posmod(along, KERB_ROWS)

	match outward:
		Vector2i.LEFT:
			layer.set_cell(cell, 17, Vector2i(KERB_LEFT_COLUMN, row))
		Vector2i.RIGHT:
			layer.set_cell(cell, 17, Vector2i(KERB_RIGHT_COLUMN, row))
		Vector2i.UP:
			layer.set_cell(cell, 17, Vector2i(KERB_LEFT_COLUMN, row), TRANSPOSE)
		_:
			layer.set_cell(cell, 17, Vector2i(KERB_RIGHT_COLUMN, row), TRANSPOSE)


func _layer(parent: Node, owner_node: Node, scene_path: String, layer_name: String) -> TileMapLayer:
	var layer := (load(scene_path) as PackedScene).instantiate() as TileMapLayer
	layer.name = layer_name
	layer.clear()  # la scène source contient les tuiles de Track01
	_add(parent, layer, owner_node)
	return layer


func _mask(mask_name: String) -> Image:
	var image := Image.load_from_file(
		ProjectSettings.globalize_path(BUILD_DIR + mask_name + ".png")
	)
	image.convert(Image.FORMAT_L8)
	return image


func _add(parent: Node, child: Node, owner_node: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node


func _vec(value: Variant) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
