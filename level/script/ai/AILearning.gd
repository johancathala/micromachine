extends RefCounted
class_name AILearning

# ============================================================
# APPRENTISSAGE DES VIRAGES (IA)
# ============================================================
#
# Les IA visent une glisse généreuse en virage (AIDriver.CAR_CORNER_SLIP).
# Certains virages ne la tolèrent pas (barils, arbres au bord de la
# trajectoire) : quand une IA s'écrase seule, elle réduit sa vitesse
# visée sur la portion qui précède le choc. Ce réglage est retenu par
# circuit et par voiture, partagé par toutes les IA de cette voiture.
#
# Mémoire :
#   - SEED_PATH : appris en essais et livré avec le jeu ;
#   - USER_PATH : ce que les IA apprennent en jouant (complète le
#     précédent ; la valeur la plus prudente l'emporte).
# Chaque point retenu : position (x, y) et facteur de vitesse (< 1).
# Les positions (et non les indices) survivent à une modification de
# la trajectoire du circuit.
# ============================================================

const SEED_PATH := "res://level/script/ai/ai_learning.json"
const USER_PATH := "user://ai_learning.json"

# Portion ralentie avant le point du choc, et un peu après (points).
const WINDOW_BEFORE := 40
const WINDOW_AFTER := 4
# Réduction de vitesse par choc, et plancher.
const CRASH_FACTOR := 0.88
const MIN_FACTOR := 0.35

# Fichier où retenir ce qui est appris ("" : rien n'est enregistré).
static var save_path := USER_PATH

# clé "circuit|voiture" -> Array de [x, y, facteur].
static var _data: Dictionary = {}
static var _loaded := false
# Compteur de modifications par clé (les IA rafraîchissent leur profil).
static var _versions: Dictionary = {}


## Génération de l'apprentissage : un changement de comportement de l'IA
## rend l'ancien inutilisable (ralentissements à contretemps). Les clés
## d'une autre génération sont ignorées, sans rien effacer.
const GENERATION := 2


static func make_key(track_path: String, car_id: String) -> String:
	return "v%d|%s|%s" % [GENERATION, track_path, car_id]


static func _ensure_loaded() -> void:
	if _loaded:
		return

	_loaded = true
	_merge_file(SEED_PATH)

	if not save_path.is_empty():
		_merge_file(save_path)


static func _merge_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))

	if not parsed is Dictionary:
		return

	for key: String in parsed:
		var points: Array = _data.get(key, [])
		points.append_array(parsed[key])
		_data[key] = points


## Facteurs de vitesse (1 = aucun ralentissement) en chaque point de
## la ligne.
static func factors(key: String, line: RacingLine) -> PackedFloat32Array:
	_ensure_loaded()

	var result := PackedFloat32Array()
	result.resize(line.points.size())
	result.fill(1.0)

	for entry: Array in _data.get(key, []):
		var index := line.closest_index(Vector2(float(entry[0]), float(entry[1])))
		result[index] = minf(result[index], float(entry[2]))

	return result


static func version(key: String) -> int:
	return int(_versions.get(key, 0))


## Choc en `index` : ralentir la portion qui précède.
static func record_crash(key: String, line: RacingLine, index: int) -> void:
	var current := factors(key, line)
	var points: Array = []

	for offset in range(-WINDOW_BEFORE, WINDOW_AFTER + 1):
		var i := line.wrap_index(index + offset)
		current[i] = maxf(current[i] * CRASH_FACTOR, MIN_FACTOR)

	# Seuls les points ralentis sont retenus.
	for i in range(current.size()):
		if current[i] < 0.999:
			points.append([snappedf(line.points[i].x, 0.1), snappedf(line.points[i].y, 0.1), snappedf(current[i], 0.001)])

	_data[key] = points
	_versions[key] = version(key) + 1
	_save()


static func _save() -> void:
	if save_path.is_empty():
		return

	var file := FileAccess.open(save_path, FileAccess.WRITE)

	if file == null:
		push_warning("AILearning : impossible d'écrire " + save_path)
		return

	file.store_string(JSON.stringify(_data, "\t"))
	file.close()


## Essais : repartir de la mémoire livrée (ou de rien), puis de
## save_path s'il existe.
static func reset(use_seed: bool) -> void:
	_data.clear()
	_versions.clear()
	_loaded = true

	if use_seed:
		_merge_file(SEED_PATH)

	if not save_path.is_empty():
		_merge_file(save_path)
