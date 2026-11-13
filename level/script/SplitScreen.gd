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

		_viewports.append(viewport)
		_cameras.append(camera)
		_labels.append(label)

	# Les cellules vides (ex. 3 joueurs en 2x2) restent noires.
	for i in range(layout.x * layout.y - player_count):
		var filler := Control.new()
		filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
		filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(filler)

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


func get_camera_for(car: Car) -> RaceCamera:
	for camera in _cameras:
		if camera.target_car == car:
			return camera

	return null


func _process(_delta: float) -> void:
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

		if state.finished:
			text += "   ARRIVÉ"

		_labels[i].text = text


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
