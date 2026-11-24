extends RefCounted
class_name AIDriverRoster

# ============================================================
# ROSTER DES PILOTES IA
# ============================================================
#
# 24 pilotes nommés, uniques : 8 par niveau (Novice, Moyen, Expert),
# et dans chaque niveau les 8 styles de pilotage d'AIStyle, dans le
# même ordre. Le joueur choisit un nom ; le niveau et le style restent
# internes (niveau affiché entre parenthèses).
#
# Un pilote ne peut être engagé qu'une fois : l'écran des IA grise les
# noms déjà pris.
#
# Les niveaux reprennent les valeurs de RaceConfig.AIPilot (0 = Novice,
# 1 = Moyen, 2 = Expert) sans dépendre de RaceConfig (évite un cycle
# d'autant plus gênant que RaceConfig lit aussi ce roster).
#
# Extension prévue : carrière, avatars et dialogues avant / après
# course. Ajouter ici les champs correspondants (portrait, répliques,
# statistiques...) : les écrans les liront par identifiant stable.
# ============================================================

const LEVEL_NOVICE := 0
const LEVEL_MEDIUM := 1
const LEVEL_EXPERT := 2

# Ordre des styles dans chaque niveau : celui d'AIStyle.STYLES.
const DRIVERS := [
	# Expert.
	{"id": "niki_laurage", "name": "Niki Laurage", "level": LEVEL_EXPERT, "style": "equilibre"},
	{"id": "lewis_hamiltemps", "name": "Lewis Hamiltemps", "level": LEVEL_EXPERT, "style": "prudent"},
	{"id": "max_verstapenade", "name": "Max Verstapenade", "level": LEVEL_EXPERT, "style": "agressif"},
	{"id": "michael_choumache", "name": "Michael Choumaché", "level": LEVEL_EXPERT, "style": "metronome"},
	{"id": "alain_prout", "name": "Alain Prout", "level": LEVEL_EXPERT, "style": "tacticien"},
	{"id": "fernando_au_lonzo", "name": "Fernando Au Lonzo", "level": LEVEL_EXPERT, "style": "opportuniste"},
	{"id": "ayrton_sauna", "name": "Ayrton Sauna", "level": LEVEL_EXPERT, "style": "spectaculaire"},
	{"id": "juan_manuel_fangio", "name": "Juan Manuel Fangio", "level": LEVEL_EXPERT, "style": "imprevisible"},
	# Moyen.
	{"id": "william_toulouse", "name": "William Toulouse", "level": LEVEL_MEDIUM, "style": "equilibre"},
	{"id": "yanis", "name": "Yanis", "level": LEVEL_MEDIUM, "style": "prudent"},
	{"id": "gabin", "name": "Gabin", "level": LEVEL_MEDIUM, "style": "agressif"},
	{"id": "lenny", "name": "Lenny", "level": LEVEL_MEDIUM, "style": "metronome"},
	{"id": "axel", "name": "Axel", "level": LEVEL_MEDIUM, "style": "tacticien"},
	{"id": "le_mos", "name": "Le Mos", "level": LEVEL_MEDIUM, "style": "opportuniste"},
	{"id": "bernard_valois", "name": "Bernard Valois", "level": LEVEL_MEDIUM, "style": "spectaculaire"},
	{"id": "daniel_dupont", "name": "Daniel Dupont", "level": LEVEL_MEDIUM, "style": "imprevisible"},
	# Novice.
	{"id": "liam", "name": "Liam", "level": LEVEL_NOVICE, "style": "equilibre"},
	{"id": "jorel", "name": "Jorel", "level": LEVEL_NOVICE, "style": "prudent"},
	{"id": "loan", "name": "Loan", "level": LEVEL_NOVICE, "style": "agressif"},
	{"id": "livia", "name": "Livia", "level": LEVEL_NOVICE, "style": "metronome"},
	{"id": "samuel", "name": "Samuel", "level": LEVEL_NOVICE, "style": "tacticien"},
	{"id": "aina", "name": "Aina", "level": LEVEL_NOVICE, "style": "opportuniste"},
	{"id": "gaspard", "name": "Gaspard", "level": LEVEL_NOVICE, "style": "spectaculaire"},
	{"id": "abel", "name": "Abel", "level": LEVEL_NOVICE, "style": "imprevisible"}
]


static func get_drivers() -> Array:
	return DRIVERS


## Pilote par identifiant ; {} s'il n'existe pas.
static func get_driver(driver_id: String) -> Dictionary:
	for driver in DRIVERS:
		if driver["id"] == driver_id:
			return driver

	return {}


static func has_driver(driver_id: String) -> bool:
	return not get_driver(driver_id).is_empty()


## Pilotes d'un niveau, dans l'ordre des styles.
static func for_level(level: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for driver in DRIVERS:
		if int(driver["level"]) == level:
			result.append(driver)

	return result


## Pilote d'un niveau et d'un style (un seul par combinaison) ; {} si
## la combinaison n'existe pas.
static func find_by_level_style(level: int, style_id: String) -> Dictionary:
	for driver in DRIVERS:
		if int(driver["level"]) == level and String(driver["style"]) == style_id:
			return driver

	return {}
