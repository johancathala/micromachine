extends Control

@onready var loading_label: Label = $MarginContainer/VBoxContainer/VBoxContainer/LoadingLabel
@onready var loading_progress: ProgressBar = $MarginContainer/VBoxContainer/VBoxContainer/LoadingProgress


func _ready() -> void:
	_start_initialization()


func _start_initialization() -> void:
	loading_label.text = "Chargement..."
	loading_progress.value = 0.0

	await _initialize_game()

	_continue_to_next_screen()


func _initialize_game() -> void:
	loading_label.text = "Initialisation..."
	loading_progress.value = 20.0
	await get_tree().process_frame

	SaveManager.initialize()

	loading_label.text = "Chargement du profil..."
	loading_progress.value = 50.0
	await get_tree().process_frame

	SaveManager.load_profile()
	
	loading_label.text = "Chargement des paramètres d'affichage..."
	loading_progress.value = 60.0
	await get_tree().process_frame
	SaveManager.apply_display_settings()

	# Important :
	# InputManager doit être initialisé APRÈS
	# le chargement de la sauvegarde.
	loading_label.text = "Chargement des paramètres de contrôle..."
	loading_progress.value = 70.0
	await get_tree().process_frame
	InputManager.initialize()

	loading_label.text = "Préparation..."
	loading_progress.value = 80.0
	await get_tree().process_frame

	loading_progress.value = 100.0
	await get_tree().create_timer(0.15).timeout


func _continue_to_next_screen() -> void:
	if SaveManager.is_first_launch():
		NavigationManager.go(
			"FirstLaunchScreen",
			false
		)
	else:
		NavigationManager.go(
			"MainMenu",
			false
		)
