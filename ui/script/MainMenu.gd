extends Control

const RACE_SETUP_SCENE := "res://ui/scene/RaceSetup.tscn"
const CHAMPIONSHIP_SETUP_SCENE := "res://ui/scene/ChampionshipSetup.tscn"
const TIME_TRIAL_SETUP_SCENE := "res://ui/scene/TimeTrialSetup.tscn"
const LEADERBOARDS_SCENE := "res://ui/scene/LeaderboardsMenu.tscn"
const OPTIONS_SCENE := "res://ui/scene/Options.tscn"

@onready var single_race_button: Button = $MarginContainer/VBoxContainer/MenuContainer/SingleRaceButton
@onready var championship_button: Button = $MarginContainer/VBoxContainer/MenuContainer/ChampionshipButton
@onready var time_trial_button: Button = $MarginContainer/VBoxContainer/MenuContainer/TimeTrialButton
@onready var leaderboards_button: Button = $MarginContainer/VBoxContainer/MenuContainer/LeaderboardsButton
@onready var options_button: Button = $MarginContainer/VBoxContainer/MenuContainer/OptionsButton
@onready var quit_button: Button = $MarginContainer/VBoxContainer/MenuContainer/QuitButton
@onready var profile_label: Label = $MarginContainer/VBoxContainer/VBoxContainer/ProfileLabel

func _ready() -> void:
	_connect_signals()
	_update_profile_label()
	single_race_button.grab_focus()

func _update_profile_label() -> void:
	profile_label.text = "Pseudo : %s" % SaveManager.get_nickname()

func _connect_signals() -> void:
	single_race_button.pressed.connect(_on_single_race_pressed)
	championship_button.pressed.connect(_on_championship_pressed)
	time_trial_button.pressed.connect(_on_time_trial_pressed)
	leaderboards_button.pressed.connect(_on_leaderboards_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_single_race_pressed() -> void:
	NavigationManager.go_to(RACE_SETUP_SCENE)

func _on_championship_pressed() -> void:
	NavigationManager.go_to(CHAMPIONSHIP_SETUP_SCENE)

func _on_time_trial_pressed() -> void:
	NavigationManager.go_to(TIME_TRIAL_SETUP_SCENE)

func _on_leaderboards_pressed() -> void:
	NavigationManager.go_to(LEADERBOARDS_SCENE)

func _on_options_pressed() -> void:
	NavigationManager.go_to(OPTIONS_SCENE)

func _on_quit_pressed() -> void:
	get_tree().quit()
