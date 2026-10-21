
extends Node

signal transition_finished

var navigation_layer: Control
var transition_layer: CanvasLayer
var fade: ColorRect
var loadingLayer: CanvasLayer

var current_screen: Control
var history: Array[String] = []
var is_transitioning: bool = false

const FADE_OUT_DURATION: float = 0.30
const FADE_IN_DURATION: float = 0.40

const SCENES: Dictionary = {
	"Audio": "res://ui/scene/Audio.tscn",
	"CarSelection": "res://ui/scene/CarSelection.tscn",
	"ControlBindingRow": "res://ui/scene/ControlBindingRow.tscn",
	"Controls": "res://ui/scene/Controls.tscn",
	"Display": "res://ui/scene/Display.tscn",
	"FirstLaunchScreen": "res://ui/scene/FirstLaunchScreen.tscn",
	"Main": "res://ui/scene/Main.tscn",
	"MainMenu": "res://ui/scene/MainMenu.tscn",
	"Options": "res://ui/scene/Options.tscn",
	"PlayerSlot": "res://ui/scene/PlayerSlot.tscn",
	"Profile": "res://ui/scene/Profile.tscn",
	"RaceRecap": "res://ui/scene/RaceRecap.tscn",
	"BestTimes": "res://ui/scene/BestTimes.tscn",
	"RaceResultRow": "res://ui/scene/RaceResultRow.tscn",
	"RaceSetup": "res://ui/scene/RaceSetup.tscn",
	"StartupScreen": "res://ui/scene/StartupScreen.tscn",
	"PauseOverlay": "res://ui/overlay/PauseOverlay.tscn",
	"PlayerJoinOverlay": "res://ui/overlay/PlayerJoinOverlay.tscn",
	"Race": "res://level/scene/Race.tscn",
	"RaceRestart": "res://level/scene/RaceRestart.tscn",
	"RaceController": "res://level/scene/RaceController.tscn",
	"RaceHUD": "res://level/scene/RaceHUD.tscn",
	"RaceWorld": "res://level/scene/RaceWorld.tscn",
	"RaceParticipantHUD": "res://level/scene/RaceParticipantHUD.tscn",
	"RaceStartLights": "res://level/scene/RaceStartLights.tscn",
	"RaceStartLight": "res://level/scene/RaceStartLight.tscn",
	"Car": "res://perso/car/Car.tscn",
	"SkidMarks": "res://perso/car/SkidMarks.tscn"
}


func setup(_navigation_layer: Control, _transition_layer: CanvasLayer) -> void:
	navigation_layer = _navigation_layer
	transition_layer = _transition_layer

	if navigation_layer == null:
		push_error("NavigationManager : NavigationLayer introuvable.")
		return

	if transition_layer == null:
		push_error("NavigationManager : TransitionLayer introuvable.")
		return

	fade = transition_layer.get_node_or_null("Fade") as ColorRect
	loadingLayer = transition_layer.get_node_or_null("LoadingLayer") as CanvasLayer

	if fade == null:
		push_error("NavigationManager : TransitionLayer/Fade introuvable.")
		return

	# Le fondu est transparent au démarrage.
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func get_scene(scene: String) -> String:
	return SCENES.get(scene, "")

func go(
	scene: String,
	add_to_history: bool = true,
	show_loading: bool = false
) -> void:
	var scene_path: String = get_scene(scene)

	if scene_path.is_empty():
		push_error("NavigationManager : scène inconnue : " + scene)
		return

	print("NavigationManager : navigation vers ", scene)
	go_to(scene_path, add_to_history, show_loading)

func go_to(
	scene_path: String,
	add_to_history: bool = true,
	show_loading: bool = false
) -> void:
	if is_transitioning:
		push_warning(
			"NavigationManager : transition déjà en cours : "
			+ scene_path
		)
		return

	if navigation_layer == null or fade == null:
		push_error("NavigationManager : setup() non exécuté.")
		return

	if show_loading and loadingLayer == null:
		push_error("NavigationManager : LoadingLayer introuvable.")
		return

	is_transitioning = true

	# Afficher l'écran de chargement avant toute opération coûteuse.
	if show_loading:
		loadingLayer.show_loading()
		await get_tree().process_frame

	# Passer au noir avant de remplacer l'écran.
	await _fade_to(1.0, FADE_OUT_DURATION)

	var packed_scene: PackedScene

	if show_loading:
		# Demander le chargement asynchrone des ressources.
		var request_error: Error = ResourceLoader.load_threaded_request(
			scene_path,
			"PackedScene",
			true
		)

		if request_error != OK:
			push_error(
				"NavigationManager : impossible de démarrer le chargement : "
				+ scene_path
			)
			await _abort_transition(show_loading)
			return

		# Attendre sans bloquer le rendu ni l'animation.
		var progress: Array = []

		while true:
			var status := ResourceLoader.load_threaded_get_status(
				scene_path,
				progress
			)

			if status == ResourceLoader.THREAD_LOAD_LOADED:
				break

			if status == ResourceLoader.THREAD_LOAD_FAILED \
			or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_error(
					"NavigationManager : échec du chargement : "
					+ scene_path
				)
				await _abort_transition(show_loading)
				return

			# Mettre à jour la barre si elle existe.
			if loadingLayer.has_method("set_progress"):
				if not progress.is_empty():
					loadingLayer.set_progress(progress[0] * 100.0)

			await get_tree().process_frame

		packed_scene = ResourceLoader.load_threaded_get(
			scene_path
		) as PackedScene
	else:
		# Chargement classique pour les écrans légers.
		packed_scene = load(scene_path) as PackedScene

	if packed_scene == null:
		push_error(
			"NavigationManager : scène impossible à charger : "
			+ scene_path
		)
		await _abort_transition(show_loading)
		return

	# Attention : instantiate() reste synchrone.
	var new_screen := packed_scene.instantiate() as Control

	if new_screen == null:
		push_error(
			"NavigationManager : la racine doit être un Control : "
			+ scene_path
		)
		await _abort_transition(show_loading)
		return

	# Remplacer l'écran précédent.
	if is_instance_valid(current_screen):
		if add_to_history and not current_screen.scene_file_path.is_empty():
			history.append(current_screen.scene_file_path)

		navigation_layer.remove_child(current_screen)
		current_screen.queue_free()

	current_screen = new_screen
	navigation_layer.add_child(current_screen)

	# Attendre que l'écran soit intégré à l'arbre.
	await get_tree().process_frame

	# Masquer le chargement uniquement après l'intégration de l'écran.
	if show_loading:
		loadingLayer.hide_loading()

	await _fade_to(0.0, FADE_IN_DURATION)

	is_transitioning = false
	transition_finished.emit()


func _abort_transition(show_loading: bool) -> void:
	if show_loading and is_instance_valid(loadingLayer):
		loadingLayer.hide_loading()

	await _fade_to(0.0, FADE_IN_DURATION)

	is_transitioning = false
	transition_finished.emit()


func _fade_to(target_alpha: float, duration: float) -> void:
	if fade == null:
		return
	
	fade.mouse_filter = (
		Control.MOUSE_FILTER_STOP
		if target_alpha > 0.0
		else Control.MOUSE_FILTER_IGNORE
	)

	var tween := create_tween()
	tween.tween_property(
		fade,
		"color:a",
		target_alpha,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await tween.finished


func go_back_menu() -> void:
	go("MainMenu")


func go_back() -> void:
	if history.is_empty() or is_transitioning:
		return

	var previous_scene: String = history.pop_back()
	go_to(previous_scene, false)


func clear_history() -> void:
	history.clear()
