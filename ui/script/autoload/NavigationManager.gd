extends Node

var navigation_layer: Control
var current_screen: Control
var history: Array[String] = []

const SCENES: Dictionary = {
	"Audio" : "res://ui/scene/Audio.tscn",
	"CarSelection" : "res://ui/scene/CarSelection.tscn",
	"ControlBindingRow" : "res://ui/scene/ControlBindingRow.tscn",
	"Controls" : "res://ui/scene/Controls.tscn",
	"Display" : "res://ui/scene/Display.tscn",
	"FirstLaunchScreen" : "res://ui/scene/FirstLaunchScreen.tscn",
	"Main" : "res://ui/scene/Main.tscn",
	"MainMenu" : "res://ui/scene/MainMenu.tscn",
	"Options" : "res://ui/scene/Options.tscn",
	"PlayerSlot" : "res://ui/scene/PlayerSlot.tscn",
	"Profile" : "res://ui/scene/Profile.tscn",
	"RaceRecap" : "res://ui/scene/RaceRecap.tscn",
	"RaceResultRow" : "res://ui/scene/RaceResultRow.tscn",
	"RaceSetup" : "res://ui/scene/RaceSetup.tscn",
	"StartupScreen" : "res://ui/scene/StartupScreen.tscn",
	"PauseOverlay" : "res://ui/overlay/PauseOverlay.tscn",
	"PlayerJoinOverlay" : "res://ui/overlay/PlayerJoinOverlay.tscn",
	"Race" : "res://level/scene/Race.tscn",
	"RaceController" : "res://level/scene/RaceController.tscn",
	"RaceHUD" : "res://level/scene/RaceHUD.tscn",
	"RaceWorld" : "res://level/scene/RaceWorld.tscn",
	"RaceParticipantHUD" : "res://level/scene/RaceParticipantHUD.tscn",
	"RaceStartLights" : "res://level/scene/RaceStartLights.tscn",
	"RaceStartLight" : "res://level/scene/RaceStartLight.tscn",
	"Car" : "res://perso/car/Car.tscn",
	"SkidMarks" : "res://perso/car/SkidMarks.tscn"
}

func setup(layer: Control) -> void:
	navigation_layer = layer

func get_scene(scene: String) -> String:
	return SCENES.get(scene)

func go(scene: String, add_to_history: bool = true) -> void:
	go_to(SCENES.get(scene), add_to_history)
	

func go_to(scene_path: String, add_to_history: bool = true) -> void:
	if navigation_layer == null:
		push_error("NavigationManager: navigation layer non configuré.")
		return

	if add_to_history and current_screen != null:
		history.append(current_screen.scene_file_path)

	if current_screen != null:
		current_screen.queue_free()
		current_screen = null

	var scene: PackedScene = load(scene_path)

	if scene == null:
		push_error("Impossible de charger la scène : " + scene_path)
		return

	current_screen = scene.instantiate() as Control

	if current_screen == null:
		push_error("La scène doit avoir un Control comme racine : " + scene_path)
		return

	navigation_layer.add_child(current_screen)

func go_back_menu() -> void:
	go("MainMenu")

func go_back() -> void:
	if history.is_empty():
		return

	var previous_scene: String = history.pop_back()
	go_to(previous_scene, false)

func clear_history() -> void:
	history.clear()
