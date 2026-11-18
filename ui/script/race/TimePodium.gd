extends Control
class_name TimePodium

# ============================================================
# PODIUM DES MEILLEURS TEMPS (contre-la-montre, choix du circuit)
# ============================================================
#
# Trois marches (2e à gauche, 1er au centre, 3e à droite) aux couleurs
# des médailles ; sur chaque marche, le pilote et sa voiture, et le
# temps dans la marche. Marche vide : « — ».
# ============================================================

const STEP_COLORS := [Color("#ffd54f"), Color("#c0c0c0"), Color("#cd7f32")]
const STEP_HEIGHTS := [1.0, 0.72, 0.5]
# Ordre d'affichage de gauche à droite : 2e, 1er, 3e.
const LAYOUT := [1, 0, 2]

const NAME_FONT_SIZE := 26
const CAR_FONT_SIZE := 19
const TIME_FONT_SIZE := 24
const RANK_FONT_SIZE := 42
const TITLE_FONT_SIZE := 28
const MAX_SIZE := Vector2(560, 440)

## [{nickname, car_name, lap_time}], du plus rapide au plus lent.
var entries: Array = []
var title := "MEILLEURS TEMPS"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(480, 380)


func set_entries(p_entries: Array) -> void:
	entries = p_entries
	queue_redraw()


func _draw() -> void:
	var font := get_theme_font("font", "Label")
	# Podium centré dans la place disponible, à taille bornée.
	var box := Vector2(minf(size.x, MAX_SIZE.x), minf(size.y, MAX_SIZE.y))
	var origin := (size - box) / 2.0
	draw_set_transform(origin)
	var width := box.x
	var top := TITLE_FONT_SIZE + 10.0
	# Place au-dessus de la plus haute marche pour le nom et la voiture.
	var label_space := NAME_FONT_SIZE + CAR_FONT_SIZE + 12.0
	var max_step := box.y - top - label_space
	var step_width := width / 3.0

	_text(font, _fit(font, title, TITLE_FONT_SIZE, width), Vector2(width / 2.0, TITLE_FONT_SIZE), TITLE_FONT_SIZE, Color.WHITE)

	for column in range(3):
		var rank: int = LAYOUT[column]
		var height: float = max_step * STEP_HEIGHTS[rank]
		var rect := Rect2(column * step_width + 3.0, box.y - height, step_width - 6.0, height)
		var center_x := rect.position.x + rect.size.x / 2.0
		var color: Color = STEP_COLORS[rank]

		# Marche : ombre, couleur, liseré clair.
		draw_rect(Rect2(rect.position + Vector2(3, 3), rect.size), Color(0, 0, 0, 0.3))
		draw_rect(rect, color.darkened(0.15))
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 6.0)), color.lightened(0.25))

		_text(font, str(rank + 1), Vector2(center_x, rect.position.y + 10.0 + RANK_FONT_SIZE), RANK_FONT_SIZE, Color.WHITE)

		if rank >= entries.size():
			_text(font, "—", Vector2(center_x, rect.position.y - 10.0), NAME_FONT_SIZE, Color(1, 1, 1, 0.6))
			continue

		var entry: Dictionary = entries[rank]

		# Nom et voiture au-dessus de la marche, temps dedans.
		_text(font, _fit(font, String(entry.get("nickname", "?")), NAME_FONT_SIZE, rect.size.x), Vector2(center_x, rect.position.y - CAR_FONT_SIZE - 10.0), NAME_FONT_SIZE, color.lightened(0.3))
		_text(font, _fit(font, String(entry.get("car_name", "")), CAR_FONT_SIZE, rect.size.x), Vector2(center_x, rect.position.y - 5.0), CAR_FONT_SIZE, Color(1, 1, 1, 0.8))

		if rect.size.y > RANK_FONT_SIZE + TIME_FONT_SIZE + 24.0:
			_text(font, _format_time(float(entry.get("lap_time", 0.0))), Vector2(center_x, rect.position.y + RANK_FONT_SIZE + TIME_FONT_SIZE + 18.0), TIME_FONT_SIZE, Color.WHITE)


## Texte raccourci (« … ») pour tenir dans `width`.
func _fit(font: Font, text: String, font_size: int, width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return text

	while text.length() > 1 and font.get_string_size(text + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		text = text.left(text.length() - 1)

	return text + "…"


func _text(font: Font, text: String, pos: Vector2, font_size: int, color: Color) -> void:
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := Vector2(pos.x - text_width / 2.0, pos.y)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color.BLACK)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


static func _format_time(seconds: float) -> String:
	return "%d:%05.2f" % [int(seconds / 60.0), fmod(seconds, 60.0)]
