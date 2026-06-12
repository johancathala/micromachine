extends Control
class_name PopupMessage

signal closed

# ───────── Enums publics (à réutiliser côté UIManager) ─────────
enum PositionMode { CENTER, BOTTOM }
enum TextMode { INSTANT, TYPEWRITER }

# ───────── Noeuds ─────────
@onready var panel: Panel = $Panel
@onready var vbox: VBoxContainer = $Panel/VBoxContainer
@onready var title_label: Label = $Panel/VBoxContainer/Title
@onready var margin: MarginContainer = $Panel/VBoxContainer/MarginContainer
@onready var text_label: Label = $Panel/VBoxContainer/MarginContainer/Text

# ───────── Réglages responsive & ratios par défaut ─────────
@export_range(10, 96, 1) var min_title_font: int = 20
@export_range(10, 96, 1) var base_title_font: int = 26
@export_range(10, 96, 1) var min_text_font: int = 16
@export_range(10, 96, 1) var base_text_font: int = 28
@export var responsive_ref_width: int = 1920

# Centre
@export_range(0.2, 1.0, 0.05) var center_width_ratio: float = 0.60
@export_range(0.1, 1.0, 0.05) var center_height_ratio: float = 0.25
@export_range(0.00, 0.30, 0.01) var center_padding_ratio: float = 0.08

# Bas
@export_range(0.2, 1.0, 0.05) var bottom_width_ratio: float = 0.98
@export_range(0.10, 0.50, 0.01) var bottom_height_ratio: float = 0.22
@export var bottom_margin_left_px: int = 32
@export var bottom_margin_right_px: int = 32
@export var bottom_margin_bottom_px: int = 28
@export var bottom_margin_top_px: int = 20
@export_range(0.00, 0.30, 0.01) var bottom_padding_x_ratio: float = 0.06
@export_range(0.00, 0.30, 0.01) var bottom_padding_y_ratio: float = 0.10

# ───────── Typewriter ─────────
const TypewriterScene := preload("res://ui/script/typewriter.gd")
var _tw: Typewriter

# ───────── État interne ─────────
var _current_title: String = ""
var _current_text: String = ""
var _current_pos_mode: int = PositionMode.CENTER
var _current_text_mode: int = TextMode.TYPEWRITER
var _is_typing: bool = false
var _show_id: int = 0

func _ready() -> void:
	_tw = TypewriterScene.new()
	add_child(_tw)

	visible = false
	# Important : on gère le clavier nous-mêmes, on ne veut pas que la popup "vole" le focus clavier
	focus_mode = Control.FOCUS_NONE   
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	#set_process_unhandled_input(true)

	# S'assure que la fonction _on_resized est appelée quand la fenêtre change
	self.resized.connect(_on_resized)

# ───────── API principale ─────────
# L'UIManager appellera uniquement cette méthode.
func show_message(title: String, message: String, pos_mode: int, text_mode: int) -> void:
	_show_id += 1
	var my_id: int = _show_id

	_current_title = title
	_current_text = message
	_current_pos_mode = pos_mode
	_current_text_mode = text_mode

	# Titre on/off
	var has_title: bool = title != "" and title.length() > 0
	title_label.visible = has_title
	if has_title:
		title_label.text = title

	# Mise en page initiale (taille + position + padding + fonts)
	_layout_popup()

	# Contenu
	text_label.text = ""
	visible = true

	# Affichage du texte
	if text_mode == TextMode.INSTANT:
		_is_typing = false
		text_label.text = message
	else:
		_is_typing = true
		_tw.cancel()
		await _tw.play(text_label, message, 42.0, 80, true)
		if my_id != _show_id:
			return
		_is_typing = false
		
func hide_message() -> void:
	visible = false
	emit_signal("closed")

# ───────── Interaction : 1er appui = skip, 2e appui = fermer ─────────
func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_handle_press()
		accept_event()
		return

	if event is InputEventKey:
		var e: InputEventKey = event as InputEventKey
		if e.pressed and not e.echo and e.keycode == Key.KEY_SPACE:
			_handle_press()
			accept_event()
			return

func _handle_press() -> void:
	if _is_typing:
		_tw.cancel()
		text_label.text = _current_text
		_is_typing = false
	else:
		hide_message()

# ───────── Layout & fonts (placement interne) ─────────
func _on_resized() -> void:
	if visible:
		_layout_popup()

func _layout_popup() -> void:
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var panel_size: Vector2 = Vector2.ZERO

	# 1) Dimensions et position selon le mode
	if _current_pos_mode == PositionMode.CENTER:
		var target_w: float = screen.x * center_width_ratio
		var target_h: float = screen.y * center_height_ratio
		panel_size = Vector2(target_w, target_h)

		# Panel centré (anchors 0, offsets en pixels)
		panel.anchor_left = 0.0
		panel.anchor_top = 0.0
		panel.anchor_right = 0.0
		panel.anchor_bottom = 0.0
		panel.offset_left = (screen.x - target_w) * 0.5
		panel.offset_top = (screen.y - target_h) * 0.5
		panel.offset_right = panel.offset_left + target_w
		panel.offset_bottom = panel.offset_top + target_h
		panel.custom_minimum_size = panel_size

		# Padding interne
		var pad_x: int = int(target_w * center_padding_ratio)
		var pad_y: int = int(target_h * center_padding_ratio)
		_set_padding(pad_x, pad_x, pad_y, pad_y)

	elif _current_pos_mode == PositionMode.BOTTOM:
		# Zone utile en bas avec marges externes
		var usable_w: float = max(0.0, screen.x - float(bottom_margin_left_px + bottom_margin_right_px))
		var target_w_b: float = min(usable_w, screen.x * bottom_width_ratio)
		var target_h_b: float = screen.y * bottom_height_ratio

		# Clamp sur la hauteur si marges top/bottom la limitent
		var max_h: float = max(0.0, screen.y - float(bottom_margin_bottom_px + bottom_margin_top_px))
		if target_h_b > max_h:
			target_h_b = max_h

		panel_size = Vector2(target_w_b, target_h_b)

		panel.anchor_left = 0.0
		panel.anchor_top = 0.0
		panel.anchor_right = 0.0
		panel.anchor_bottom = 0.0
		panel.offset_left = float(bottom_margin_left_px)
		panel.offset_top = screen.y - float(bottom_margin_bottom_px) - target_h_b
		panel.offset_right = panel.offset_left + target_w_b
		panel.offset_bottom = panel.offset_top + target_h_b
		panel.custom_minimum_size = panel_size

		# Padding interne (légèrement asymétrique : plus d'air en Y)
		var pad_x_b: int = int(target_w_b * bottom_padding_x_ratio)
		var pad_y_b: int = int(target_h_b * bottom_padding_y_ratio)
		_set_padding(pad_x_b, pad_x_b, pad_y_b, pad_y_b)
	else:
		push_warning("PopupMessage: PositionMode inconnu: " + str(_current_pos_mode))

	# 2) Fonts responsives (titre + texte)
	_apply_responsive_fonts(screen.x)

	# 3) Petit recalcul layout pour l'autowrap
	#text_label.queue_sort()

func _apply_responsive_fonts(screen_w: float) -> void:
	var scale_factor: float = float(clamp(screen_w / float(responsive_ref_width), 0.6, 1.6))

	var ttl_size: int = max(min_title_font, int(float(base_title_font) * scale_factor))
	var txt_size: int = max(min_text_font, int(float(base_text_font) * scale_factor))

	if title_label.get_theme_font_size("font_size") != ttl_size:
		title_label.add_theme_font_size_override("font_size", ttl_size)
	if text_label.get_theme_font_size("font_size") != txt_size:
		text_label.add_theme_font_size_override("font_size", txt_size)

func _set_padding(pad_left: int, pad_right: int, pad_top: int, pad_bottom: int) -> void:
	margin.add_theme_constant_override("margin_left", pad_left)
	margin.add_theme_constant_override("margin_right", pad_right)
	margin.add_theme_constant_override("margin_top", pad_top)
	margin.add_theme_constant_override("margin_bottom", pad_bottom)
