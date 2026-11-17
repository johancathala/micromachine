extends Node
class_name SkidMarkFader

# ============================================================
# EFFACEMENT DES TRACES DE PNEUS
# ============================================================
#
# Chaque glissade laisse une trace (Line2D) sous le nœud parent. Sans
# effacement, elles s'accumulent tout au long de la course et
# alourdissent l'affichage.
#
# Une trace reste nette LIFETIME secondes après son dernier point, puis
# s'estompe en FADE_TIME secondes avant d'être supprimée. Au-delà de
# MAX_MARKS traces, les plus anciennes commencent à s'estomper tout de
# suite (longues dérives à 8 voitures).
#
# L'âge suit le temps de jeu (rien ne s'efface pendant la pause) : il
# repart à zéro tant que la trace s'allonge.
# ============================================================

const LIFETIME := 15.0
const FADE_TIME := 5.0
const MAX_MARKS := 250
# Fréquence de mise à jour (s) : inutile de le faire à chaque image.
const UPDATE_INTERVAL := 0.2

const META_AGE := &"skid_age"
const META_LAST := &"skid_last_point"

var _timer := 0.0


func _process(delta: float) -> void:
	_timer += delta

	if _timer < UPDATE_INTERVAL:
		return

	var step := _timer
	_timer = 0.0
	var parent := get_parent()

	if parent == null:
		return

	var marks: Array[Line2D] = []

	for child in parent.get_children():
		var line := child as Line2D

		if line != null and not line.is_queued_for_deletion() and line.get_point_count() > 0:
			marks.append(line)

	# Trop de traces : les plus anciennes (premiers enfants) s'estompent
	# sans attendre.
	var excess := marks.size() - MAX_MARKS

	for i in range(marks.size()):
		var line := marks[i]
		var last_point := line.get_point_position(line.get_point_count() - 1)
		var age := float(line.get_meta(META_AGE, 0.0))

		if not line.has_meta(META_LAST) or line.get_meta(META_LAST) != last_point:
			# La voiture glisse encore : trace « fraîche ».
			line.set_meta(META_LAST, last_point)
			age = 0.0
		else:
			age += step

		if i < excess:
			age = maxf(age, LIFETIME)

		line.set_meta(META_AGE, age)

		if age <= LIFETIME:
			line.modulate.a = 1.0
			continue

		var alpha := 1.0 - (age - LIFETIME) / FADE_TIME

		if alpha <= 0.0:
			line.queue_free()
		else:
			line.modulate.a = alpha
