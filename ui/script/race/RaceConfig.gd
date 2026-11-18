extends RefCounted
class_name RaceConfig

const TOTAL_RACE_SLOTS := 8
const MAX_HUMAN_PLAYERS := 8

# Règles de la partie.
enum RaceRules {
	# Course classique au nombre de tours.
	CLASSIC,
	# Élimination (écran partagé, joueurs et IA) :
	# un joueur qui sort de l'écran explose. Quand il ne reste qu'un
	# joueur, la manche est terminée, les points sont distribués et
	# la course repart en grille inversée à la position du leader.
	ELIMINATION,
	# Contre-la-montre : un seul joueur, sans IA, contre le fantôme de
	# son meilleur tour (un fantôme par circuit et par voiture).
	TIME_TRIAL
}

const ELIMINATION_MIN_PLAYERS := 2
const DEFAULT_TARGET_SCORE := 20

# Pilote d'une IA : un des trois niveaux, ou un fantôme (le meilleur
# fantôme valide de sa voiture sur le circuit choisi ensuite).
enum AIPilot {
	NOVICE,
	MEDIUM,
	EXPERT,
	GHOST
}

const AI_PILOT_NAMES := ["Novice", "Moyen", "Expert", "Fantôme"]

# Dernière composition des IA, reprise d'une course à l'autre.
static var last_ai_slots: Array[Dictionary] = []
static var last_ai_difficulty: int = AIPilot.MEDIUM


var mode: GameManager.GameMode = GameManager.GameMode.SINGLE_RACE

# Niveau proposé pour les IA ajoutées (écran des IA).
var ai_difficulty: int = AIPilot.MEDIUM
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

# IA engagées (écran des IA), dans l'ordre. Chacune : {"pilot": AIPilot,
# "style": identifiant AIStyle, "car_id": String, "color_id": String,
# "name" (facultatif : nom saisi, prioritaire sur celui du style)}.
var ai_slots: Array[Dictionary] = []

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


func _init() -> void:
	ai_slots = last_ai_slots.duplicate(true)
	ai_difficulty = last_ai_difficulty


## Les IA courent en course classique et en élimination (pas en
## contre-la-montre : seul contre son fantôme).
func allows_ai() -> bool:
	return is_classic() or is_elimination()


## Places disponibles pour les IA.
func get_max_ai_count() -> int:
	if not allows_ai():
		return 0

	return maxi(TOTAL_RACE_SLOTS - get_human_player_count(), 0)


## Mémorise la composition des IA pour les prochaines courses.
func remember_ai_slots() -> void:
	last_ai_slots = ai_slots.duplicate(true)
	last_ai_difficulty = ai_difficulty


## Niveau de conduite réel d'une IA : un pilote fantôme roule en
## Expert tant que la conduite des fantômes n'existe pas.
static func get_ai_difficulty(pilot: int) -> int:
	if pilot == AIPilot.GHOST:
		return AIPilot.EXPERT

	return clampi(pilot, AIPilot.NOVICE, AIPilot.EXPERT)


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
	if not are_players_valid():
		return false

	if track.is_empty():
		return false

	if lap_count <= 0:
		return false

	if is_elimination():
		if target_score <= 0:
			return false

		# Au moins deux voitures (joueurs et IA).
		if players.size() + mini(ai_slots.size(), get_max_ai_count()) < ELIMINATION_MIN_PLAYERS:
			return false

	return true


## Nombre de joueurs conforme au mode (écran des joueurs, avant le
## choix du circuit).
func are_players_valid() -> bool:
	if players.is_empty() or players.size() > MAX_HUMAN_PLAYERS:
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

		# La voiture choisie par le joueur est conservée dans sa fiche ;
		# l'ancien participant ne sert que s'il n'en a pas (sinon un
		# départ de joueur décalerait les voitures des autres).
		if not old.is_empty() and not participant.has("car_id"):
			if old.has("car_id"):
				participant["car_id"] = old["car_id"]

			if old.has("color_id"):
				participant["color_id"] = old["color_id"]

		participants.append(participant)

	# IA de l'écran des IA (pas en contre-la-montre : seul contre son
	# fantôme).
	var ai_count := mini(ai_slots.size(), get_max_ai_count())

	# Les IA portent le nom de leur style, numéroté s'il y a des doublons.
	var style_totals: Dictionary = {}
	var style_seen: Dictionary = {}

	for i in range(ai_count):
		# Un nom saisi ne compte pas dans la numérotation des styles.
		if not String(ai_slots[i].get("name", "")).is_empty():
			continue

		var id := String(ai_slots[i].get("style", AIStyle.DEFAULT_ID))
		style_totals[id] = int(style_totals.get(id, 0)) + 1

	for i in range(ai_count):
		var slot := ai_slots[i]
		var pilot := int(slot.get("pilot", ai_difficulty))

		participants.append({
			"participant_id": players.size() + i,
			"player_id": -1,
			"device_type": "ai",
			"device_id": -1,
			"nickname": (
				String(slot["name"]) if not String(slot.get("name", "")).is_empty()
				else _ai_name(String(slot.get("style", AIStyle.DEFAULT_ID)), style_totals, style_seen)
			),
			"is_ai": true,
			"enabled": true,
			"ai_pilot": pilot,
			"ai_difficulty": get_ai_difficulty(pilot),
			"ai_style": String(slot.get("style", AIStyle.DEFAULT_ID)),
			"car_id": String(slot.get("car_id", "")),
			"color_id": String(slot.get("color_id", ""))
		})

	_resolve_ai_liveries()


## Nom d'une IA : le pilote de son style (« Régis »), numéroté si
## plusieurs IA ont le même (« Régis 1 », « Régis 2 »).
func _ai_name(style_id: String, totals: Dictionary, seen: Dictionary) -> String:
	var name := String(AIStyle.get_style(style_id)["driver"])

	if int(totals.get(style_id, 0)) <= 1:
		return name

	seen[style_id] = int(seen.get(style_id, 0)) + 1
	return "%s %d" % [name, seen[style_id]]


## Les IA cèdent leur livrée : une IA dont la voiture ou la couleur
## manque, ou est déjà prise par un participant précédent (joueurs
## d'abord), reçoit une couleur libre de son modèle, sinon d'un autre.
## Le choix est recopié dans `ai_slots`.
func _resolve_ai_liveries() -> void:
	var color_ids: Array = []

	for color_data in ColorCatalog.get_colors():
		color_ids.append(String(color_data["id"]))

	var cars := CarCatalog.get_cars()
	var slot_index := 0

	for i in range(participants.size()):
		var participant := participants[i]

		if not bool(participant.get("is_ai", false)):
			continue

		var car_id := String(participant.get("car_id", ""))
		var color_id := String(participant.get("color_id", ""))

		if (
			not CarCatalog.has_car(car_id)
			or not color_ids.has(color_id)
			or _livery_used_before(car_id, color_id, i)
		):
			var candidates: Array[String] = []

			if CarCatalog.has_car(car_id):
				candidates.append(car_id)

			for car in cars:
				candidates.append(car.id)

			for candidate in candidates:
				var free := ""

				for id in color_ids:
					if not _livery_used_before(candidate, id, i):
						free = id
						break

				if not free.is_empty():
					car_id = candidate
					color_id = free
					break

			participant["car_id"] = car_id
			participant["color_id"] = color_id
			participants[i] = participant

		if slot_index < ai_slots.size():
			ai_slots[slot_index]["car_id"] = car_id
			ai_slots[slot_index]["color_id"] = color_id

		slot_index += 1


func _livery_used_before(car_id: String, color_id: String, index: int) -> bool:
	for i in range(index):
		var other := participants[i]

		if String(other.get("car_id", "")) == car_id and String(other.get("color_id", "")) == color_id:
			return true

	return false


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

## Deux voitures identiques seraient indiscernables sur un écran
## commun : un couple modèle + couleur ne sert qu'à un participant.
## Les livrées sont choisies avant l'affichage (partagé ou splitté,
## réglé sur l'écran du circuit) : elles sont donc toujours uniques.
func requires_unique_liveries() -> bool:
	return true


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
	copy.ai_slots = ai_slots.duplicate(true)

	copy.players = players.duplicate(true)
	copy.participants = participants.duplicate(true)

	return copy
