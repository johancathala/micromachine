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
# Boucle fermée (tour du circuit) ou trajet ouvert (passage au stand).
var closed := true
# Place praticable (px) de chaque côté de la ligne, le long de
# direction(i).orthogonal() (room_plus) et à l'opposé (room_minus).
# Vide si inconnue.
var room_plus := PackedFloat32Array()
var room_minus := PackedFloat32Array()


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

	if progress != null and line.is_valid():
		line._measure_room(progress)

	return line


func _measure_room(progress: TrackProgress) -> void:
	var count := points.size()
	room_plus.resize(count)
	room_minus.resize(count)

	for i in range(count):
		var normal := direction(i).orthogonal()
		room_plus[i] = progress.drivable_extent(points[i], normal)
		room_minus[i] = progress.drivable_extent(points[i], -normal)


func is_valid() -> bool:
	return points.size() >= 8


## Trajet ouvert (points déjà espacés de SPACING px).
static func open_path(new_points: PackedVector2Array, p_source: String) -> RacingLine:
	var line := RacingLine.new()
	line.closed = false
	line._set_points(new_points)
	line.source = p_source
	return line


func _set_points(new_points: PackedVector2Array) -> void:
	points = new_points
	length = points.size() * SPACING

	var count := points.size()
	curvature.resize(count)
	signed_curvature.resize(count)

	for i in range(count):
		var a := point(i - CURVATURE_SPAN)
		var b := points[i]
		var c := point(i + CURVATURE_SPAN)
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
		var i := wrap_index(hint + offset)
		var d := position.distance_squared_to(points[i])

		if d < best_distance:
			best_distance = d
			best = i

	return best


## Indice ramené sur la ligne : bouclé, ou borné pour un trajet ouvert.
func wrap_index(index: int) -> int:
	if closed:
		return posmod(index, points.size())

	return clampi(index, 0, points.size() - 1)


func point(index: int) -> Vector2:
	return points[wrap_index(index)]


func curvature_at(index: int) -> float:
	return curvature[wrap_index(index)]


func signed_curvature_at(index: int) -> float:
	return signed_curvature[wrap_index(index)]


## Direction de la ligne en un point.
func direction(index: int) -> Vector2:
	var from := point(index - 2)
	var to := point(index + 2)

	if from.distance_squared_to(to) < 1.0:
		return Vector2.RIGHT

	return (to - from).normalized()
