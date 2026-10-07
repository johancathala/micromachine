extends Control

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
	NavigationManager.go("RaceSetup")

func _on_championship_pressed() -> void:
	NavigationManager.go("ChampionshipSetup")

func _on_time_trial_pressed() -> void:
	NavigationManager.go("TimeTrialSetup")

func _on_leaderboards_pressed() -> void:
	NavigationManager.go("LeaderboardsMenu")

func _on_options_pressed() -> void:
	NavigationManager.go("Options")

func _on_quit_pressed() -> void:
	get_tree().quit()
