extends RefCounted
class_name RaceConfig

const TOTAL_RACE_SLOTS := 8
const MAX_HUMAN_PLAYERS := 8

# Règles de la partie.
enum RaceRules {
	# Course classique au nombre de tours.
	CLASSIC,
	# Élimination (écran partagé, humains uniquement) :
	# un joueur qui sort de l'écran explose. Quand il ne reste qu'un
	# joueur, la manche est terminée, les points sont distribués et
	# la course repart en grille inversée à la position du leader.
	ELIMINATION,
	# Contre-la-montre : un seul joueur, sans IA, contre le fantôme de
	# son meilleur tour (un fantôme par circuit et par voiture).
	TIME_TRIAL
}

const ELIMINATION_MIN_PLAYERS := 2
const DEFAULT_TARGET_SCORE := 10


var mode: GameManager.GameMode = GameManager.GameMode.SINGLE_RACE

var ai_difficulty: int = 0
var track: Dictionary = {}
var lap_count: int = 3

var race_rules: RaceRules = RaceRules.CLASSIC

# Mode élimination : score qui fait gagner la partie.
var target_score: int = DEFAULT_TARGET_SCORE

# Course classique : une vue par joueur humain (écran splitté)
# au lieu d'une caméra commune (écran partagé).
var split_screen: bool = false

# Course classique : usure des pneus et arrêts au stand.
var tire_wear: bool = false

# Contre-la-montre : fantômes affichés (GhostManager.GhostMode :
# 0 = les deux, 1 = le meilleur, 2 = celui du joueur).
var ghost_mode: int = 0

# Joueurs humains ayant rejoint le lobby.
var players: Array[Dictionary] = []

# Grille complète après CarSelection :
# humains + IA.
var participants: Array[Dictionary] = []


# ================================================================
# JOUEURS HUMAINS
# ================================================================

func get_human_player_count() -> int:
	return players.size()


func get_ai_count() -> int:
	if not is_classic():
		return 0

	return TOTAL_RACE_SLOTS - get_human_player_count()


func is_full() -> bool:
	return get_human_player_count() >= MAX_HUMAN_PLAYERS


func has_keyboard_player(device_id: int = -1) -> bool:
	for player in players:
		if str(player.get("device_type", "")) != "keyboard":
			continue

		# -1 : n'importe quel joueur clavier.
		if device_id < 0:
			return true

		if InputManager.get_keyboard_index(
			int(player.get("device_id", 0))
		) == device_id:
			return true

	return false


## Premier emplacement clavier libre (0 ou 1), -1 si tous sont pris.
func get_free_keyboard_id() -> int:
	for keyboard_id in range(InputManager.KEYBOARD_PLAYER_COUNT):
		if not has_keyboard_player(keyboard_id):
			return keyboard_id

	return -1


func has_gamepad_player(device_id: int) -> bool:
	for player in players:
		if str(player.get("device_type", "")) == "gamepad":
			if int(player.get("device_id", -1)) == device_id:
				return true

	return false


func get_player_by_id(player_id: int) -> Dictionary:
	for player in players:
		if int(player.get("player_id", -1)) == player_id:
			return player

	return {}


func remove_player(player_id: int) -> bool:
	for i in range(players.size()):
		if int(players[i].get("player_id", -1)) == player_id:
			players.remove_at(i)
			return true

	return false


func get_next_player_id() -> int:
	for candidate in range(players.size() + 1):
		var used := false

		for player in players:
			if int(player.get("player_id", -1)) == candidate:
				used = true
				break

		if not used:
			return candidate

	return -1

# ================================================================
# VALIDATION RACE SETUP
# ================================================================

func is_valid() -> bool:
	if players.is_empty():
		return false

	if players.size() > MAX_HUMAN_PLAYERS:
		return false

	if track.is_empty():
		return false

	if lap_count <= 0:
		return false

	if is_elimination():
		if players.size() < ELIMINATION_MIN_PLAYERS:
			return false

		if target_score <= 0:
			return false

	# Contre-la-montre : un seul joueur.
	if is_time_trial() and players.size() != 1:
		return false

	return true


func is_elimination() -> bool:
	return race_rules == RaceRules.ELIMINATION


func is_time_trial() -> bool:
	return race_rules == RaceRules.TIME_TRIAL


func is_classic() -> bool:
	return race_rules == RaceRules.CLASSIC


## Tours illimités : élimination (fin au score) et contre-la-montre
## (on enchaîne les tours jusqu'à quitter la course).
func has_infinite_laps() -> bool:
	return not is_classic()


## L'usure des pneus ne concerne que la course classique
## (écran partagé ou splitté).
func uses_tire_wear() -> bool:
	return tire_wear and is_classic()


## L'écran splitté ne s'applique qu'à la course classique,
## avec au moins deux joueurs humains.
func uses_split_screen() -> bool:
	return (
		split_screen
		and is_classic()
		and get_human_player_count() >= 2
	)


# ================================================================
# PARTICIPANTS
# ================================================================

func build_participants() -> void:
	var previous := participants.duplicate(true)

	participants.clear()

	for i in range(players.size()):
		var player := players[i].duplicate(true)

		var participant := player
		participant["participant_id"] = i
		participant["is_ai"] = false
		participant["enabled"] = true

		var old := _find_previous_participant(
			previous,
			i,
			false
		)

		if not old.is_empty():
			if old.has("car_id"):
				participant["car_id"] = old["car_id"]

			if old.has("color_id"):
				participant["color_id"] = old["color_id"]

		participants.append(participant)

	var ai_count := TOTAL_RACE_SLOTS - players.size()

	# Pas d'IA en élimination (la caméra ne suit que les humains) ni en
	# contre-la-montre (seul contre son fantôme).
	if not is_classic():
		ai_count = 0

	for i in range(ai_count):
		var participant_id := players.size() + i

		var participant := {
			"participant_id": participant_id,
			"player_id": -1,
			"device_type": "ai",
			"device_id": -1,
			"nickname": "IA %d" % (i + 1),
			"is_ai": true,
			"enabled": false
		}

		var old := _find_previous_participant(
			previous,
			participant_id,
			true
		)

		if not old.is_empty():
			if old.has("car_id"):
				participant["car_id"] = old["car_id"]

			if old.has("color_id"):
				participant["color_id"] = old["color_id"]

		participants.append(participant)


func _find_previous_participant(
	previous: Array,
	participant_id: int,
	ai: bool
) -> Dictionary:

	for participant in previous:
		if int(
			participant.get("participant_id", -1)
		) != participant_id:
			continue

		if bool(
			participant.get("is_ai", false)
		) == ai:
			return participant

	return {}


func get_participant_count() -> int:
	return participants.size()


func get_participant(index: int) -> Dictionary:
	if index < 0 or index >= participants.size():
		return {}

	return participants[index]

func get_active_participants() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for participant in participants:
		if bool(participant.get("enabled", true)):
			result.append(participant)

	return result


func get_active_participant_count() -> int:

	var count := 0

	for participant in participants:

		if bool(
			participant.get(
				"enabled",
				true
			)
		):

			count += 1

	return count

func get_enabled_ai_count() -> int:
	var count := 0

	for participant in participants:
		if (
			bool(participant.get("is_ai", false))
			and bool(participant.get("enabled", true))
		):
			count += 1

	return count


# ================================================================
# LIVRÉES (MODÈLE + COULEUR)
# ================================================================

## Sur un écran commun (partagé ou élimination), deux voitures
## identiques seraient indiscernables : un couple modèle + couleur
## ne peut être utilisé que par un seul participant.
func requires_unique_liveries() -> bool:
	return not uses_split_screen()


func is_livery_taken(
	car_id: String,
	color_id: String,
	except_index: int
) -> bool:

	for i in range(participants.size()):
		if i == except_index:
			continue

		var other := participants[i]

		if not bool(other.get("enabled", true)):
			continue

		if (
			String(other.get("car_id", "")) == car_id
			and String(other.get("color_id", "")) == color_id
		):
			return true

	return false


## Première couleur libre pour ce modèle ("" si toutes sont prises).
func find_free_color(
	car_id: String,
	except_index: int,
	color_ids: Array
) -> String:

	for color_id in color_ids:
		if not is_livery_taken(car_id, String(color_id), except_index):
			return String(color_id)

	return ""


func has_duplicate_liveries() -> bool:
	for i in range(participants.size()):
		var participant := participants[i]

		if not bool(participant.get("enabled", true)):
			continue

		if is_livery_taken(
			String(participant.get("car_id", "")),
			String(participant.get("color_id", "")),
			i
		):
			return true

	return false


func is_car_selection_valid() -> bool:
	if requires_unique_liveries() and has_duplicate_liveries():
		return false

	var active_count := 0

	for participant in participants:
		if not bool(participant.get("enabled", true)):
			continue

		active_count += 1

		var car_id := String(
			participant.get("car_id", "")
		)

		var color_id := String(
			participant.get("color_id", "")
		)

		if not CarCatalog.has_car(car_id):
			return false

		if not ColorCatalog.has_color(color_id):
			return false

	# Au moins un participant doit courir.
	if active_count == 0:
		return false

	return true


# ================================================================
# COPIE
# ================================================================

func duplicate_config() -> RaceConfig:
	var copy := RaceConfig.new()

	copy.mode = mode
	copy.ai_difficulty = ai_difficulty
	copy.track = track
	copy.lap_count = lap_count
	copy.race_rules = race_rules
	copy.target_score = target_score
	copy.split_screen = split_screen
	copy.tire_wear = tire_wear
	copy.ghost_mode = ghost_mode

	copy.players = players.duplicate(true)
	copy.participants = participants.duplicate(true)

	return copy
