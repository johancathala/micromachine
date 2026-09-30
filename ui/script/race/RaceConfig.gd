extends RefCounted
class_name RaceConfig

const TOTAL_RACE_SLOTS := 8
const MAX_HUMAN_PLAYERS := 8


var mode: GameManager.GameMode = GameManager.GameMode.SINGLE_RACE

var ai_difficulty: int = 0
var track_id: String = ""
var lap_count: int = 3

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
	return TOTAL_RACE_SLOTS - get_human_player_count()


func is_full() -> bool:
	return get_human_player_count() >= MAX_HUMAN_PLAYERS


func has_keyboard_player() -> bool:
	for player in players:
		if str(player.get("device_type", "")) == "keyboard":
			return true

	return false


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

	if track_id.is_empty():
		return false

	if lap_count <= 0:
		return false

	return true


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

	for i in range(ai_count):
		var participant_id := players.size() + i

		var participant := {
			"participant_id": participant_id,
			"player_id": -1,
			"device_type": "ai",
			"device_id": -1,
			"nickname": "IA %d" % (i + 1),
			"is_ai": true
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


func is_car_selection_valid() -> bool:
	if participants.size() != TOTAL_RACE_SLOTS:
		return false

	var used_colors: Dictionary = {}

	for participant in participants:
		var car_id := str(participant.get("car_id", ""))
		var color_id := str(participant.get("color_id", ""))

		if car_id.is_empty():
			return false

		if color_id.is_empty():
			return false

		if used_colors.has(color_id):
			return false

		used_colors[color_id] = true

	return true


# ================================================================
# COPIE
# ================================================================

func duplicate_config() -> RaceConfig:
	var copy := RaceConfig.new()

	copy.mode = mode
	copy.ai_difficulty = ai_difficulty
	copy.track_id = track_id
	copy.lap_count = lap_count

	copy.players = players.duplicate(true)
	copy.participants = participants.duplicate(true)

	return copy
