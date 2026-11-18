extends RefCounted
class_name AIStyle

# ============================================================
# STYLES DE PILOTAGE (IA)
# ============================================================
#
# Le niveau (Novice, Moyen, Expert) dit à quel point un pilote est bon ;
# le style dit COMMENT il pilote. Chaque IA a les deux, choisis sur
# l'écran des IA.
#
# Traits (1 = neutre) :
#   corner       vitesse visée en virage
#   braking      freinage anticipé (> 1 : freine plus tard, plus fort)
#   pace         rythme général
#   line_bias    trajectoire : < 0 serre l'intérieur, > 0 reste large
#                (fraction de la place disponible)
#   wander       dérive latérale propre au pilote (px), lente
#   noise        irrégularité d'un tour à l'autre (fraction, points de
#                freinage et vitesses de passage)
#   mistakes     fréquence des erreurs (Novice et Moyen seulement)
#   overtake     audace au dépassement (distance, écart, prise de risque)
#   traffic_care prudence en peloton (vitesse de virage sûre près d'une
#                autre voiture)
#   finish_push  Tacticien : rythme retenu, puis attaque dans les derniers
#                tours (0 : non)
# ============================================================

const DEFAULT_ID := "equilibre"

const STYLES := [
	{
		"id": "equilibre", "name": "Équilibré",
		"description": "Pilotage propre et complet : bonne trajectoire, freinages justes, dépasse quand l'occasion se présente.",
		"corner": 1.0, "braking": 1.0, "pace": 1.0, "line_bias": 0.0, "wander": 20.0,
		"noise": 0.015, "mistakes": 1.0, "overtake": 1.0, "traffic_care": 1.0, "finish_push": 0.0
	},
	{
		"id": "prudent", "name": "Prudent",
		"description": "Assure avant tout : trajectoire large, freine tôt, laisse de la place aux autres. Peu d'erreurs, mais rarement devant.",
		"corner": 0.95, "braking": 0.85, "pace": 0.98, "line_bias": 0.35, "wander": 15.0,
		"noise": 0.01, "mistakes": 0.5, "overtake": 0.6, "traffic_care": 1.0, "finish_push": 0.0
	},
	{
		"id": "agressif", "name": "Agressif",
		"description": "Freine très tard, rase les cordes et plonge à l'intérieur dès qu'il voit une ouverture. Rapide, mais il commet plus d'erreurs.",
		"corner": 1.04, "braking": 1.2, "pace": 1.01, "line_bias": -0.5, "wander": 25.0,
		"noise": 0.035, "mistakes": 1.6, "overtake": 1.6, "traffic_care": 0.0, "finish_push": 0.0
	},
	{
		"id": "metronome", "name": "Métronome",
		"description": "Une régularité d'horloge : la même trajectoire et les mêmes freinages à chaque tour. Très peu d'erreurs.",
		"corner": 1.0, "braking": 1.0, "pace": 1.0, "line_bias": 0.0, "wander": 5.0,
		"noise": 0.003, "mistakes": 0.3, "overtake": 0.9, "traffic_care": 1.0, "finish_push": 0.0
	},
	{
		"id": "tacticien", "name": "Tacticien",
		"description": "Économise sa voiture et ses pneus en début de course, puis attaque fort dans les deux derniers tours.",
		"corner": 0.99, "braking": 0.95, "pace": 0.97, "line_bias": 0.1, "wander": 15.0,
		"noise": 0.012, "mistakes": 0.8, "overtake": 1.1, "traffic_care": 1.0, "finish_push": 0.06
	},
	{
		"id": "opportuniste", "name": "Opportuniste",
		"description": "Colle à l'adversaire, profite de son aspiration et attaque dès qu'une porte s'ouvre.",
		"corner": 1.0, "braking": 1.05, "pace": 0.99, "line_bias": -0.2, "wander": 20.0,
		"noise": 0.02, "mistakes": 1.1, "overtake": 1.5, "traffic_care": 0.5, "finish_push": 0.0
	},
	{
		"id": "spectaculaire", "name": "Spectaculaire",
		"description": "Glisse en travers, sort large des virages et cherche la glisse plutôt que le chrono. Imprévisible.",
		"corner": 1.06, "braking": 1.05, "pace": 1.0, "line_bias": 0.6, "wander": 40.0,
		"noise": 0.05, "mistakes": 1.3, "overtake": 1.2, "traffic_care": 0.5, "finish_push": 0.0
	},
	{
		"id": "imprevisible", "name": "Imprévisible",
		"description": "Change de rythme et de trajectoire d'un tour à l'autre : parfois très rapide, parfois à la peine.",
		"corner": 1.0, "braking": 1.0, "pace": 1.0, "line_bias": 0.0, "wander": 35.0,
		"noise": 0.07, "mistakes": 1.2, "overtake": 1.2, "traffic_care": 0.5, "finish_push": 0.0
	}
]

# Description des niveaux (écran des IA).
const LEVEL_DESCRIPTIONS := [
	"Pilote hésitant : rythme modeste et environ une erreur par tour (35 % de tours sans faute) : freinages manqués, sorties larges, tête-à-queue, qui l'envoient souvent dans le décor.",
	"Pilote solide : bon rythme, une erreur tous les deux ou trois tours (60 % de tours sans faute), parfois une sortie de route.",
	"Pilote d'élite : au plus près des limites (98 % de tours sans faute) ; ses rares erreurs sont légères et il ne part jamais dans le décor de lui-même."
]

# Part des tours sans aucune erreur, selon le niveau (Novice, Moyen,
# Expert), pour un style au comportement « mistakes » = 1. Le nombre
# d'erreurs d'un tour suit une loi de Poisson de moyenne -ln(part).
const CLEAN_LAPS := [0.35, 0.60, 0.98]


static func get_styles() -> Array:
	return STYLES


static func get_style(style_id: String) -> Dictionary:
	for style in STYLES:
		if style["id"] == style_id:
			return style

	return STYLES[0]


static func has_style(style_id: String) -> bool:
	for style in STYLES:
		if style["id"] == style_id:
			return true

	return false


## Identifiants de tous les styles, mélangés (pour « Remplir »).
static func shuffled_ids() -> Array[String]:
	var ids: Array[String] = []

	for style in STYLES:
		ids.append(String(style["id"]))

	ids.shuffle()
	return ids
