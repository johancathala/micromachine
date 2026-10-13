
extends Node

# ============================================================
# RESSOURCES AUDIO : à affecter dans l'inspecteur
# ============================================================

@export_group("Musiques")
@export var music_menu: AudioStream
@export var music_race: AudioStream
@export var music_pause: AudioStream
@export var music_results: AudioStream

@export_group("Sons d'interface")
@export var sfx_click: AudioStream
@export var sfx_back: AudioStream
@export var sfx_confirm: AudioStream
@export var sfx_disabled: AudioStream

@export_group("Volume")
@export_range(-40.0, 6.0, 0.5)
var music_volume_db: float = -6.0

@export_range(-40.0, 6.0, 0.5)
var sfx_volume_db: float = -3.0

@export_group("Transitions")
@export_range(0.0, 3.0, 0.1)
var default_fade_duration: float = 0.5


# ============================================================
# NŒUDS AUDIO
# ============================================================

@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var music_player_secondary: AudioStreamPlayer = $MusicPlayerSecondary

@onready var sfx_player_1: AudioStreamPlayer = $SFXPlayer1
@onready var sfx_player_2: AudioStreamPlayer = $SFXPlayer2
@onready var sfx_player_3: AudioStreamPlayer = $SFXPlayer3
@onready var sfx_player_4: AudioStreamPlayer = $SFXPlayer4

var sfx_players: Array[AudioStreamPlayer] = []
var sfx_index: int = 0

var active_music_player: AudioStreamPlayer
var secondary_music_player: AudioStreamPlayer
var music_tween: Tween

var pause_override_active: bool = false
var saved_music_stream: AudioStream
var saved_music_position: float = 0.0


# ============================================================
# INITIALISATION
# ============================================================

func _ready() -> void:
	# Le gestionnaire doit fonctionner même pendant la pause.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Initialisation des lecteurs.
	sfx_players = [
		sfx_player_1,
		sfx_player_2,
		sfx_player_3,
		sfx_player_4
	]

	active_music_player = music_player
	secondary_music_player = music_player_secondary
	active_music_player.set

	for player in sfx_players:
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.bus = _get_audio_bus("SFX")

	for player in [music_player, music_player_secondary]:
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.bus = _get_audio_bus("Music")
		player.volume_db = -80.0

	bind_sound_btt()

func bind_sound_btt() -> void:
	# Connexion automatique des boutons existants et futurs.
	_bind_buttons_in_tree(get_tree().root)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)

func _get_audio_bus(bus_name: String) -> StringName:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return StringName(bus_name)

	return &"Master"


# ============================================================
# EFFETS SONORES
# ============================================================

func play_sfx(stream: AudioStream) -> void:
	if stream == null or sfx_players.is_empty():
		return

	var player: AudioStreamPlayer = sfx_players[sfx_index]

	sfx_index = (sfx_index + 1) % sfx_players.size()

	player.stop()
	player.stream = stream
	player.volume_db = sfx_volume_db
	player.play()


func play_click() -> void:
	play_sfx(sfx_click)


func play_back() -> void:
	play_sfx(sfx_back)


func play_confirm() -> void:
	play_sfx(sfx_confirm)


func play_disabled() -> void:
	play_sfx(sfx_disabled)


# ============================================================
# GESTION AUTOMATIQUE DES BOUTONS
#
# Par défaut : clic.
# Groupe "audio_back"    : son de retour.
# Groupe "audio_confirm" : son de validation.
# ============================================================

func _bind_buttons_in_tree(node: Node) -> void:
	if node is BaseButton:
		_bind_button(node as BaseButton)

	for child in node.get_children():
		_bind_buttons_in_tree(child)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_bind_button(node as BaseButton)


func _bind_button(button: BaseButton) -> void:
	if button.has_meta("audio_manager_bound"):
		return

	button.set_meta("audio_manager_bound", true)
	button.pressed.connect(_on_button_pressed.bind(button))


func _on_button_pressed(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return

	if button.is_in_group("audio_back"):
		play_back()
	elif button.is_in_group("audio_confirm"):
		play_confirm()
	else:
		play_click()


# ============================================================
# MUSIQUES
# ============================================================

func play_music(
	stream: AudioStream,
	fade_duration: float = -1.0,
	start_position: float = 0.0
) -> void:
	if stream == null:
		return

	if fade_duration < 0.0:
		fade_duration = default_fade_duration

	# Évite de relancer inutilement le morceau en cours.
	if active_music_player.stream == stream \
	and active_music_player.playing \
	and start_position <= 0.0:
		return

	_stop_music_tween()

	var outgoing: AudioStreamPlayer = active_music_player
	var incoming: AudioStreamPlayer = secondary_music_player

	incoming.stop()
	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play(maxf(0.0, start_position))

	# Inversion des lecteurs pour la prochaine transition.
	active_music_player = incoming
	secondary_music_player = outgoing

	if fade_duration <= 0.0:
		outgoing.stop()
		incoming.volume_db = music_volume_db
		return

	music_tween = create_tween()
	music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	music_tween.set_parallel(true)

	music_tween.tween_property(
		incoming,
		"volume_db",
		music_volume_db,
		fade_duration
	)

	if outgoing.playing:
		music_tween.tween_property(
			outgoing,
			"volume_db",
			-80.0,
			fade_duration
		)

		music_tween.chain().tween_callback(
			func() -> void:
				outgoing.stop()
		)


func _stop_music_tween() -> void:
	if music_tween != null and music_tween.is_running():
		music_tween.kill()

	music_tween = null


func play_menu_music() -> void:
	if not pause_override_active:
		play_music(music_menu)


func play_race_music() -> void:
	if not pause_override_active:
		play_music(music_race)


func play_results_music() -> void:
	if not pause_override_active:
		play_music(music_results)


func stop_music() -> void:
	_stop_music_tween()

	music_player.stop()
	music_player_secondary.stop()

	music_player.volume_db = -80.0
	music_player_secondary.volume_db = -80.0


# ============================================================
# MUSIQUE DE PAUSE
# ============================================================

func push_pause_music() -> void:
	if pause_override_active:
		return

	pause_override_active = true

	# Mémorise le morceau et sa position avant la pause.
	saved_music_stream = active_music_player.stream
	saved_music_position = active_music_player.get_playback_position()

	# Si aucune musique de pause n'est configurée,
	# la musique actuelle continue normalement.
	if music_pause != null:
		play_music(music_pause)


func pop_pause_music() -> void:
	if not pause_override_active:
		return

	pause_override_active = false

	if saved_music_stream != null:
		play_music(
			saved_music_stream,
			default_fade_duration,
			saved_music_position
		)
	else:
		stop_music()

	saved_music_stream = null
	saved_music_position = 0.0


# ============================================================
# VOLUME
# ============================================================

func set_music_volume(value_db: float) -> void:
	music_volume_db = clampf(value_db, -40.0, 6.0)

	if active_music_player.playing:
		active_music_player.volume_db = music_volume_db


func set_sfx_volume(value_db: float) -> void:
	sfx_volume_db = clampf(value_db, -40.0, 6.0)
