extends Control
class_name TireGauge

# ============================================================
# JAUGE D'USURE DES PNEUS
# ============================================================
#
# Pneu de course dessiné (gomme noire, jante à rayons) dont les
# marquages du flanc passent du vert au rouge avec l'usure ; « USURE »
# écrit sur le flanc, le pourcentage au-dessus. Les crampons
# s'effacent à mesure que le pneu s'use. Clignote quand il est temps de passer au stand.
# Masquée si l'usure n'est pas activée pour la voiture suivie.
# ============================================================

## Rayon du pneu (px).
const RADIUS := 58.0
const PERCENT_FONT_SIZE := 34
const LABEL_FONT_SIZE := 18
const CAPTION_FONT_SIZE := 18
const TREAD_BLOCKS := 24
const SPOKES := 8

const RUBBER := Color("#0d0d0d")
const TREAD := Color("#262626")
const RIM := Color("#a9a9a9")
const RIM_DARK := Color("#686868")
const SPOKE := Color("#f4f4f4")
const OUTLINE := Color.BLACK

# Couleur selon l'usure (0 = neuf, 1 = usé) : vert, jaune, orange, rouge.
const WEAR_COLORS := [
	[0.0, Color("#3ddc5a")],
	[0.4, Color("#c8e03c")],
	[0.6, Color("#ffc533")],
	[0.8, Color("#ff7a2e")],
	[1.0, Color("#ff3030")],
]
# Au-delà : clignotement (BOX).
const BLINK_FROM := 0.8

## Participant suivi (sa voiture est relue à chaque image).
var state: RaceParticipantState = null
## Nom affiché sous le pneu (plusieurs joueurs sur un même écran).
var caption: String = ""

var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caption_height := 0.0 if caption.is_empty() else CAPTION_FONT_SIZE + 8.0
	custom_minimum_size = Vector2(RADIUS * 2.0 + 24.0, RADIUS * 2.0 + PERCENT_FONT_SIZE + 14.0 + caption_height)


func _process(delta: float) -> void:
	_time += delta
	var car := _car()
	var shown := car != null and car.tire_wear_enabled

	if visible != shown:
		visible = shown

	if shown:
		queue_redraw()


static func wear_color(wear: float) -> Color:
	wear = clampf(wear, 0.0, 1.0)

	for i in range(1, WEAR_COLORS.size()):
		var upper: Array = WEAR_COLORS[i]

		if wear <= float(upper[0]):
			var lower: Array = WEAR_COLORS[i - 1]
			var t := (wear - float(lower[0])) / (float(upper[0]) - float(lower[0]))
			return (lower[1] as Color).lerp(upper[1], t)

	return WEAR_COLORS[-1][1]


## Nom du joueur : couleur de sa voiture (calculée une fois).
var _caption_tint := Color(0, 0, 0, 0)


func _caption_color(car: Car) -> Color:
	if _caption_tint.a == 0.0:
		_caption_tint = RaceParticipantHUD.car_display_color(car)

	return _caption_tint


func _car() -> Car:
	if state == null or not is_instance_valid(state.car):
		return null

	return state.car


func _draw() -> void:
	var car := _car()

	if car == null:
		return

	var wear := clampf(car.tire_wear, 0.0, 1.0)
	var color := wear_color(wear)
	var font := get_theme_font("font", "Label")
	var center := Vector2(size.x / 2.0, PERCENT_FONT_SIZE + 8.0 + RADIUS)

	# Clignotement quand il faut changer les pneus.
	var flash := wear >= BLINK_FROM and fmod(_time, 0.6) < 0.3

	# ---- Voie des stands : vitesse bridée ----
	if car.is_speed_limited():
		_text(font, "LIMITEUR", Vector2(size.x / 2.0, -6.0), CAPTION_FONT_SIZE, Color("#5ce1ff"))

	# ---- Pourcentage, au-dessus ----
	_text(font, "%d %%" % int(round(wear * 100.0)), Vector2(size.x / 2.0, PERCENT_FONT_SIZE), PERCENT_FONT_SIZE, color)

	# ---- Pneu (dessin de course : gomme noire, marquages de couleur
	# sur le flanc, jante à rayons) ----
	var mark := Color.WHITE if flash else color

	# Ombre, contour.
	draw_circle(center + Vector2(3, 4), RADIUS + 3.0, Color(0, 0, 0, 0.35))
	draw_circle(center, RADIUS + 3.0, OUTLINE)

	# Gomme : bande de roulement un peu plus claire, crampons qui
	# s'effacent avec l'usure.
	draw_circle(center, RADIUS, TREAD)
	draw_circle(center, RADIUS * 0.86, RUBBER)
	var block_color := TREAD.darkened(0.6)
	block_color.a = lerpf(1.0, 0.0, wear)

	for k in range(TREAD_BLOCKS):
		var dir := Vector2.from_angle(TAU * float(k) / TREAD_BLOCKS)
		draw_line(center + dir * RADIUS * 0.88, center + dir * (RADIUS - 1.0), block_color, 3.0, true)

	# Marquages du flanc : deux arcs de la couleur de l'usure.
	var arc_radius := RADIUS * 0.66
	var arc_width := RADIUS * 0.1
	draw_arc(center, arc_radius, deg_to_rad(122.0), deg_to_rad(238.0), 32, mark, arc_width, true)
	draw_arc(center, arc_radius, deg_to_rad(-58.0), deg_to_rad(58.0), 32, mark, arc_width, true)

	# « USURE » en haut du flanc.
	_text(font, "USURE", center + Vector2(0, -RADIUS * 0.56), LABEL_FONT_SIZE, mark, 0)

	# Jante : bord clair, fond gris, rayons blancs, moyeu.
	var rim_radius := RADIUS * 0.44
	draw_circle(center, rim_radius + 1.5, OUTLINE)
	draw_circle(center, rim_radius, RIM)
	draw_circle(center, rim_radius * 0.86, RIM_DARK)

	for k in range(SPOKES):
		var angle := TAU * float(k) / SPOKES + PI / SPOKES
		var half := PI / SPOKES * 0.62
		var inner := rim_radius * 0.3
		var outer := rim_radius * 0.78
		draw_colored_polygon(PackedVector2Array([
			center + Vector2.from_angle(angle - half * 0.7) * inner,
			center + Vector2.from_angle(angle - half) * outer,
			center + Vector2.from_angle(angle) * (outer + 1.5),
			center + Vector2.from_angle(angle + half) * outer,
			center + Vector2.from_angle(angle + half * 0.7) * inner,
		]), SPOKE)

	draw_circle(center, rim_radius * 0.24, SPOKE)
	draw_arc(center, rim_radius * 0.24, 0.0, TAU, 24, RIM_DARK, 1.5, true)

	# ---- Nom (écran partagé à plusieurs) ----
	if not caption.is_empty():
		_text(font, caption, center + Vector2(0, RADIUS + 6.0 + CAPTION_FONT_SIZE), CAPTION_FONT_SIZE, _caption_color(car))


## Texte centré horizontalement sur `pos` (ligne de base), avec contour.
func _text(font: Font, text: String, pos: Vector2, font_size: int, color: Color, outline: int = 6) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := Vector2(pos.x - width / 2.0, pos.y)

	if outline > 0:
		draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, OUTLINE)

	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
