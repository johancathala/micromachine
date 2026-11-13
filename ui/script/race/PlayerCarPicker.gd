extends PanelContainer
class_name PlayerCarPicker

# ============================================================
# Panneau de choix de voiture d'UN joueur, piloté avec SES
# commandes (clavier ou manette), en même temps que les autres :
#   gauche / droite : voiture
#   haut / bas      : couleur (accélérer / freiner)
#   frein à main    : prêt / pas prêt
# La logique (couleurs uniques, IA, départ) reste dans CarSelection.
# ============================================================

signal car_step_requested(picker: PlayerCarPicker, direction: int)
signal color_step_requested(picker: PlayerCarPicker, direction: int)
signal ready_toggled(picker: PlayerCarPicker)
signal remove_requested(picker: PlayerCarPicker)
signal nickname_changed(picker: PlayerCarPicker, nickname: String)

const INPUT_THRESHOLD := 0.5
const READY_COLOR := Color("#81c784")
const ACCENT_COLOR := Color("#ffd54f")

var participant_index := -1
var device_type := ""
var device_id := -1
var is_ready := false

var _previous := {"left": false, "right": false, "up": false, "down": false, "ready": false}

var _title: Label
var _nickname: LineEdit
var _car_label: Label
var _preview: TextureRect
var _color_label: Label
var _color_swatch: ColorRect
var _status: Label
var _bars: Array[ProgressBar] = []


func setup(index: int, player_number: int, participant: Dictionary, stats: Array) -> void:
	participant_index = index
	device_type = String(participant.get("device_type", ""))
	device_id = int(participant.get("device_id", -1))

	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	# En-tête : numéro, pseudo modifiable, bouton pour quitter.
	var header := HBoxContainer.new()
	box.add_child(header)

	_title = _label(header, "J%d" % player_number, 28, ACCENT_COLOR)

	_nickname = LineEdit.new()
	_nickname.text = String(participant.get("nickname", ""))
	_nickname.placeholder_text = "Pseudo"
	_nickname.max_length = 20
	_nickname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nickname.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nickname.add_theme_font_size_override("font_size", 24)
	_nickname.text_submitted.connect(func(text): _submit_nickname(text))
	_nickname.focus_exited.connect(func(): _submit_nickname(_nickname.text))
	header.add_child(_nickname)

	var remove := Button.new()
	remove.text = "✕"
	remove.tooltip_text = "Quitter la partie"
	remove.focus_mode = Control.FOCUS_NONE
	remove.pressed.connect(func(): remove_requested.emit(self))
	header.add_child(remove)

	_label(box, _controls_hint(), 18, Color(1, 1, 1, 0.7))

	_car_label = _label(box, "", 30, Color.WHITE)

	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.custom_minimum_size = Vector2(0, 60)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(_preview)

	var color_row := HBoxContainer.new()
	color_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(color_row)

	_color_swatch = ColorRect.new()
	_color_swatch.custom_minimum_size = Vector2(26, 26)
	color_row.add_child(_color_swatch)

	_color_label = _label(color_row, "", 24, Color.WHITE)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	box.add_child(grid)

	for stat in stats:
		var name_label := Label.new()
		name_label.text = stat["name"]
		name_label.add_theme_font_size_override("font_size", 18)
		grid.add_child(name_label)

		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(120, 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var background := StyleBoxFlat.new()
		background.bg_color = Color(0, 0, 0, 0.45)
		background.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", background)
		var fill := StyleBoxFlat.new()
		fill.bg_color = stat["color"]
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		grid.add_child(bar)
		_bars.append(bar)

	_status = _label(box, "", 26, Color.WHITE)


## Met à jour l'affichage (voiture, couleur, barres, état prêt).
func refresh(car: CarDefinition, color_data: Dictionary, stat_ratios: Array) -> void:
	_car_label.text = "◀  %s  ▶" % (car.display_name if car else "?")
	_preview.texture = car.preview_texture if car else null

	var color: Color = color_data.get("color", Color.WHITE)
	_preview.modulate = color
	_color_swatch.color = color
	_color_label.text = "  ▲  %s  ▼" % color_data.get("name", "?")

	for i in range(mini(_bars.size(), stat_ratios.size())):
		_bars[i].value = clampf(stat_ratios[i], 0.1, 1.0) * 100.0

	if is_ready:
		_status.text = "PRÊT !"
		_status.add_theme_color_override("font_color", READY_COLOR)
	else:
		_status.text = "%s = prêt" % _key_name("handbrake")
		_status.remove_theme_color_override("font_color")


func _submit_nickname(text: String) -> void:
	var clean := text.strip_edges()
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9 _-]{1,20}$")

	if regex.search(clean) == null:
		return

	nickname_changed.emit(self, clean)
	_nickname.release_focus()


func _process(_delta: float) -> void:
	# Saisie d'un pseudo en cours : les touches ne pilotent pas le panneau.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return

	var input := InputManager.get_player_input(device_type, device_id)

	var now := {
		"left": input.steering < -INPUT_THRESHOLD,
		"right": input.steering > INPUT_THRESHOLD,
		"up": input.throttle > INPUT_THRESHOLD,
		"down": input.brake > INPUT_THRESHOLD,
		"ready": input.handbrake
	}

	# Une action ne compte qu'au moment de l'appui.
	if _pressed(now, "ready"):
		ready_toggled.emit(self)

	if not is_ready:
		if _pressed(now, "left"):
			car_step_requested.emit(self, -1)
		if _pressed(now, "right"):
			car_step_requested.emit(self, 1)
		if _pressed(now, "up"):
			color_step_requested.emit(self, -1)
		if _pressed(now, "down"):
			color_step_requested.emit(self, 1)

	_previous = now


func _pressed(now: Dictionary, action: String) -> bool:
	return now[action] and not _previous[action]


func _controls_hint() -> String:
	return "%s %s voiture · %s %s couleur" % [
		_key_name("left"), _key_name("right"),
		_key_name("accelerate"), _key_name("brake")
	]


func _key_name(action: String) -> String:
	if device_type == "gamepad" and action in ["left", "right"]:
		return "Stick"

	return InputManager.get_binding_display_name(device_type, device_id, action)


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
