extends Control

# ============================================================
# MODE DE JEU (premier écran de la course simple)
# ============================================================
#
# Parcours : Mode → Joueurs → IA (course classique) → Circuit → Course.
# Le mode vient en premier : il décide s'il y a des IA (course
# classique) et des fantômes (contre-la-montre).
# ============================================================

const MODES := [
	{
		"rules": RaceConfig.RaceRules.CLASSIC,
		"title": "COURSE CLASSIQUE",
		"text": "Contre des IA, au nombre de tours"
	},
	{
		"rules": RaceConfig.RaceRules.ELIMINATION,
		"title": "ÉLIMINATION",
		"text": "%d joueurs minimum : qui sort de l'écran explose" % RaceConfig.ELIMINATION_MIN_PLAYERS
	},
	{
		"rules": RaceConfig.RaceRules.TIME_TRIAL,
		"title": "CONTRE-LA-MONTRE",
		"text": "Un seul joueur, contre son fantôme"
	}
]

var race_config: RaceConfig

@onready var mode_list: VBoxContainer = $MarginContainer/VBoxContainer/Modes
@onready var back_button: Button = $MarginContainer/VBoxContainer/Footer/BackButton
@onready var focus_manager: MenuFocusManager = $MenuFocusManager


func _ready() -> void:
	race_config = GameManager.get_pending_race_config()

	if race_config == null:
		race_config = RaceConfig.new()
		race_config.mode = GameManager.GameMode.SINGLE_RACE

	var buttons: Array[Control] = []
	var current: Button = null

	for mode in MODES:
		var button := Button.new()
		button.text = "%s\n%s" % [mode["title"], mode["text"]]
		button.custom_minimum_size = Vector2(0, 140)
		button.focus_mode = Control.FOCUS_ALL
		button.add_to_group("audio_confirm")
		button.pressed.connect(_on_mode_pressed.bind(mode["rules"]))
		mode_list.add_child(button)
		buttons.append(button)

		if mode["rules"] == race_config.race_rules:
			current = button

	buttons.append(back_button)
	focus_manager.set_vertical_navigation(buttons)
	back_button.pressed.connect(_on_back_pressed)
	AudioManager.bind_sound_btt()

	focus_manager.set_focus.call_deferred(current if current != null else buttons[0])


func _on_mode_pressed(rules: RaceConfig.RaceRules) -> void:
	race_config.race_rules = rules
	GameManager.set_pending_race_config(race_config)
	NavigationManager.go("CarSelection")


func _on_back_pressed() -> void:
	GameManager.clear_pending_race_config()
	NavigationManager.go_back_menu()
