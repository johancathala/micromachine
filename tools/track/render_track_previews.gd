extends SceneTree

# ============================================================
# Aperçus des circuits pour l'écran de préparation.
#
#   godot --path . -s tools/track/render_track_previews.gd
#   (avec fenêtre : le rendu ne fonctionne pas en --headless)
#
# Même procédé que la minimap de l'écran splitté : le circuit est
# chargé dans une SubViewport et cadré en entier (tourné de 90° s'il
# remplit mieux l'image). Le parcours de course (chemin le long de la
# route entre les sections) et la ligne de départ sont dessinés
# par-dessus : indispensable pour distinguer les variantes qui
# partagent la même carte.
# Sortie : level/sprite/minia/track_<id>.png
# ============================================================

const OUTPUT := "res://level/sprite/minia/track_%d.png"
const SIZE := Vector2i(600, 970)
const MARGIN := 1.06
const RENDER_FRAMES := 12
const ROUTE_COLOR := Color(1.0, 0.82, 0.2, 0.9)
const START_COLOR := Color(1, 1, 1, 0.95)

var _tracks: Array = []
var _index := -1
var _frames := 0
var _viewport: SubViewport = null


func _initialize() -> void:
	_tracks = TrackCatalog.get_tracks()


func _process(_delta: float) -> bool:
	if _viewport == null:
		_index += 1

		if _index >= _tracks.size():
			return true

		_start(_tracks[_index])
		return false

	_frames += 1

	if _frames < RENDER_FRAMES:
		return false

	var track: Dictionary = _tracks[_index]
	var image := _viewport.get_texture().get_image()
	var path := OUTPUT % int(track["id"])
	image.save_png(ProjectSettings.globalize_path(path))
	print("aperçu : %-24s -> %s" % [track["name"], path])

	_viewport.queue_free()
	_viewport = null
	return false


func _start(track: Dictionary) -> void:
	_frames = 0

	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	root.add_child(_viewport)

	var scene := (load(String(track["scene"])) as PackedScene).instantiate() as Node2D
	_viewport.add_child(scene)

	# Parcours : mêmes calculs que pendant la course.
	var gates: Dictionary = {}
	var sections := scene.get_node_or_null("Sections")

	if sections != null:
		for section in sections.get_children():
			for child in section.get_children():
				var shape := child as CollisionShape2D

				if shape != null and shape.shape is SegmentShape2D:
					var segment := shape.shape as SegmentShape2D
					gates[section.section_id] = [shape.to_global(segment.a), shape.to_global(segment.b)]

	var progress := TrackProgress.new()
	var route := PackedVector2Array()

	if progress.build(scene, gates):
		for k in range(progress.section_count):
			route.append_array(progress.get_path(k))
	else:
		push_warning("%s : %s" % [track["name"], progress.last_error])

	var bounds := Rect2()

	for i in range(route.size()):
		bounds = Rect2(route[0], Vector2.ZERO) if i == 0 else bounds.expand(route[i])

	if bounds.size == Vector2.ZERO:
		return

	# Cadrage (comme la minimap) : rotation si le circuit rentre mieux.
	var camera := Camera2D.new()
	camera.ignore_rotation = false
	_viewport.add_child(camera)
	camera.make_current()

	var track_size := bounds.size * MARGIN
	var view := Vector2(SIZE)

	if (track_size.y > track_size.x) != (view.y > view.x):
		track_size = Vector2(track_size.y, track_size.x)
		camera.rotation = -PI / 2.0

	camera.position = bounds.get_center()
	var zoom := minf(view.x / track_size.x, view.y / track_size.y)
	camera.zoom = Vector2.ONE * zoom

	# Parcours et ligne de départ, épaisseur constante à l'écran.
	var line := Line2D.new()
	line.points = route
	line.closed = true
	line.width = 7.0 / zoom
	line.default_color = ROUTE_COLOR
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.z_index = 50
	scene.add_child(line)

	# Ligne de départ : court trait perpendiculaire au parcours (les
	# portes peuvent couvrir plusieurs routes).
	if route.size() > 4:
		var direction := (route[4] - route[0]).normalized()
		var normal := direction.orthogonal() * (22.0 / zoom)
		var start := Line2D.new()
		start.points = PackedVector2Array([route[0] + normal, route[0] - normal])
		start.width = 9.0 / zoom
		start.default_color = START_COLOR
		start.z_index = 51
		scene.add_child(start)
