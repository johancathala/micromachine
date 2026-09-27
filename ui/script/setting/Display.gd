extends Control

const DEFAULT_RESOLUTION := Vector2i(1920, 1080)

const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160)
]

const UI_SCALES := {
	"small": 0.85,
	"normal": 1.0,
	"large": 1.15
}

@onready var mode_option: OptionButton = (
	$MarginContainer/VBoxContainer/DisplayContainer/ModeRow/ModeOption
)

@onready var resolution_option: OptionButton = (
	$MarginContainer/VBoxContainer/DisplayContainer/ResolutionRow/ResolutionOption
)

@onready var vsync_option: OptionButton = (
	$MarginContainer/VBoxContainer/DisplayContainer/VSyncRow/VSyncOption
)

@onready var ui_scale_option: OptionButton = (
	$MarginContainer/VBoxContainer/DisplayContainer/UIScaleRow/UIScaleOption
)

@onready var reset_button: Button = (
	$MarginContainer/VBoxContainer/Footer/ResetButton
)

@onready var back_button: Button = (
	$MarginContainer/VBoxContainer/Footer/BackButton
)


func _ready() -> void:
	_setup_mode_options()
	_setup_resolution_options()
	_setup_vsync_options()
	_setup_ui_scale_options()

	_load_settings()
	_connect_signals()

	back_button.grab_focus()


# ============================================================
# INITIALISATION DES LISTES
# ============================================================

func _setup_mode_options() -> void:
	mode_option.clear()

	mode_option.add_item("Fenêtré")
	mode_option.set_item_metadata(0, DisplayServer.WINDOW_MODE_WINDOWED)

	mode_option.add_item("Plein écran")
	mode_option.set_item_metadata(1, DisplayServer.WINDOW_MODE_FULLSCREEN)


func _setup_resolution_options() -> void:
	resolution_option.clear()

	for resolution in RESOLUTIONS:
		var index := resolution_option.item_count

		resolution_option.add_item(
			"%d × %d" % [
				resolution.x,
				resolution.y
			]
		)

		resolution_option.set_item_metadata(
			index,
			resolution
		)


func _setup_vsync_options() -> void:
	vsync_option.clear()

	vsync_option.add_item("Désactivée")
	vsync_option.set_item_metadata(
		0,
		false
	)

	vsync_option.add_item("Activée")
	vsync_option.set_item_metadata(
		1,
		true
	)


func _setup_ui_scale_options() -> void:
	ui_scale_option.clear()

	ui_scale_option.add_item("Petite")
	ui_scale_option.set_item_metadata(
		0,
		"small"
	)

	ui_scale_option.add_item("Normale")
	ui_scale_option.set_item_metadata(
		1,
		"normal"
	)

	ui_scale_option.add_item("Grande")
	ui_scale_option.set_item_metadata(
		2,
		"large"
	)


# ============================================================
# CHARGEMENT
# ============================================================

func _load_settings() -> void:
	var mode = SaveManager.get_display_setting(
		"window_mode",
		DisplayServer.WINDOW_MODE_WINDOWED
	)

	var resolution: Vector2i = SaveManager.get_display_setting(
		"resolution",
		DEFAULT_RESOLUTION
	)

	var vsync = SaveManager.get_display_setting(
		"vsync",
		true
	)

	var ui_scale = SaveManager.get_display_setting(
		"ui_scale",
		"normal"
	)

	_select_mode(mode)
	_select_resolution(resolution)
	_select_vsync(vsync)
	_select_ui_scale(ui_scale)

	_apply_all()


# ============================================================
# SIGNALS
# ============================================================

func _connect_signals() -> void:
	back_button.pressed.connect(
		_on_back_pressed
	)
	
	reset_button.pressed.connect(
		_on_reset_pressed
	)

	mode_option.item_selected.connect(
		_on_mode_selected
	)

	resolution_option.item_selected.connect(
		_on_resolution_selected
	)

	vsync_option.item_selected.connect(
		_on_vsync_selected
	)

	ui_scale_option.item_selected.connect(
		_on_ui_scale_selected
	)


# ============================================================
# MODE D'AFFICHAGE
# ============================================================

func _on_mode_selected(index: int) -> void:
	var mode = mode_option.get_item_metadata(index)

	SaveManager.set_display_setting(
		"window_mode",
		mode
	)

	_apply_window_mode(mode)

	_update_resolution_state()


func _apply_window_mode(mode: int) -> void:
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		# On revient d'abord en fenêtré.
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED
		)

		# Puis on applique la résolution de la fenêtre.
		var resolution: Vector2i = SaveManager.get_display_setting(
			"resolution",
			DEFAULT_RESOLUTION
		)

		DisplayServer.window_set_size(resolution)

	elif mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		# Plein écran sans changer le mode vidéo du moniteur.
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN
		)

	elif mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		# Pour un jeu, ce mode permet le vrai plein écran exclusif.
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		)

		var resolution: Vector2i = SaveManager.get_display_setting(
			"resolution",
			DEFAULT_RESOLUTION
		)

		DisplayServer.window_set_size(resolution)


# ============================================================
# RESOLUTION
# ============================================================

func _on_resolution_selected(index: int) -> void:
	var resolution: Vector2i = (
		resolution_option.get_item_metadata(index)
	)

	SaveManager.set_display_setting(
		"resolution",
		resolution
	)

	_apply_resolution(resolution)


func _apply_resolution(
	resolution: Vector2i
) -> void:

	var mode := DisplayServer.window_get_mode()

	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(
			resolution
		)

	elif mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		# En plein écran exclusif, on repasse par la
		# résolution souhaitée puis on réactive le mode.
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED
		)

		DisplayServer.window_set_size(
			resolution
		)

		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		)

	# En WINDOW_MODE_FULLSCREEN :
	# la résolution du bureau/moniteur ne doit pas être
	# modifiée. Le jeu occupe l'écran disponible.


# ============================================================
# VSYNC
# ============================================================

func _on_vsync_selected(index: int) -> void:
	var enabled: bool = (
		vsync_option.get_item_metadata(index)
	)

	SaveManager.set_display_setting(
		"vsync",
		enabled
	)

	_apply_vsync(enabled)


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
# ECHELLE UI
# ============================================================

func _on_ui_scale_selected(index: int) -> void:
	var scale_id: String = (
		ui_scale_option.get_item_metadata(index)
	)

	SaveManager.set_display_setting(
		"ui_scale",
		scale_id
	)

	_apply_ui_scale(scale_id)


func _apply_ui_scale(scale_id: String) -> void:
	var scale_value: float = UI_SCALES.get(
		scale_id,
		1.0
	)

	get_tree().root.content_scale_factor = (
		scale_value
	)


# ============================================================
# APPLICATION COMPLETE
# ============================================================

func _apply_all() -> void:
	var mode = SaveManager.get_display_setting(
		"window_mode",
		DisplayServer.WINDOW_MODE_WINDOWED
	)

	var resolution: Vector2i = SaveManager.get_display_setting(
		"resolution",
		DEFAULT_RESOLUTION
	)

	var vsync = SaveManager.get_display_setting(
		"vsync",
		true
	)

	var ui_scale = SaveManager.get_display_setting(
		"ui_scale",
		"normal"
	)

	_apply_window_mode(mode)
	_apply_resolution(resolution)
	_apply_vsync(vsync)
	_apply_ui_scale(ui_scale)

	_update_resolution_state()


# ============================================================
# ETAT DE LA RESOLUTION
# ============================================================

func _update_resolution_state() -> void:
	var mode := DisplayServer.window_get_mode()

	resolution_option.disabled = (
		mode == DisplayServer.WINDOW_MODE_FULLSCREEN
	)


# ============================================================
# SELECTION DES OPTIONS
# ============================================================

func _select_mode(mode: int) -> void:
	for i in mode_option.item_count:
		if mode_option.get_item_metadata(i) == mode:
			mode_option.select(i)
			return


func _select_resolution(resolution: Vector2i) -> void:
	for i in resolution_option.item_count:
		var value: Vector2i = (
			resolution_option.get_item_metadata(i)
		)

		if value == resolution:
			resolution_option.select(i)
			return

	# Résolution inconnue : on sélectionne 1920x1080.
	_select_resolution(DEFAULT_RESOLUTION)


func _select_vsync(enabled: bool) -> void:
	for i in vsync_option.item_count:
		if vsync_option.get_item_metadata(i) == enabled:
			vsync_option.select(i)
			return


func _select_ui_scale(scale_id: String) -> void:
	for i in ui_scale_option.item_count:
		if ui_scale_option.get_item_metadata(i) == scale_id:
			ui_scale_option.select(i)
			return


# ============================================================
# RESET
# ============================================================

func _on_reset_pressed() -> void:
	SaveManager.set_display_setting(
		"window_mode",
		DisplayServer.WINDOW_MODE_WINDOWED
	)

	SaveManager.set_display_setting(
		"resolution",
		DEFAULT_RESOLUTION
	)

	SaveManager.set_display_setting(
		"vsync",
		true
	)

	SaveManager.set_display_setting(
		"ui_scale",
		"normal"
	)

	_select_mode(
		DisplayServer.WINDOW_MODE_WINDOWED
	)

	_select_resolution(
		DEFAULT_RESOLUTION
	)

	_select_vsync(true)
	_select_ui_scale("normal")

	_apply_all()


# ============================================================
# RETOUR
# ============================================================

func _on_back_pressed() -> void:
	NavigationManager.go_back()
