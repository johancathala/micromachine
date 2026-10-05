extends RefCounted
class_name RaceParticipantState


# ============================================================
# IDENTITÉ
# ============================================================

var participant_id: int = -1
var nickname: String = ""
var car: Car = null
var is_ai: bool = false
var input_device_type: String = ""


# ============================================================
# ÉTAT DE COURSE
# ============================================================

var finished: bool = false
var finish_position: int = 0

var current_lap: int = 0
var next_section: int = 0
var has_started_lap: bool = false

var race_position: int = 0
var last_progress_time: float = 0.0


# ============================================================
# CHRONOMÉTRAGE DU TOUR COURANT
# ============================================================

var lap_start_time: float = 0.0
var last_lap_time: float = 0.0

# Timestamps absolus du tour actuellement parcouru.
#
# Exemple avec 4 sections :
#
# [ départ, section1, section2, section3, arrivée ]
#
var section_times: Array[float] = []
var last_section_time = 0.0
var last_section_delta = 0.0
var last_section_index = -1

# ============================================================
# HISTORIQUE DES TOURS
# ============================================================

# Un élément par tour terminé :
#
# {
#     "lap": 1,
#     "lap_time": 42.531,
#     "section_times": [8.421, 11.203, 10.871, 12.036]
# }
#
var lap_records: Array[Dictionary] = []


# ============================================================
# MEILLEURS TEMPS
# ============================================================

var best_lap_time: float = 0.0

# Meilleur temps de chaque secteur.
#
# Index 0 = section 0
# Index 1 = section 1
# ...
#
var best_section_times: Array[float] = []


# ============================================================
# FIN DE COURSE
# ============================================================

# Temps absolu depuis le départ jusqu'à l'arrivée.
var finish_time: float = 0.0


func initialize(
	p_participant_id: int,
	p_nickname: String,
	p_car: Car,
	p_is_ai: bool,
	p_section_count: int,
	p_input_device_type: String
) -> void:

	participant_id = p_participant_id
	nickname = p_nickname
	car = p_car
	is_ai = p_is_ai
	input_device_type = p_input_device_type

	finished = false
	finish_position = 0

	current_lap = 0
	next_section = 0
	has_started_lap = false

	race_position = 0
	last_progress_time = 0.0

	lap_start_time = 0.0
	last_lap_time = 0.0

	section_times.clear()
	lap_records.clear()

	best_lap_time = 0.0

	best_section_times.clear()

	for i in range(p_section_count):
		best_section_times.append(0.0)

	finish_time = 0.0

	race_position = 0
	last_progress_time = 0.0
	last_section_time = 0.0
	last_section_delta = 0.0
	last_section_index = -1
