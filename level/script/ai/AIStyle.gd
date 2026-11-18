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
# Chaque style porte aussi le nom de pilote affiché en course
# (« driver » : Régis...), et une description pour l'écran des IA.
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
		"id": "equilibre", "name": "Équilibré", "driver": "Jean-Michel",
		"description": "Ni trop, ni trop peu. Le gendre idéal, chemise rentrée dans le pantalon.",
		"corner": 1.0, "braking": 1.0, "pace": 1.0, "line_bias": 0.0, "wander": 20.0,
		"noise": 0.015, "mistakes": 1.0, "overtake": 1.0, "traffic_care": 1.0, "finish_push": 0.0
	},
	{
		"id": "prudent", "name": "Prudent", "driver": "Papy Airbag",
		"description": "Gilet jaune sur le siège passager, triangle dans le coffre.",
		"corner": 0.95, "braking": 0.85, "pace": 0.98, "line_bias": 0.35, "wander": 15.0,
		"noise": 0.01, "mistakes": 0.5, "overtake": 0.6, "traffic_care": 1.0, "finish_push": 0.0
	},
	{
		"id": "agressif", "name": "Agressif", "driver": "Brian Turbo",
		"description": "Freine quand il voit Dieu. Et encore.",
		"corner": 1.04, "braking": 1.2, "pace": 1.01, "line_bias": -0.5, "wander": 25.0,
		"noise": 0.035, "mistakes": 1.6, "overtake": 1.6, "traffic_care": 0.0, "finish_push": 0.0
	},
	{
		"id": "metronome", "name": "Métronome", "driver": "Monsieur Pointeuse",
		"description": "Même trajectoire, même freinage, même heure. Il prend son café à 7 h 32 depuis 1998. Un connard fini.",
		"corner": 1.0, "braking": 1.0, "pace": 1.0, "line_bias": 0.0, "wander": 5.0,
		"noise": 0.003, "mistakes": 0.3, "overtake": 0.9, "traffic_care": 1.0, "finish_push": 0.0
	},
	{
		"id": "tacticien", "name": "Tacticien", "driver": "Deep Blue",
		"description": "Il garde ses pneus comme son pognon. Au dernier tour, il se réveille et c'est toi qui pleures.",
		"corner": 0.99, "braking": 0.95, "pace": 0.97, "line_bias": 0.1, "wander": 15.0,
		"noise": 0.012, "mistakes": 0.8, "overtake": 1.1, "traffic_care": 1.0, "finish_push": 0.06
	},
	{
		"id": "opportuniste", "name": "Opportuniste", "driver": "Le FDP",
		"description": "Il te colle au cul et te double en faisant un doigt.",
		"corner": 1.0, "braking": 1.05, "pace": 0.99, "line_bias": -0.2, "wander": 20.0,
		"noise": 0.02, "mistakes": 1.1, "overtake": 1.5, "traffic_care": 0.5, "finish_push": 0.0
	},
	{
		"id": "spectaculaire", "name": "Spectaculaire", "driver": "Régis",
		"description": "Le chrono, il s'en fout, il est fini à la pisse.",
		"corner": 1.06, "braking": 1.05, "pace": 1.0, "line_bias": 0.6, "wander": 40.0,
		"noise": 0.05, "mistakes": 1.3, "overtake": 1.2, "traffic_care": 0.5, "finish_push": 0.0
	},
	{
		"id": "imprevisible", "name": "Imprévisible", "driver": "Tonton Jackie",
		"description": "Un tour pilote de F1, un tour grand-mère. Même lui ne sait pas lequel arrive.",
		"corner": 1.0, "braking": 1.0, "pace": 1.0, "line_bias": 0.0, "wander": 35.0,
		"noise": 0.07, "mistakes": 1.2, "overtake": 1.2, "traffic_care": 0.5, "finish_push": 0.0
	}
]

# Description des niveaux (écran des IA).
const LEVEL_DESCRIPTIONS := [
	"Il a eu son permis dans un Kinder Surprise.",
	"Roule mieux avec trois pastis dans le cornet.",
	"Il pisse du sans-plomb 98 et a appris à conduire avant de marcher."
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
