extends Control
class_name MinimapOverlay

# ============================================================
# Pastilles des joueurs sur la minimap (écran splitté).
# Les voitures sont trop petites à ce niveau de dézoom : chaque
# joueur est repéré par une pastille numérotée.
# ============================================================

const MARKER_RADIUS := 11.0
const PLAYER_COLORS := [
	Color("#ffd54f"), Color("#4fc3f7"), Color("#ef5350"), Color("#81c784"),
	Color("#ba68c8"), Color("#ffb74d"), Color("#f06292"), Color("#e0e0e0")
]

var viewport: SubViewport = null
var states: Array[RaceParticipantState] = []


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if viewport == null:
		return

	var canvas := viewport.get_canvas_transform()
	var font := ThemeDB.fallback_font

	for i in range(states.size()):
		var state := states[i]

		if not is_instance_valid(state.car) or not state.car.visible:
			continue

		var point := canvas * state.car.global_position
		var color: Color = PLAYER_COLORS[i % PLAYER_COLORS.size()]

		draw_circle(point, MARKER_RADIUS + 2.0, Color.BLACK)
		draw_circle(point, MARKER_RADIUS, color)

		var label := str(i + 1)
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string(
			font,
			point + Vector2(-text_size.x / 2.0, 6.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color.BLACK
		)
