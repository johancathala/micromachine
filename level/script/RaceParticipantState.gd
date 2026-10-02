extends RefCounted
class_name RaceParticipantState


# ============================================================
# IDENTIFICATION
# ============================================================

var participant_id: int = -1
var nickname: String = ""
var device_type: String = ""

var car: Car = null

var is_ai: bool = false


# ============================================================
# ÉTAT DE COURSE
# ============================================================

var finished: bool = false

var finish_position: int = 0


# ============================================================
# PROGRESSION SUR LE CIRCUIT
# ============================================================

# 0 = la voiture n'a pas encore franchi la ligne de départ.
# 1 = premier tour en cours.
# 2 = deuxième tour en cours, etc.
var current_lap: int = 0

# ID de la prochaine section que la voiture doit franchir.
var next_section: int = 0

# Indique si la voiture a déjà franchi la ligne de départ
# depuis le début de la course.
var has_started_lap: bool = false


# ============================================================
# CHRONOMÉTRAGE
# ============================================================

# Temps de course auquel le tour courant a commencé.
var lap_start_time: float = 0.0

# Temps du dernier tour terminé.
var last_lap_time: float = 0.0

# Meilleur temps au tour.
var best_lap_time: float = 0.0


# ============================================================
# CHRONOMÉTRAGE DES SECTIONS
# ============================================================

# Temps absolus de passage des sections du tour courant.
#
# Exemple :
#
# section 0 -> 12.351 s
# section 1 -> 15.842 s
# section 2 -> 19.221 s
#
# Ces valeurs permettent ensuite de calculer les temps
# intermédiaires et les écarts.
var section_times: Array[float] = []


# Meilleur temps réalisé sur chaque section.
#
# Exemple :
#
# section 0 -> 2.154 s
# section 1 -> 3.487 s
# section 2 -> 2.921 s
#
var best_section_times: Array[float] = []


# ============================================================
# CLASSEMENT
# ============================================================

var race_position: int = 0

# Dernier instant auquel la voiture a validé une section.
#
# Utilisé pour départager deux voitures qui ont :
# - le même tour ;
# - la même section.
var last_progress_time: float = 0.0


# ============================================================
# INITIALISATION
# ============================================================

func initialize(
	p_participant_id: int,
	p_nickname: String,
	p_car: Car,
	p_is_ai: bool,
	p_section_count: int,
	p_device_type: String
) -> void:

	participant_id = p_participant_id
	nickname = p_nickname
	device_type = p_device_type
	car = p_car
	is_ai = p_is_ai

	finished = false
	finish_position = 0

	current_lap = 0
	next_section = 0
	has_started_lap = false

	lap_start_time = 0.0
	last_lap_time = 0.0
	best_lap_time = 0.0

	section_times.clear()

	best_section_times.clear()

	for i in range(p_section_count):
		best_section_times.append(0.0)

	race_position = 0
	last_progress_time = 0.0
