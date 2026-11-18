extends Control

# ============================================================
# ÉCRAN DES IA (course classique et élimination, après les joueurs)
# ============================================================
#
# Une ligne par IA engagée : pilote (Novice, Moyen, Expert ou
# fantôme), voiture et couleur. Les places libres sont celles que
# les joueurs n'occupent pas (8 au total). Les livrées restent
# uniques : une couleur déjà prise est grisée.
#
# « Ajouter » et « Remplir » engagent des IA au niveau choisi en
# haut de l'écran, avec une voiture au hasard. La composition est
# reprise d'une course à l'autre (RaceConfig.remember_ai_slots).
#
# Pilote fantôme : il roulera avec le meilleur fantôme valide de sa
# voiture sur le circuit choisi à l'écran suivant. Grisé tant que la
# conduite des fantômes n'existe pas.
# ============================================================

const GHOST_PILOT_AVAILABLE := false

var race_config: RaceConfig
# Styles restant à distribuer (Ajouter / Remplir).
var _style_pool: Array[String] = []
var _description_slot := -1
var _description_kind := "level"
var cars: Array[CarDefinition] = []
var colors: Array = []

@onready var title_label: Label = $MarginContainer/VBoxContainer/Title
@onready var level_selector: OptionButton = $MarginContainer/VBoxContainer/Toolbar/Level
@onready var add_button: Button = $MarginContainer/VBoxContainer/Toolbar/AddButton
@onready var fill_button: Button = $MarginContainer/VBoxContainer/Toolbar/FillButton
@onready var clear_button: Button = $MarginContainer/VBoxContainer/Toolbar/ClearButton
@onready var rows_box: VBoxContainer = $MarginContainer/VBoxContainer/Scroll/Rows
@onready var empty_label: Label = $MarginContainer/VBoxContainer/EmptyLabel
@onready var description_label: Label = $MarginContainer/VBoxContainer/Description
@onready var back_button: Button = $MarginContainer/VBoxContainer/Footer/BackButton
@onready var help_label: Label = $MarginContainer/VBoxContainer/Footer/HelpLabel
@onready var next_button: Button = $MarginContainer/VBoxContainer/Footer/NextButton
@onready var focus_manager: MenuFocusManager = $MenuFocusManager


func _ready() -> void:
	race_config = GameManager.get_pending_race_config()

	if race_config == null:
		race_config = RaceConfig.new()
		race_config.mode = GameManager.GameMode.SINGLE_RACE

	cars = CarCatalog.get_cars()
	colors = ColorCatalog.get_colors()

	for level in [RaceConfig.AIPilot.NOVICE, RaceConfig.AIPilot.MEDIUM, RaceConfig.AIPilot.EXPERT]:
		level_selector.add_item(RaceConfig.AI_PILOT_NAMES[level], level)

	level_selector.select(level_selector.get_item_index(
		RaceConfig.get_ai_difficulty(race_config.ai_difficulty)
	))
	level_selector.item_selected.connect(
		func(index: int):
			race_config.ai_difficulty = level_selector.get_item_id(index)
			_show_level_hint()
	)
	level_selector.focus_entered.connect(_show_level_hint)

	add_button.pressed.connect(_on_add_pressed)
	fill_button.pressed.connect(_on_fill_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	back_button.pressed.connect(_on_back_pressed)
	next_button.pressed.connect(_on_next_pressed)

	_sync()
	_rebuild_rows()
	AudioManager.bind_sound_btt()
	focus_manager.set_focus.call_deferred(level_selector)


# ------------------------------------------------------------
# Composition
# ------------------------------------------------------------

## Limite la composition aux places libres et recalcule la grille
## (livrées des IA rendues uniques).
func _sync() -> void:
	var max_count := race_config.get_max_ai_count()

	if race_config.ai_slots.size() > max_count:
		race_config.ai_slots.resize(max_count)

	race_config.build_participants()


func _free_places() -> int:
	return race_config.get_max_ai_count() - race_config.ai_slots.size()


## Nouvelle IA au niveau choisi, voiture au hasard (livrée libre
## attribuée par la grille).
func _add_ai() -> void:
	if _free_places() <= 0:
		return

	if _style_pool.is_empty():
		_style_pool = AIStyle.shuffled_ids()

	race_config.ai_slots.append({
		"pilot": race_config.ai_difficulty,
		"style": _style_pool.pop_back(),
		"car_id": cars[randi() % cars.size()].id,
		"color_id": String(colors[randi() % colors.size()]["id"])
	})
	_sync()


func _on_add_pressed() -> void:
	_add_ai()
	_rebuild_rows()


func _on_fill_pressed() -> void:
	# Tous les styles avant de reprendre le même.
	_style_pool = AIStyle.shuffled_ids()

	while _free_places() > 0:
		_add_ai()

	_rebuild_rows()


func _on_clear_pressed() -> void:
	race_config.ai_slots.clear()
	_sync()
	_rebuild_rows()
	focus_manager.set_focus(add_button)


func _on_remove_pressed(slot_index: int) -> void:
	race_config.ai_slots.remove_at(slot_index)
	_sync()
	_rebuild_rows()


func _on_pilot_selected(index: int, slot_index: int, selector: OptionButton) -> void:
	race_config.ai_slots[slot_index]["pilot"] = selector.get_item_id(index)
	_sync()
	_rebuild_rows()
	_show_description(slot_index, "level")


## Description du niveau choisi pour les IA ajoutées.
func _show_level_hint() -> void:
	var level := RaceConfig.get_ai_difficulty(race_config.ai_difficulty)
	description_label.text = "Niveau %s : %s" % [RaceConfig.AI_PILOT_NAMES[level], AIStyle.LEVEL_DESCRIPTIONS[level]]


func _on_style_selected(index: int, slot_index: int) -> void:
	race_config.ai_slots[slot_index]["style"] = String(AIStyle.get_styles()[index]["id"])
	_sync()
	_rebuild_rows()
	_show_description(slot_index, "style")


## Description sous le tableau : niveau ou style de l'IA survolée /
## sélectionnée.
func _show_description(slot_index: int, kind: String) -> void:
	if slot_index < 0 or slot_index >= race_config.ai_slots.size():
		return

	_description_slot = slot_index
	_description_kind = kind
	var slot := race_config.ai_slots[slot_index]
	var level := RaceConfig.get_ai_difficulty(int(slot.get("pilot", RaceConfig.AIPilot.MEDIUM)))
	var style := AIStyle.get_style(String(slot.get("style", AIStyle.DEFAULT_ID)))

	if kind == "style":
		description_label.text = "Style %s : %s" % [style["name"], style["description"]]
	else:
		description_label.text = "Niveau %s : %s" % [
			RaceConfig.AI_PILOT_NAMES[level], AIStyle.LEVEL_DESCRIPTIONS[level]
		]


func _on_car_selected(index: int, slot_index: int, selector: OptionButton) -> void:
	race_config.ai_slots[slot_index]["car_id"] = cars[selector.get_item_id(index)].id
	# Couleur gardée si elle est libre pour ce modèle, sinon la grille
	# en attribue une autre.
	_sync()
	_rebuild_rows()


func _on_color_selected(index: int, slot_index: int, selector: OptionButton) -> void:
	race_config.ai_slots[slot_index]["color_id"] = String(colors[selector.get_item_id(index)]["id"])
	_sync()
	_rebuild_rows()


# ------------------------------------------------------------
# Affichage
# ------------------------------------------------------------

func _participant_index(slot_index: int) -> int:
	return race_config.players.size() + slot_index


func _rebuild_rows() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var focused_path := rows_box.get_path_to(focused) if focused != null and rows_box.is_ancestor_of(focused) else NodePath()

	for child in rows_box.get_children():
		rows_box.remove_child(child)
		child.queue_free()

	var focus_rows: Array[Array] = []

	if not race_config.ai_slots.is_empty():
		_build_header()

	for slot_index in range(race_config.ai_slots.size()):
		focus_rows.append(_build_row(slot_index))

	var free := _free_places()
	var count := race_config.ai_slots.size()

	title_label.text = "INTELLIGENCES ARTIFICIELLES (%d / %d)" % [count, race_config.get_max_ai_count()]
	empty_label.visible = count == 0
	add_button.disabled = free <= 0
	fill_button.disabled = free <= 0
	clear_button.disabled = count == 0
	# Élimination : au moins deux voitures en tout.
	next_button.disabled = (
		race_config.is_elimination()
		and race_config.players.size() + count < RaceConfig.ELIMINATION_MIN_PLAYERS
	)

	if count == 0:
		_show_level_hint()
	elif _description_slot >= 0 and _description_slot < count:
		_show_description(_description_slot, _description_kind)
	else:
		_show_description(0, "level")

	if race_config.get_max_ai_count() == 0:
		empty_label.text = "Aucune place libre : la grille est complète."
	elif race_config.is_elimination() and race_config.players.size() < RaceConfig.ELIMINATION_MIN_PLAYERS:
		empty_label.text = "Élimination : ajoutez au moins une IA."
	else:
		empty_label.text = "Aucune IA : course entre joueurs."

	help_label.text = "%d joueur%s + %d IA" % [
		race_config.players.size(),
		"s" if race_config.players.size() > 1 else "",
		count
	]

	_set_navigation(focus_rows)

	# Focus conservé sur la même commande après reconstruction.
	if not focused_path.is_empty():
		var restored := rows_box.get_node_or_null(focused_path) as Control

		if restored != null and restored.focus_mode != Control.FOCUS_NONE:
			focus_manager.set_focus.call_deferred(restored)
			return

	if (
		focused == null
		or not is_instance_valid(focused)
		or not focused.is_visible_in_tree()
		or (focused is BaseButton and (focused as BaseButton).disabled)
	):
		focus_manager.set_focus.call_deferred(next_button if count > 0 else add_button)


## En-têtes des colonnes, alignés sur les lignes.
func _build_header() -> void:
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	rows_box.add_child(header)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(28 + 12 + 110, 0)
	header.add_child(spacer)

	for title in ["Niveau", "Style", "Voiture", "Couleur"]:
		var label := Label.new()
		label.text = title
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 24)
		label.modulate = Color(1, 1, 1, 0.75)
		header.add_child(label)

	var end := Control.new()
	end.custom_minimum_size = Vector2(133, 0)
	header.add_child(end)


## Ligne d'une IA ; renvoie ses commandes (ordre de navigation).
func _build_row(slot_index: int) -> Array[Control]:
	var participant := race_config.get_participant(_participant_index(slot_index))
	var slot := race_config.ai_slots[slot_index]

	var row := HBoxContainer.new()
	row.name = "Row%d" % slot_index
	row.add_theme_constant_override("separation", 12)
	rows_box.add_child(row)

	# Pastille de couleur + nom.
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(28, 28)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var color_data := ColorCatalog.get_color(String(participant.get("color_id", "")))
	swatch.color = color_data.get("color", Color.WHITE)
	row.add_child(swatch)

	var name_label := Label.new()
	name_label.text = String(participant.get("nickname", "IA %d" % (slot_index + 1)))
	name_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(name_label)

	# Pilote.
	var pilot := OptionButton.new()
	pilot.name = "Pilot"
	pilot.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for value in [RaceConfig.AIPilot.NOVICE, RaceConfig.AIPilot.MEDIUM, RaceConfig.AIPilot.EXPERT, RaceConfig.AIPilot.GHOST]:
		var label: String = RaceConfig.AI_PILOT_NAMES[value]

		if value == RaceConfig.AIPilot.GHOST:
			label = "Fantôme" if GHOST_PILOT_AVAILABLE else "Fantôme (bientôt)"

		pilot.add_item(label, value)

		if value == RaceConfig.AIPilot.GHOST and not GHOST_PILOT_AVAILABLE:
			pilot.set_item_disabled(pilot.get_item_index(value), true)

	pilot.select(pilot.get_item_index(int(slot.get("pilot", RaceConfig.AIPilot.MEDIUM))))
	pilot.item_selected.connect(_on_pilot_selected.bind(slot_index, pilot))
	pilot.focus_entered.connect(_show_description.bind(slot_index, "level"))
	pilot.mouse_entered.connect(_show_description.bind(slot_index, "level"))

	# Style de pilotage.
	var style_selector := OptionButton.new()
	style_selector.name = "Style"
	style_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var styles := AIStyle.get_styles()
	var style_id := String(slot.get("style", AIStyle.DEFAULT_ID))

	for i in range(styles.size()):
		style_selector.add_item(String(styles[i]["name"]), i)

		if styles[i]["id"] == style_id:
			style_selector.select(i)

	style_selector.item_selected.connect(_on_style_selected.bind(slot_index))
	style_selector.focus_entered.connect(_show_description.bind(slot_index, "style"))
	style_selector.mouse_entered.connect(_show_description.bind(slot_index, "style"))
	row.add_child(pilot)
	row.add_child(style_selector)

	# Voiture.
	var car_selector := OptionButton.new()
	car_selector.name = "Car"
	car_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var car_id := String(participant.get("car_id", ""))

	for i in range(cars.size()):
		car_selector.add_item(cars[i].display_name, i)

		if cars[i].id == car_id:
			car_selector.select(i)

	car_selector.item_selected.connect(_on_car_selected.bind(slot_index, car_selector))
	row.add_child(car_selector)

	# Couleur : celles déjà prises pour ce modèle sont grisées.
	var color_selector := OptionButton.new()
	color_selector.name = "Color"
	color_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var participant_index := _participant_index(slot_index)

	for i in range(colors.size()):
		var color_id := String(colors[i]["id"])
		var taken := race_config.is_livery_taken(car_id, color_id, participant_index)
		color_selector.add_item(String(colors[i]["name"]) + (" (prise)" if taken else ""), i)
		color_selector.set_item_disabled(i, taken)

		if color_id == String(participant.get("color_id", "")):
			color_selector.select(i)

	color_selector.item_selected.connect(_on_color_selected.bind(slot_index, color_selector))
	row.add_child(color_selector)

	var remove := Button.new()
	remove.name = "Remove"
	remove.text = "RETIRER"
	remove.add_to_group("audio_back")
	remove.pressed.connect(_on_remove_pressed.bind(slot_index))
	row.add_child(remove)

	var controls: Array[Control] = [pilot, style_selector, car_selector, color_selector, remove]

	for control in controls:
		control.focus_mode = Control.FOCUS_ALL

	return controls


## Navigation à la manette : gauche/droite dans une ligne, haut/bas
## d'une ligne à l'autre (même colonne), barre d'outils en haut,
## boutons du bas en dessous.
func _set_navigation(rows: Array[Array]) -> void:
	var toolbar: Array[Control] = [level_selector, add_button, fill_button, clear_button]
	focus_manager.set_horizontal_navigation(toolbar, false)

	for row: Array in rows:
		var typed: Array[Control] = []
		typed.assign(row)
		focus_manager.set_horizontal_navigation(typed, false)

	for column in range(5):
		var chain: Array[Control] = [toolbar[mini(column, toolbar.size() - 1)]]

		for row: Array in rows:
			chain.append(row[column])

		chain.append(next_button if column >= 3 else back_button)
		focus_manager.set_vertical_navigation(chain, false)

	var footer: Array[Control] = [back_button, next_button]
	focus_manager.set_horizontal_navigation(footer, false)
	var first_row: Control = rows[0][0] if not rows.is_empty() else level_selector
	focus_manager.set_neighbors(back_button, (rows[rows.size() - 1][0] if not rows.is_empty() else level_selector))
	focus_manager.set_neighbors(next_button, (rows[rows.size() - 1][3] if not rows.is_empty() else fill_button))
	focus_manager.set_neighbors(level_selector, null, first_row)


# ------------------------------------------------------------
# Navigation
# ------------------------------------------------------------

func _leave(scene: String) -> void:
	race_config.remember_ai_slots()
	GameManager.set_pending_race_config(race_config.duplicate_config())
	NavigationManager.go(scene)


func _on_back_pressed() -> void:
	_leave("CarSelection")


func _on_next_pressed() -> void:
	_leave("RaceSetup")
