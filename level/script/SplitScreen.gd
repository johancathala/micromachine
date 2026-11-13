extends Control
class_name SplitScreen

# ============================================================
# ÉCRAN SPLITTÉ
# ============================================================
#
# Une vue (SubViewport) par joueur humain, toutes rendues à partir
# du même monde : RaceWorld est déplacé dans la première vue, les
# suivantes partagent son World2D (même physique, mêmes voitures).
#
# Chaque vue a sa propre caméra (RaceCamera en mode « voiture cible »)
# et un bandeau : joueur, position, tour.
# ============================================================

# Colonnes x lignes selon le nombre de joueurs.
const LAYOUTS := {
	1: Vector2i(1, 1),
	2: Vector2i(2, 1),
	3: Vector2i(2, 2),
	4: Vector2i(2, 2),
	5: Vector2i(3, 2),
	6: Vector2i(3, 2),
	7: Vector2i(4, 2),
	8: Vector2i(4, 2)
}

const SEPARATOR_SIZE := 6
const SEPARATOR_COLOR := Color(0.05, 0.05, 0.05)

const PLACE := {
	1: "1er", 2: "2e", 3: "3e", 4: "4e",
	5: "5e", 6: "6e", 7: "7e", 8: "8e"
}

var race_controller: RaceController = null

var _viewports: Array[SubViewport] = []
var _cameras: Array[RaceCamera] = []
var _labels: Array[Label] = []
var _states: Array[RaceParticipantState] = []

# Message temporaire (ex. « BOX, BOX ») et statut (ex. QTE du stand)
# affichés dans la vue de chaque joueur.
var _callouts: Array[Label] = []
var _callout_ids: Array[int] = []
var _status_labels: Array[RichTextLabel] = []

# Position du joueur, en haut à droite de sa vue (seule info en haut
# de l'écran, pour ne pas gêner la vue).
var _position_labels: Array[Label] = []

# Minimap : cases vides de la grille (ex. 3 joueurs en 2x2).
var _minimap_viewports: Array[SubViewport] = []
var _minimap_cameras: Array[Camera2D] = []
var _minimap_overlays: Array[MinimapOverlay] = []

# Marge autour du circuit sur la minimap.
const MINIMAP_MARGIN := 1.08

# Taille des minimaps au dernier cadrage (recadrage si elle change).
var _minimap_framed_sizes: Array[Vector2i] = []

# Le circuit ne bouge pas : la minimap n'est dessinée que pendant
# quelques images après chaque cadrage (le temps que les tuiles soient
# prêtes), puis figée. Seules les pastilles des joueurs sont mises à
# jour. La redessiner à chaque image coûtait ~75 % des performances
# (tout le circuit, ~450 000 tuiles sur Alès).
const MINIMAP_RENDER_FRAMES := 10
var _minimap_render_left: Array[int] = []


## Construit les vues et y place le monde de course.
## À appeler AVANT de charger le circuit et les voitures.
func build(race_world: RaceWorld, player_count: int) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var background := ColorRect.new()
	background.color = SEPARATOR_COLOR
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var layout: Vector2i = LAYOUTS.get(
		clampi(player_count, 1, 8),
		Vector2i(4, 2)
	)

	var grid := GridContainer.new()
	grid.columns = layout.x
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override("h_separation", SEPARATOR_SIZE)
	grid.add_theme_constant_override("v_separation", SEPARATOR_SIZE)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grid)

	for i in range(player_count):
		# Cellule : la vue, avec le bandeau du joueur par-dessus.
		var cell := Control.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.clip_contents = true
		grid.add_child(cell)

		var container := SubViewportContainer.new()
		container.stretch = true
		container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(container)

		var viewport := SubViewport.new()
		viewport.name = "PlayerView%d" % (i + 1)
		viewport.handle_input_locally = false
		# Chaque joueur entend les sons autour de sa voiture.
		viewport.audio_listener_enable_2d = true
		container.add_child(viewport)

		if i == 0:
			# Le monde (circuit, voitures, physique) vit dans la 1re vue.
			race_world.get_parent().remove_child(race_world)
			viewport.add_child(race_world)
		else:
			viewport.world_2d = _viewports[0].world_2d

		var camera := RaceCamera.new()
		camera.name = "PlayerCamera"
		camera.use_target_car = true
		viewport.add_child(camera)

		var label := _create_player_label()
		cell.add_child(label)

		var callout := _create_callout()
		cell.add_child(callout)

		var status := _create_status_label()
		cell.add_child(status)

		var position_label := _create_position_label()
		cell.add_child(position_label)

		_viewports.append(viewport)
		_cameras.append(camera)
		_labels.append(label)
		_callouts.append(callout)
		_callout_ids.append(0)
		_status_labels.append(status)
		_position_labels.append(position_label)

	# Cases vides (ex. 3 joueurs en 2x2) : minimap du circuit, vue de
	# très loin. Rien à 2, 4, 6 ou 8 joueurs (pas de case libre).
	for i in range(layout.x * layout.y - player_count):
		_build_minimap_cell(grid)

	# La caméra partagée n'est plus utilisée.
	var shared_camera := race_world.race_camera as RaceCamera

	if shared_camera != null:
		shared_camera.follow_cars = false
		shared_camera.enabled = false


## Associe chaque vue à un joueur humain (une fois les voitures créées).
func attach_players(controller: RaceController) -> void:
	race_controller = controller
	_states.clear()

	for state in controller.get_participant_states():
		if not state.is_ai:
			_states.append(state)

	_states.sort_custom(
		func(a, b): return a.participant_id < b.participant_id
	)

	for i in range(_cameras.size()):
		if i >= _states.size():
			break

		var camera := _cameras[i]
		camera.target_car = _states[i].car
		camera.race_controller = controller
		camera.enabled = true
		camera.make_current()

	for overlay in _minimap_overlays:
		overlay.states = _states

	_frame_minimaps()


func has_minimap() -> bool:
	return not _minimap_viewports.is_empty()


# ------------------------------------------------------------
# Messages dans la vue d'un joueur
# ------------------------------------------------------------

## Message temporaire, en grand, dans la vue du joueur.
func show_player_message(
	state: RaceParticipantState,
	text: String,
	duration: float
) -> void:

	var index := _states.find(state)

	if index < 0:
		return

	_callout_ids[index] += 1
	var id := _callout_ids[index]

	_callouts[index].text = text
	_callouts[index].show()

	await get_tree().create_timer(duration, false).timeout

	if is_instance_valid(self) and _callout_ids[index] == id:
		_callouts[index].hide()


## Texte permanent dans la vue du joueur ("" pour l'effacer).
func set_player_status(state: RaceParticipantState, text: String) -> void:
	var index := _states.find(state)

	if index < 0:
		return

	_status_labels[index].text = "[center]%s[/center]" % text
	_status_labels[index].visible = not text.is_empty()


# ------------------------------------------------------------
# Minimap
# ------------------------------------------------------------

func _build_minimap_cell(grid: GridContainer) -> void:
	var cell := Control.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.clip_contents = true
	grid.add_child(cell)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(container)

	var viewport := SubViewport.new()
	viewport.name = "Minimap"
	viewport.handle_input_locally = false
	viewport.audio_listener_enable_2d = false
	viewport.world_2d = _viewports[0].world_2d
	container.add_child(viewport)

	var camera := Camera2D.new()
	camera.name = "MinimapCamera"
	camera.ignore_rotation = false
	viewport.add_child(camera)
	camera.make_current()

	var overlay := MinimapOverlay.new()
	overlay.viewport = viewport
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(overlay)

	_minimap_viewports.append(viewport)
	_minimap_cameras.append(camera)
	_minimap_overlays.append(overlay)
	_minimap_framed_sizes.append(Vector2i.ZERO)
	_minimap_render_left.append(0)


## Cadre tout le circuit dans chaque minimap. Un circuit en hauteur
## dans une case en largeur est tourné de 90° pour être plus grand.
func _frame_minimaps() -> void:
	var bounds := _get_track_bounds()

	if bounds.size == Vector2.ZERO:
		return

	for i in range(_minimap_cameras.size()):
		var camera := _minimap_cameras[i]
		var view_size := Vector2(_minimap_viewports[i].size)

		if view_size.x <= 16.0 or view_size.y <= 16.0:
			continue

		var track_size := bounds.size * MINIMAP_MARGIN
		var rotate := (
			(track_size.y > track_size.x) != (view_size.y > view_size.x)
		)

		if rotate:
			track_size = Vector2(track_size.y, track_size.x)
			camera.rotation = -PI / 2.0
		else:
			camera.rotation = 0.0

		camera.position = bounds.get_center()
		camera.zoom = Vector2.ONE * minf(
			view_size.x / track_size.x,
			view_size.y / track_size.y
		)

		_minimap_viewports[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_minimap_render_left[i] = MINIMAP_RENDER_FRAMES


## Emprise du circuit : chemins de la course si disponibles,
## sinon les portes de section.
func _get_track_bounds() -> Rect2:
	var points := PackedVector2Array()

	if race_controller != null and race_controller.track_progress != null:
		var progress := race_controller.track_progress

		for section_id in range(progress.section_count):
			points.append_array(progress.get_path(section_id))
	elif race_controller != null:
		for position in race_controller._section_positions.values():
			points.append(position)

	if points.is_empty():
		return Rect2()

	var bounds := Rect2(points[0], Vector2.ZERO)

	for point in points:
		bounds = bounds.expand(point)

	return bounds


func get_camera_for(car: Car) -> RaceCamera:
	for camera in _cameras:
		if camera.target_car == car:
			return camera

	return null


func _process(_delta: float) -> void:
	# Les cases n'ont leur taille réelle qu'après la mise en page :
	# on (re)cadre la minimap dès que sa taille change.
	for i in range(_minimap_viewports.size()):
		var size := _minimap_viewports[i].size

		if size.x > 16 and size.y > 16 and size != _minimap_framed_sizes[i]:
			_minimap_framed_sizes[i] = size
			_frame_minimaps()

		# Quelques images de rendu après le cadrage, puis image figée.
		if _minimap_render_left[i] > 0:
			_minimap_render_left[i] -= 1

			if _minimap_render_left[i] == 0:
				_minimap_viewports[i].render_target_update_mode = (
					SubViewport.UPDATE_DISABLED
				)
	for i in range(mini(_labels.size(), _states.size())):
		var state := _states[i]

		var text := "J%d  %s" % [i + 1, state.nickname]

		if state.race_position > 0:
			text += "   %s" % PLACE.get(state.race_position, "")

		if race_controller != null:
			text += "   Tour %d/%d" % [
				state.current_lap,
				race_controller.get_lap_count()
			]

		if race_controller != null and race_controller.pit_stops != null:
			text += "   Pneus %d %%" % int(state.car.tire_wear * 100.0)

		if state.finished:
			text += "   ARRIVÉ"

		_labels[i].text = text

		if state.race_position > 0:
			_position_labels[i].text = "%s / %d" % [
				PLACE.get(state.race_position, str(state.race_position)),
				race_controller.get_participant_count() if race_controller else _states.size()
			]


func _create_position_label() -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.offset_right = -16.0
	label.offset_top = 8.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	return label


func _create_callout() -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.offset_top = 40.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_color", Color("#ffd54f"))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 12)
	label.hide()
	return label


## QTE du stand (texte riche : flèche à faire en gras et en couleur).
func _create_status_label() -> RichTextLabel:
	var label := RaceHUD.create_qte_label(34)
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_bottom = -60.0
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return label


func _create_player_label() -> Label:
	# En bas à gauche de la vue : le haut de l'écran est occupé
	# par le HUD global (temps, classement).
	var label := Label.new()
	label.anchor_left = 0.0
	label.anchor_right = 0.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 16.0
	label.offset_bottom = -12.0
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	return label
