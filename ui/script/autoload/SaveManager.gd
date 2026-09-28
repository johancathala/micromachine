extends Node

# ============================================================
# PROFIL
# ============================================================

var profile: Dictionary = {
	"initialized": false,
	"nickname": ""
}

# ============================================================
# PLAYER NICKNAMES
# ============================================================

var player_nicknames: Dictionary = {
	"keyboard": "",
	"gamepads": {}
}

# ============================================================
# AUDIO
# ============================================================

var audio_settings: Dictionary = {
	"master_volume": 1.0,
	"music_volume": 1.0,
	"sfx_volume": 1.0
}


# ============================================================
# CONTROLES
# ============================================================

var control_settings: Dictionary = {
	"keyboard": {},
	"gamepads": {}
}


# ============================================================
# AFFICHAGE
# ============================================================

var display_settings: Dictionary = {
	"window_mode": DisplayServer.WINDOW_MODE_WINDOWED,
	"resolution": Vector2i(1920, 1080),
	"vsync": true,
	"ui_scale": "normal"
}

# ============================================================
# CONSTANTES
# ============================================================

const SAVE_PATH := "user://profile.cfg"

const DEFAULT_RESOLUTION := Vector2i(1920, 1080)

const DEFAULT_WINDOW_MODE := DisplayServer.WINDOW_MODE_WINDOWED

const DEFAULT_VSYNC := true

const DEFAULT_UI_SCALE := "normal"

# ============================================================
# INITIALISATION
# ============================================================

func initialize() -> void:
	
	_ensure_profile_structure()
	_ensure_audio_structure()
	_ensure_control_structure()
	_ensure_display_structure()

func is_first_launch() -> bool:
	if profile.get("nickname", "") == "":
		return true
	else:
		return false
	

# ============================================================
# CHARGEMENT / SAUVEGARDE
# ============================================================

func load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		initialize()
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)

	if file == null:
		initialize()
		return

	var content := file.get_as_text()
	file.close()

	var json := JSON.new()

	if json.parse(content) != OK:
		initialize()
		return

	var data = json.data

	if not data is Dictionary:
		initialize()
		return

	# --------------------------------------------------------
	# Profil
	# --------------------------------------------------------

	if data.has("profile") and data["profile"] is Dictionary:
		profile = data["profile"].duplicate(true)

	# --------------------------------------------------------
	# Audio
	# --------------------------------------------------------

	if data.has("audio") and data["audio"] is Dictionary:
		audio_settings = data["audio"].duplicate(true)

	# --------------------------------------------------------
	# Contrôles
	# --------------------------------------------------------

	if data.has("controls") and data["controls"] is Dictionary:
		control_settings = data["controls"].duplicate(true)

	# --------------------------------------------------------
	# Affichage
	# --------------------------------------------------------

	if data.has("display") and data["display"] is Dictionary:
		display_settings = data["display"].duplicate(true)

	# --------------------------------------------------------
	# Complète les éventuelles données manquantes
	# --------------------------------------------------------

	initialize()


func save_profile() -> void:
	_ensure_profile_structure()
	_ensure_player_nicknames_structure()
	_ensure_audio_structure()
	_ensure_control_structure()
	_ensure_display_structure()

	var data := {
		"profile": profile,
		"audio": audio_settings,
		"controls": control_settings,
		"display": display_settings
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)

	if file == null:
		push_error("Impossible d'ouvrir le fichier de sauvegarde : " + SAVE_PATH)
		return

	file.store_string(JSON.stringify(data, "\t"))
	file.close()


# ============================================================
# PROFIL
# ============================================================

func get_profile() -> Dictionary:
	_ensure_profile_structure()
	return profile


func get_nickname() -> String:
	_ensure_profile_structure()
	return str(profile.get("nickname", ""))


func set_nickname(nickname: String) -> void:
	_ensure_profile_structure()

	profile["nickname"] = nickname

	save_profile()

func get_player_nickname(
	device_type: String,
	device_id: int = -1
) -> String:

	_ensure_player_nicknames_structure()

	if device_type == "keyboard":
		return str(player_nicknames.get("keyboard", ""))

	if device_type == "gamepad":
		var gamepads: Dictionary = player_nicknames["gamepads"]
		return str(gamepads.get(str(device_id), ""))

	return ""

func set_player_nickname(
	device_type: String,
	device_id: int,
	nickname: String
) -> void:

	_ensure_player_nicknames_structure()

	if device_type == "keyboard":
		player_nicknames["keyboard"] = nickname

	elif device_type == "gamepad":
		var gamepads: Dictionary = player_nicknames["gamepads"]

		gamepads[str(device_id)] = nickname

		player_nicknames["gamepads"] = gamepads

	save_profile()


func is_profile_initialized() -> bool:
	_ensure_profile_structure()
	return bool(profile.get("initialized", false))


func set_profile_initialized(value: bool) -> void:
	_ensure_profile_structure()

	profile["initialized"] = value

	save_profile()


func _ensure_profile_structure() -> void:
	if not profile is Dictionary:
		profile = {}

	if not profile.has("initialized"):
		profile["initialized"] = false

	if not profile.has("nickname"):
		profile["nickname"] = ""

func _ensure_player_nicknames_structure() -> void:
	if not player_nicknames.has("keyboard"):
		player_nicknames["keyboard"] = ""

	if not player_nicknames.has("gamepads"):
		player_nicknames["gamepads"] = {}


# ============================================================
# AUDIO
# ============================================================

func get_audio_setting(audio_name: String, default_value = null):
	_ensure_audio_structure()

	return audio_settings.get(audio_name, default_value)


func set_audio_setting(audio_name: String, value) -> void:
	_ensure_audio_structure()

	audio_settings[audio_name] = value

	save_profile()


func reset_audio_settings() -> void:
	audio_settings = {
		"master_volume": 1.0,
		"music_volume": 1.0,
		"sfx_volume": 1.0
	}

	save_profile()


func _ensure_audio_structure() -> void:
	if not audio_settings is Dictionary:
		audio_settings = {}

	if not audio_settings.has("master_volume"):
		audio_settings["master_volume"] = 1.0

	if not audio_settings.has("music_volume"):
		audio_settings["music_volume"] = 1.0

	if not audio_settings.has("sfx_volume"):
		audio_settings["sfx_volume"] = 1.0


# ============================================================
# CONTROLES
# ============================================================

func get_keyboard_binding(action: String, default_value = null):
	_ensure_control_structure()

	return control_settings["keyboard"].get(
		action,
		default_value
	)


func set_keyboard_binding(action: String, event_data) -> void:
	_ensure_control_structure()

	control_settings["keyboard"][action] = event_data

	save_profile()


func reset_keyboard_bindings(default_bindings: Dictionary) -> void:
	_ensure_control_structure()

	control_settings["keyboard"] = default_bindings.duplicate(true)

	save_profile()


func get_gamepad_binding(
	device_id: int,
	action: String,
	default_value = null
):
	_ensure_control_structure()

	var device_key := str(device_id)

	if not control_settings["gamepads"].has(device_key):
		return default_value

	return control_settings["gamepads"][device_key].get(
		action,
		default_value
	)


func set_gamepad_binding(
	device_id: int,
	action: String,
	event_data
) -> void:
	_ensure_control_structure()

	var device_key := str(device_id)

	if not control_settings["gamepads"].has(device_key):
		control_settings["gamepads"][device_key] = {}

	control_settings["gamepads"][device_key][action] = event_data

	save_profile()


func reset_gamepad_bindings(
	device_id: int,
	default_bindings: Dictionary
) -> void:
	_ensure_control_structure()

	var device_key := str(device_id)

	control_settings["gamepads"][device_key] = (
		default_bindings.duplicate(true)
	)

	save_profile()


func get_gamepad_settings(device_id: int) -> Dictionary:
	_ensure_control_structure()

	var device_key := str(device_id)

	if not control_settings["gamepads"].has(device_key):
		return {}

	return control_settings["gamepads"][device_key]


func clear_gamepad_settings(device_id: int) -> void:
	_ensure_control_structure()

	var device_key := str(device_id)

	control_settings["gamepads"].erase(device_key)

	save_profile()


func _ensure_control_structure() -> void:
	if not control_settings is Dictionary:
		control_settings = {}

	if not control_settings.has("keyboard"):
		control_settings["keyboard"] = {}

	if not control_settings["keyboard"] is Dictionary:
		control_settings["keyboard"] = {}

	if not control_settings.has("gamepads"):
		control_settings["gamepads"] = {}

	if not control_settings["gamepads"] is Dictionary:
		control_settings["gamepads"] = {}


# ============================================================
# AFFICHAGE - ACCES AUX PARAMETRES
# ============================================================

func get_display_setting(display_name: String, default_value = null):
	_ensure_display_structure()

	return display_settings.get(
		display_name,
		default_value
	)


func set_display_setting(display_name: String, value) -> void:
	_ensure_display_structure()

	display_settings[display_name] = value

	save_profile()


func reset_display_settings() -> void:
	display_settings = {
		"window_mode": DEFAULT_WINDOW_MODE,
		"resolution": DEFAULT_RESOLUTION,
		"vsync": DEFAULT_VSYNC,
		"ui_scale": DEFAULT_UI_SCALE
	}

	save_profile()

	apply_display_settings()


func _ensure_display_structure() -> void:
	if not display_settings is Dictionary:
		display_settings = {}

	if not display_settings.has("window_mode"):
		display_settings["window_mode"] = DEFAULT_WINDOW_MODE

	if not display_settings.has("resolution"):
		display_settings["resolution"] = DEFAULT_RESOLUTION

	# JSON transforme les Vector2i en tableau.
	# On reconvertit donc ici les anciennes sauvegardes.
	if display_settings["resolution"] is Array:
		var resolution_array: Array = display_settings["resolution"]

		if resolution_array.size() >= 2:
			display_settings["resolution"] = Vector2i(
				int(resolution_array[0]),
				int(resolution_array[1])
			)
		else:
			display_settings["resolution"] = DEFAULT_RESOLUTION

	if not display_settings["resolution"] is Vector2i:
		display_settings["resolution"] = DEFAULT_RESOLUTION

	if not display_settings.has("vsync"):
		display_settings["vsync"] = DEFAULT_VSYNC

	if not display_settings.has("ui_scale"):
		display_settings["ui_scale"] = DEFAULT_UI_SCALE


# ============================================================
# AFFICHAGE - APPLICATION COMPLETE
# ============================================================

func apply_display_settings() -> void:
	_ensure_display_structure()

	var mode: DisplayServer.WindowMode = get_display_setting(
			"window_mode",
			DEFAULT_WINDOW_MODE
		)

	var resolution: Vector2i = get_display_setting(
		"resolution",
		DEFAULT_RESOLUTION
	)

	var vsync: bool = bool(
		get_display_setting(
			"vsync",
			DEFAULT_VSYNC
		)
	)

	var ui_scale: String = str(
		get_display_setting(
			"ui_scale",
			DEFAULT_UI_SCALE
		)
	)

	_apply_window_mode(mode, resolution)
	_apply_vsync(vsync)
	_apply_ui_scale(ui_scale)


# ============================================================
# AFFICHAGE - MODE DE FENETRE
# ============================================================

func _apply_window_mode(
	mode: DisplayServer.WindowMode,
	resolution: Vector2i
) -> void:

	match mode:

		DisplayServer.WINDOW_MODE_WINDOWED:
			# En mode fenêtré, la résolution correspond
			# directement à la taille de la fenêtre.

			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_WINDOWED
			)

			DisplayServer.window_set_size(resolution)


		DisplayServer.WINDOW_MODE_FULLSCREEN:
			# Plein écran fenêtré / borderless.
			#
			# La résolution choisie n'est PAS appliquée
			# au moniteur. Le jeu utilise la résolution
			# native actuelle du moniteur.

			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_FULLSCREEN
			)


		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			# Pour l'exclusif, on passe d'abord en fenêtré,
			# on définit la résolution, puis on repasse
			# en exclusif.

			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_WINDOWED
			)

			DisplayServer.window_set_size(resolution)

			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			)


		_:
			# Sécurité en cas de valeur invalide.

			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_WINDOWED
			)

			DisplayServer.window_set_size(
				DEFAULT_RESOLUTION
			)


# ============================================================
# AFFICHAGE - V-SYNC
# ============================================================

func _apply_vsync(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED
		)
	else:
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_DISABLED
		)


# ============================================================
# AFFICHAGE - ECHELLE UI
# ============================================================

func _apply_ui_scale(scale_name: String) -> void:
	var scale := 1.0

	match scale_name:
		"small":
			scale = 0.85

		"normal":
			scale = 1.0

		"large":
			scale = 1.15

		_:
			scale = 1.0

	get_tree().root.content_scale_factor = scale
