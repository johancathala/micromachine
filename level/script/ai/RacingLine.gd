extends RefCounted
class_name RacingLine

# ============================================================
# TRAJECTOIRE IDÉALE (pour l'IA)
# ============================================================
#
# Source, par ordre de priorité :
#   1. un nœud Path2D nommé « RacingLine » dans le circuit : modifiable
#      dans l'éditeur Godot (déplacer / ajouter des points), l'IA s'y
#      adapte au lancement de la course ;
#   2. sinon, l'axe de la chaussée calculé le long du parcours
#      (TrackProgress.build_centerline).
#
# Points régulièrement espacés (SPACING px), boucle fermée, dans le
# sens de la course. Courbure précalculée en chaque point.
# ============================================================

const SPACING := 32.0
# Demi-fenêtre (en points) pour estimer la courbure.
const CURVATURE_SPAN := 3

var points := PackedVector2Array()
var curvature := PackedFloat32Array()
# Courbure signée : positive quand la ligne tourne dans le sens des
# angles croissants (sens de rotation des voitures).
var signed_curvature := PackedFloat32Array()
var length := 0.0
var source := ""


static func from_track(track: Node, progress: TrackProgress) -> RacingLine:
	var line := RacingLine.new()
	var path := track.find_child("RacingLine", true, false) as Path2D

	if path != null and path.curve != null and path.curve.point_count >= 3:
		var baked := path.curve.get_baked_points()
		var global_points := PackedVector2Array()

		for point in baked:
			global_points.append(path.to_global(point))

		line._set_points(TrackProgress.resample_closed(global_points, SPACING))
		line.source = "tracé RacingLine du circuit"
	elif progress != null:
		line._set_points(progress.build_racing_line(SPACING))
		line.source = "trajectoire calculée (chaussée)"

	return line


func is_valid() -> bool:
	return points.size() >= 8


func _set_points(new_points: PackedVector2Array) -> void:
	points = new_points
	length = points.size() * SPACING

	var count := points.size()
	curvature.resize(count)
	signed_curvature.resize(count)

	for i in range(count):
		var a := points[posmod(i - CURVATURE_SPAN, count)]
		var b := points[i]
		var c := points[(i + CURVATURE_SPAN) % count]
		curvature[i] = _menger_curvature(a, b, c)
		signed_curvature[i] = curvature[i] * signf((b - a).cross(c - b))


## Courbure du cercle passant par trois points (1 / rayon).
static func _menger_curvature(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ca := c.distance_to(a)
	var denominator := ab * bc * ca

	if denominator < 0.0001:
		return 0.0

	var area2 := absf((b - a).cross(c - a))
	return 2.0 * area2 / denominator


## Indice du point le plus proche, recherché autour de `hint`
## (suivi continu le long de la boucle), ou sur toute la ligne.
func closest_index(position: Vector2, hint: int = -1, window: int = 60) -> int:
	var count := points.size()
	var best := 0
	var best_distance := INF

	if hint < 0:
		for i in range(count):
			var d := position.distance_squared_to(points[i])

			if d < best_distance:
				best_distance = d
				best = i

		return best

	for offset in range(-window, window + 1):
		var i := posmod(hint + offset, count)
		var d := position.distance_squared_to(points[i])

		if d < best_distance:
			best_distance = d
			best = i

	return best


func point(index: int) -> Vector2:
	return points[posmod(index, points.size())]


func curvature_at(index: int) -> float:
	return curvature[posmod(index, points.size())]


func signed_curvature_at(index: int) -> float:
	return signed_curvature[posmod(index, points.size())]


## Direction de la ligne en un point.
func direction(index: int) -> Vector2:
	return (point(index + 2) - point(index - 2)).normalized()
