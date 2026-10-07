extends Control


var race_config: RaceConfig
var selected_participant_index: int = -1

var cars: Array[CarDefinition] = []
var colors: Array = []


@onready var back_button: Button = $MarginContainer/VBoxContainer/Footer/BackButton

@onready var participant_list: VBoxContainer = $MarginContainer/VBoxContainer/MainContent/ParticipantsPanel/ParticipantsMargin/ParticipantsVBox/ParticipantScroll/ParticipantList

@onready var selected_participant_label: Label = $MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/SelectedParticipant

@onready var car_grid: GridContainer = $MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/CarGridScroll/CarGrid

@onready var color_grid: GridContainer = $MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/ColorGrid

@onready var preview_image: TextureRect = $MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/PreviewPanel/PreviewVBox/PreviewImage

@onready var car_name_label: Label = $MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/PreviewPanel/PreviewVBox/CarName

@onready var car_description_label: Label = $MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/PreviewPanel/PreviewVBox/CarDescription

@onready var selection_status: Label = $MarginContainer/VBoxContainer/MainContent/SelectionPanel/SelectionMargin/SelectionVBox/SelectionStatus

@onready var start_button: Button = $MarginContainer/VBoxContainer/Footer/StartButton


func _ready() -> void:
	race_config = GameManager.get_pending_race_config()

	if race_config == null:
		push_error("CarSelection : aucune RaceConfig en attente.")
		return

	#if race_config.participants.is_empty():
	#	race_config.build_participants()
	race_config.build_participants()

	cars = CarCatalog.get_cars()
	colors = ColorCatalog.get_colors()

	_setup_participant_defaults()
	_setup_car_grid()
	_setup_color_grid()
	_refresh_participant_list()

	if race_config.participants.size() > 0:
		_select_participant(0)

	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)

	back_button.grab_focus()


func _setup_participant_defaults() -> void:
	for i in range(race_config.participants.size()):
		var participant := race_config.participants[i]

		if String(participant.get("car_id", "")).is_empty():
			if not cars.is_empty():
				participant["car_id"] = cars[0].id

		if String(participant.get("color_id", "")).is_empty():
			if i < colors.size():
				participant["color_id"] = colors[i]["id"]

		race_config.participants[i] = participant


func _setup_car_grid() -> void:
	for child in car_grid.get_children():
		child.queue_free()

	for car: CarDefinition in cars:
		var button := Button.new()

		button.text = car.display_name
		button.set_meta("car_id", car.id)

		button.custom_minimum_size = Vector2(150, 60)
		button.focus_mode = Control.FOCUS_ALL

		button.pressed.connect(
			_on_car_selected.bind(car.id, car.display_name)
		)

		car_grid.add_child(button)


func _setup_color_grid() -> void:
	for child in color_grid.get_children():
		child.queue_free()

	for color_data: Dictionary in colors:
		var button := Button.new()

		button.text = color_data["name"]
		button.custom_minimum_size = Vector2(110, 50)
		button.focus_mode = Control.FOCUS_ALL

		_apply_color_button_style(
			button,
			color_data["color"]
		)

		button.pressed.connect(
			_on_color_selected.bind(color_data["id"])
		)

		color_grid.add_child(button)


func _apply_color_button_style(
	button: Button,
	color: Color
) -> void:

	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6

	button.add_theme_stylebox_override(
		"normal",
		normal
	)

	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.12)

	button.add_theme_stylebox_override(
		"hover",
		hover
	)

	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.12)

	button.add_theme_stylebox_override(
		"pressed",
		pressed
	)


func _refresh_participant_list() -> void:
	for child in participant_list.get_children():
		child.queue_free()

	for i in range(race_config.participants.size()):
		var participant := race_config.participants[i]

		var is_ai: bool = bool(
			participant.get("is_ai", false)
		)

		var enabled: bool = bool(
			participant.get("enabled", true)
		)

		var hbox := HBoxContainer.new()

		var select_button := Button.new()

		select_button.text = _get_participant_display_text(
			participant,
			i
		)

		select_button.custom_minimum_size = Vector2(0, 60)
		select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select_button.focus_mode = Control.FOCUS_ALL

		# Une IA désactivée reste visible mais ne peut pas
		# être sélectionnée pour modifier sa voiture/couleur.
		select_button.disabled = is_ai and not enabled

		select_button.pressed.connect(
			_select_participant.bind(i)
		)

		hbox.add_child(select_button)

		if is_ai:
			var toggle_button := Button.new()

			toggle_button.text = (
				"Désactiver"
				if enabled
				else "Activer"
			)

			toggle_button.custom_minimum_size = Vector2(110, 60)
			toggle_button.focus_mode = Control.FOCUS_ALL

			toggle_button.pressed.connect(
				_on_toggle_pressed.bind(i)
			)

			hbox.add_child(toggle_button)

			# Aspect visuel d'une IA désactivée.
			if not enabled:
				select_button.modulate = Color(
					0.55,
					0.55,
					0.55,
					1.0
				)

		participant_list.add_child(hbox)


func _get_participant_display_text(
	participant: Dictionary,
	index: int
) -> String:

	var nickname := String(
		participant.get(
			"nickname",
			"Participant %d" % (index + 1)
		)
	)

	var car_id := String(
		participant.get("car_id", "")
	)

	var color_id := String(
		participant.get("color_id", "")
	)

	var car := CarCatalog.get_car(car_id)
	var color := ColorCatalog.get_color(color_id)

	var car_name := "?"
	if car != null:
		car_name = car.display_name

	var color_name := "?"
	if not color.is_empty():
		color_name = color["name"]

	var ai_text := ""

	if bool(participant.get("is_ai", false)):
		ai_text = " [IA]"

	return "%d. %s%s — %s / %s" % [
		index + 1,
		nickname,
		ai_text,
		car_name,
		color_name
	]


func _select_participant(index: int) -> void:
	if index < 0 or index >= race_config.participants.size():
		return

	selected_participant_index = index

	var participant := race_config.participants[index]

	selected_participant_label.text = String(
		participant.get(
			"nickname",
			"Participant %d" % (index + 1)
		)
	)

	_refresh_car_buttons()
	_refresh_color_buttons()
	_refresh_preview()
	_update_status()

func _on_toggle_pressed(index: int) -> void:
	if index < 0 or index >= race_config.participants.size():
		return

	var participant := race_config.participants[index]

	if not bool(participant.get("is_ai", false)):
		return

	var enabled := bool(
		participant.get("enabled", true)
	)

	participant["enabled"] = not enabled

	race_config.participants[index] = participant

	_refresh_participant_list()

	_refresh_car_buttons()
	_refresh_color_buttons()
	_refresh_preview()
	_update_status()

func _refresh_car_buttons() -> void:
	if selected_participant_index < 0:
		return

	var participant := race_config.participants[
		selected_participant_index
	]

	var selected_car_id := String(
		participant.get("car_id", "")
	)

	for child in car_grid.get_children():
		var button := child as Button

		if button == null:
			continue

		var car_id := String(
			button.get_meta("car_id", "")
		)

		var car := CarCatalog.get_car(car_id)

		if car == null:
			continue

		button.text = (
			"✓ " + car.display_name
			if car.id == selected_car_id
			else car.display_name
		)


func _find_car_by_display_name(
	display_name: String
) -> CarDefinition:

	for car: CarDefinition in cars:
		if car.display_name == display_name:
			return car

	return null


func _refresh_color_buttons() -> void:
	if selected_participant_index < 0:
		return

	var participant := race_config.participants[
		selected_participant_index
	]

	var selected_color_id := String(
		participant.get("color_id", "")
	)

	for i in range(color_grid.get_child_count()):
		var button := color_grid.get_child(i) as Button

		if button == null:
			continue

		var color_data: Dictionary = colors[i]

		var color_id := String(
			color_data["id"]
		)

		var used_by_other := _is_color_used_by_other(
			color_id,
			selected_participant_index
		)

		button.disabled = used_by_other

		var prefix := "✓ " if color_id == selected_color_id else ""

		button.text = prefix + String(
			color_data["name"]
		)


func _is_color_used_by_other(
	color_id: String,
	current_index: int
) -> bool:

	for i in range(race_config.participants.size()):
		if i == current_index:
			continue

		var participant := race_config.participants[i]

		if not bool(participant.get("enabled", true)):
			continue

		if String(
			participant.get("color_id", "")
		) == color_id:
			return true

	return false


func _on_car_selected(car_id: String, car_name: String) -> void:
	if selected_participant_index < 0:
		return

	race_config.participants[
		selected_participant_index
	]["car_id"] = car_id
	
	race_config.participants[
		selected_participant_index
	]["car_name"] = car_name

	_refresh_participant_list()
	_refresh_car_buttons()
	_refresh_preview()
	_update_status()


func _on_color_selected(color_id: String) -> void:
	if selected_participant_index < 0:
		return

	if _is_color_used_by_other(
		color_id,
		selected_participant_index
	):
		return

	race_config.participants[
		selected_participant_index
	]["color_id"] = color_id

	_refresh_participant_list()
	_refresh_color_buttons()
	_refresh_preview()
	_update_status()


func _refresh_preview() -> void:
	if selected_participant_index < 0:
		return

	var participant := race_config.participants[
		selected_participant_index
	]

	var car := CarCatalog.get_car(
		String(participant.get("car_id", ""))
	)

	if car == null:
		car_name_label.text = "Voiture inconnue"
		car_description_label.text = ""
		preview_image.texture = null
		return

	car_name_label.text = car.display_name
	car_description_label.text = car.description

	preview_image.texture = car.preview_texture

	var color_data := ColorCatalog.get_color(
		String(participant.get("color_id", ""))
	)

	if not color_data.is_empty():
		preview_image.modulate = color_data["color"]
	else:
		preview_image.modulate = Color.WHITE


func _update_status() -> void:
	if race_config.is_car_selection_valid():
		selection_status.text = "Sélection complète."
		start_button.disabled = false
	else:
		selection_status.text = "Chaque participant doit avoir une voiture et une couleur."
		start_button.disabled = true


func _on_start_pressed() -> void:
	if not race_config.is_car_selection_valid():
		_update_status()
		return

	if not GameManager.start_race():
		return

	NavigationManager.go("Race")


func _on_back_pressed() -> void:
	NavigationManager.go_back()
