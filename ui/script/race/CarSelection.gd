extends Control

const PARTICIPANT_SCENE := preload(
	"res://ui/scene/CarSelectionParticipant.tscn"
)


@onready var back_button: Button = (
	$MarginContainer/VBoxContainer/Footer/BackButton
)

@onready var participant_list: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainContent/ParticipantsPanel/ParticipantsMargin/ParticipantsVBox/ParticipantScroll/ParticipantList
)

@onready var selected_participant_label: Label = (
	$MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/SelectedParticipant
)

@onready var car_grid: GridContainer = (
	$MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/CarGridScroll/CarGrid
)

@onready var color_grid: GridContainer = (
	$MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/ColorGrid
)

@onready var preview_image: TextureRect = (
	$MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/PreviewPanel/PreviewVBox/PreviewImage
)

@onready var car_name: Label = (
	$MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/PreviewPanel/PreviewVBox/CarName
)

@onready var car_description: Label = (
	$MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/PreviewPanel/PreviewVBox/CarDescription
)

@onready var selection_status: Label = (
	$MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/SelectionStatus
)

@onready var help_label: Label = (
	$MarginContainer/VBoxContainer/Footer/HelpLabel
)

@onready var start_button: Button = (
	$MarginContainer/VBoxContainer/Footer/StartButton
)


var race_config: RaceConfig

var selected_participant_index := -1
var participant_buttons: Array[CarSelectionParticipant] = []
var car_buttons: Array[Button] = []
var color_buttons: Array[Button] = []


func _ready() -> void:

	race_config = GameManager.get_pending_race_config()

	if race_config == null:
		push_error(
			"CarSelection : aucune RaceConfig en attente."
		)

		NavigationManager.go_back()
		return


	# Construction des 8 participants.
	race_config.build_participants()

	_setup_car_grid()
	_setup_color_grid()
	_setup_participants()

	_connect_signals()

	_refresh_start_button()

	if not participant_buttons.is_empty():
		_select_participant(0)
	else:
		back_button.grab_focus()


# ================================================================
# SIGNALS
# ================================================================

func _connect_signals() -> void:
	back_button.pressed.connect(_on_back_pressed)
	start_button.pressed.connect(_on_start_pressed)


# ================================================================
# PARTICIPANTS
# ================================================================

func _setup_participants() -> void:

	for child in participant_list.get_children():
		child.queue_free()

	participant_buttons.clear()


	for i in range(race_config.participants.size()):

		var participant: Dictionary = (
			race_config.participants[i]
		)

		# Attribution d'une couleur initiale unique.
		if not participant.has("color_id"):
			participant["color_id"] = _get_default_color(i)

		# Première voiture par défaut.
		if not participant.has("car_id"):
			participant["car_id"] = "car_01"


		var button: CarSelectionParticipant = (
			PARTICIPANT_SCENE.instantiate()
		)

		participant_list.add_child(button)

		button.setup(i, participant)

		button.participant_selected.connect(
			_on_participant_selected
		)

		participant_buttons.append(button)


func _on_participant_selected(index: int) -> void:
	_select_participant(index)


func _select_participant(index: int) -> void:

	if index < 0:
		return

	if index >= race_config.participants.size():
		return

	selected_participant_index = index

	var participant := race_config.participants[index]

	var nickname := str(
		participant.get("nickname", "")
	)

	var is_ai := bool(
		participant.get("is_ai", false)
	)

	if is_ai:
		selected_participant_label.text = (
			"Configuration de %s"
		) % nickname
	else:
		selected_participant_label.text = (
			"Configuration de %s"
		) % nickname


	_refresh_car_selection()
	_refresh_color_selection()
	_refresh_preview()
	_refresh_status()


# ================================================================
# VOITURES
# ================================================================

func _setup_car_grid() -> void:

	for child in car_grid.get_children():
		child.queue_free()

	car_buttons.clear()


	for car in CarCatalog.get_cars():

		var button := Button.new()

		button.text = str(car.get("name", "Voiture"))

		button.custom_minimum_size = Vector2(180, 70)
		button.focus_mode = Control.FOCUS_ALL

		car_grid.add_child(button)

		button.pressed.connect(
			_on_car_selected.bind(
				str(car.get("id", ""))
			)
		)

		car_buttons.append(button)


func _refresh_car_selection() -> void:

	if selected_participant_index < 0:
		return

	var participant := race_config.participants[
		selected_participant_index
	]

	var current_car_id := str(
		participant.get("car_id", "")
	)


	for i in range(car_buttons.size()):

		var car = CarCatalog.get_cars()[i]

		var car_id := str(
			car.get("id", "")
		)

		car_buttons[i].button_pressed = (
			car_id == current_car_id
		)


func _on_car_selected(car_id: String) -> void:

	if selected_participant_index < 0:
		return

	race_config.participants[
		selected_participant_index
	]["car_id"] = car_id

	_refresh_car_selection()
	_refresh_preview()
	_refresh_participant_list()
	_refresh_start_button()


# ================================================================
# COULEURS
# ================================================================

func _setup_color_grid() -> void:

	for child in color_grid.get_children():
		child.queue_free()

	color_buttons.clear()


	for color in CarCatalog.get_colors():

		var button := Button.new()

		button.text = str(
			color.get("name", "Couleur")
		)

		button.custom_minimum_size = Vector2(130, 50)
		button.focus_mode = Control.FOCUS_ALL

		color_grid.add_child(button)

		button.pressed.connect(
			_on_color_selected.bind(
				str(color.get("id", ""))
			)
		)

		color_buttons.append(button)


func _refresh_color_selection() -> void:

	if selected_participant_index < 0:
		return

	var participant := race_config.participants[
		selected_participant_index
	]

	var current_color_id := str(
		participant.get("color_id", "")
	)


	for i in range(color_buttons.size()):

		var color = CarCatalog.get_colors()[i]

		var color_id := str(
			color.get("id", "")
		)

		color_buttons[i].disabled = (
			_is_color_used_by_other_participant(color_id)
		)

		color_buttons[i].button_pressed = (
			color_id == current_color_id
		)


func _is_color_used_by_other_participant(
	color_id: String
) -> bool:

	for i in range(race_config.participants.size()):

		if i == selected_participant_index:
			continue

		var participant := race_config.participants[i]

		if str(
			participant.get("color_id", "")
		) == color_id:
			return true

	return false


func _on_color_selected(color_id: String) -> void:

	if selected_participant_index < 0:
		return

	if _is_color_used_by_other_participant(color_id):
		return

	race_config.participants[
		selected_participant_index
	]["color_id"] = color_id

	_refresh_color_selection()
	_refresh_participant_list()
	_refresh_preview()
	_refresh_status()
	_refresh_start_button()


func _get_default_color(index: int) -> String:

	var colors := CarCatalog.get_colors()

	if index >= colors.size():
		return ""

	return str(
		colors[index].get("id", "")
	)


# ================================================================
# PREVIEW
# ================================================================

func _refresh_preview() -> void:

	if selected_participant_index < 0:
		return

	var participant := race_config.participants[
		selected_participant_index
	]

	var car_id := str(
		participant.get("car_id", "")
	)

	var color_id := str(
		participant.get("color_id", "")
	)


	var car := CarCatalog.get_car(car_id)

	if car.is_empty():
		car_name.text = "Aucune voiture"
		car_description.text = ""
	else:
		car_name.text = str(
			car.get("name", "")
		)

		car_description.text = str(
			car.get("description", "")
		)


	# Pas encore de sprite de preview obligatoire.
	# On laisse le TextureRect vide jusqu'à ce que les
	# assets des voitures soient définis.
	preview_image.texture = null


	var color := CarCatalog.get_color(color_id)

	if not color.is_empty():
		preview_image.modulate = color.color
	else:
		preview_image.modulate = Color.WHITE


# ================================================================
# LISTE PARTICIPANTS
# ================================================================

func _refresh_participant_list() -> void:

	for i in range(
		min(
			participant_buttons.size(),
			race_config.participants.size()
		)
	):

		participant_buttons[i].setup(
			i,
			race_config.participants[i]
		)


# ================================================================
# VALIDATION
# ================================================================

func _refresh_status() -> void:

	if race_config.is_car_selection_valid():
		selection_status.text = "Configuration complète."
	else:
		selection_status.text = (
			"Chaque participant doit avoir une voiture et une couleur unique."
	)


func _refresh_start_button() -> void:
	start_button.disabled = (
		not race_config.is_car_selection_valid()
	)


# ================================================================
# NAVIGATION
# ================================================================

func _on_back_pressed() -> void:
	NavigationManager.go_back()


func _on_start_pressed() -> void:

	if not race_config.is_car_selection_valid():
		return

	GameManager.set_pending_race_config(
		race_config.duplicate_config()
	)

	if not GameManager.start_race():
		return

	NavigationManager.go_to(
		"res://ui/scene/Race.tscn"
	)
