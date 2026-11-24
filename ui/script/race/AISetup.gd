extends Control

# ============================================================
# ÉCRAN DES IA (course classique et élimination, après les joueurs)
# ============================================================
#
# Une ligne par IA engagée : pilote, voiture et couleur. Les places
# libres sont celles que les joueurs n'occupent pas (8 au total). Les
# livrées restent uniques : une couleur déjà prise est grisée.
#
# Les pilotes viennent du roster (AIDriverRoster) : 24 noms uniques,
# 8 par niveau. Le pilote choisi fixe en interne son niveau et son
# style de pilotage ; le joueur ne voit que son nom, suivi de son
# niveau entre parenthèses. Un pilote déjà engagé est grisé.
#
# « Ajouter » et « Remplir » engagent des pilotes du niveau choisi en
# haut de l'écran, avec une voiture au hasard. La composition est
# reprise d'une course à l'autre (RaceConfig.remember_ai_slots).
#
# Pilote fantôme : à la place du pilote, on choisit le fantôme rejoué
# (le Platine, meilleur de tous, ou celui d'un joueur et d'une
# médaille : Or, Argent, Bronze) parmi ceux enregistrés avec sa
# voiture ; il en prend le nom (« Flavien Or »). Sans enregistrement sur le
# circuit choisi ensuite, il roule en Expert. Pas de fantôme en
# élimination (il ne peut pas être éliminé).
# ============================================================

const GHOST_DESCRIPTION := "Fantôme : rejoue un tour enregistré en contre-la-montre avec sa voiture, tour après tour. Il traverse les autres voitures et ne peut pas exploser. Ses pneus s'usent et il passe au stand comme les autres."

# Fantômes enregistrés, par voiture (lus une fois par écran).
var _ghost_cache: Dictionary = {}

var race_config: RaceConfig
var _description_slot := -1
var _description_kind := "driver"
var _color_icons: Dictionary = {}
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
	_sanitize_slots()

	for level in [RaceConfig.AIPilot.NOVICE, RaceConfig.AIPilot.MEDIUM, RaceConfig.AIPilot.EXPERT]:
		level_selector.add_item(RaceConfig.AI_PILOT_NAMES[level], level)

	# Fantômes : tirés au hasard parmi ceux enregistrés (pas en
	# élimination).
	if not race_config.is_elimination():
		level_selector.add_item(RaceConfig.AI_PILOT_NAMES[RaceConfig.AIPilot.GHOST], RaceConfig.AIPilot.GHOST)

		if _all_ghosts().is_empty():
			level_selector.set_item_text(
				level_selector.get_item_index(RaceConfig.AIPilot.GHOST), "Fantôme (aucun enregistré)"
			)
			level_selector.set_item_disabled(level_selector.get_item_index(RaceConfig.AIPilot.GHOST), true)

	var level_index := level_selector.get_item_index(race_config.ai_difficulty)

	if level_index < 0 or level_selector.is_item_disabled(level_index):
		race_config.ai_difficulty = RaceConfig.get_ai_difficulty(race_config.ai_difficulty)
		level_index = level_selector.get_item_index(race_config.ai_difficulty)

	level_selector.select(level_index)
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


## Premier pilote libre (de ce niveau si possible).
func _first_free_driver(level: int, used: Dictionary) -> Dictionary:
	for driver in AIDriverRoster.for_level(level):
		if not used.has(String(driver["id"])):
			return driver

	for driver in AIDriverRoster.get_drivers():
		if not used.has(String(driver["id"])):
			return driver

	return {}


## Composition reprise d'une version précédente : un même pilote ne
## court qu'une fois. En élimination, un fantôme redevient un pilote
## (il ne peut pas être éliminé).
func _sanitize_slots() -> void:
	var used: Dictionary = {}
	var kept: Array[Dictionary] = []

	for slot in race_config.ai_slots:
		var level := RaceConfig.get_ai_difficulty(
			int(slot.get("pilot", RaceConfig.AIPilot.MEDIUM))
		)
		var driver := RaceConfig.get_slot_driver(slot)

		# Fantôme conservé (course classique) ; impossible en élimination.
		if int(slot.get("pilot", -1)) == RaceConfig.AIPilot.GHOST:
			if not race_config.is_elimination():
				kept.append(slot)
				continue

			driver = _first_free_driver(RaceConfig.AIPilot.EXPERT, used)
		elif driver.is_empty():
			driver = _first_free_driver(level, used)
		elif used.has(String(driver["id"])):
			driver = _first_free_driver(int(driver["level"]), used)

		# Plus aucun pilote libre : l'emplacement en double est retiré.
		if driver.is_empty():
			continue

		used[String(driver["id"])] = true
		slot["pilot"] = int(driver["level"])
		slot["driver"] = String(driver["id"])
		slot["style"] = String(driver["style"])
		slot.erase("ghost")
		slot.erase("ghost_name")
		kept.append(slot)

	race_config.ai_slots = kept


## Pilotes déjà engagés (sauf l'emplacement indiqué), par identifiant.
func _used_driver_ids(except_slot: int = -1) -> Dictionary:
	var used: Dictionary = {}

	for i in range(race_config.ai_slots.size()):
		if i == except_slot:
			continue

		var driver := RaceConfig.get_slot_driver(race_config.ai_slots[i])

		if not driver.is_empty():
			used[String(driver["id"])] = true

	return used


## Pilotes du niveau qui ne sont pas encore engagés.
func _available_drivers(level: int) -> Array[Dictionary]:
	var used := _used_driver_ids()
	var available: Array[Dictionary] = []

	for driver in AIDriverRoster.for_level(level):
		if not used.has(String(driver["id"])):
			available.append(driver)

	return available


## Voitures proposées aux IA ajoutées : celles du groupe le plus élevé
## des voitures choisies par les joueurs humains (D à S). La voiture
## reste modifiable sans restriction ensuite.
func _ai_car_pool() -> Array[CarDefinition]:
	var group := CarCatalog.highest_group(_human_car_ids())
	var pool := CarCatalog.get_cars_in_group(group)

	if pool.is_empty():
		return cars

	return pool


## Ajoute un pilote avec une voiture du groupe et une couleur au hasard
## (la grille attribue une livrée libre).
func _append_driver(driver: Dictionary) -> void:
	var pool := _ai_car_pool()
	var car_id := ""
	var color_id := String(colors[randi() % colors.size()]["id"])

	if not pool.is_empty():
		car_id = pool[randi() % pool.size()].id

	race_config.ai_slots.append({
		"pilot": int(driver["level"]),
		"driver": String(driver["id"]),
		"style": String(driver["style"]),
		"car_id": car_id,
		"color_id": color_id
	})
	_sync()


## Une IA peut-elle encore être ajoutée au niveau choisi ?
func _can_add_ai() -> bool:
	if _free_places() <= 0:
		return false

	if race_config.ai_difficulty == RaceConfig.AIPilot.GHOST:
		return not _all_ghosts().is_empty()

	return not _available_drivers(race_config.ai_difficulty).is_empty()


## Nouvelle IA au niveau choisi, parmi les pilotes encore libres.
func _add_ai() -> void:
	if _free_places() <= 0:
		return

	if race_config.ai_difficulty == RaceConfig.AIPilot.GHOST:
		_add_ghost()
		return

	var available := _available_drivers(race_config.ai_difficulty)

	if available.is_empty():
		return

	_append_driver(available.pick_random())


## Tous les fantômes enregistrés, toutes voitures : [{car_id, key,
## nickname}] (lus une fois par écran).
func _all_ghosts() -> Array[Dictionary]:
	var ghosts: Array[Dictionary] = []

	for car in cars:
		for recorder in _ghost_recorders_for(car.id):
			ghosts.append({"car_id": car.id, "key": recorder["key"], "nickname": recorder["nickname"]})

	return ghosts


func _ghost_recorders_for(car_id: String) -> Array[Dictionary]:
	if not _ghost_cache.has(car_id):
		_ghost_cache[car_id] = GhostManager.list_recorders(car_id)

	return _ghost_cache[car_id]


## Nouvelle IA fantôme : un fantôme enregistré au hasard (sa voiture
## avec), en évitant ceux déjà engagés tant qu'il en reste.
func _add_ghost() -> void:
	var ghosts := _all_ghosts()

	if ghosts.is_empty():
		return

	var unused: Array[Dictionary] = []

	for ghost in ghosts:
		var taken := false

		for slot in race_config.ai_slots:
			if (
				int(slot.get("pilot", -1)) == RaceConfig.AIPilot.GHOST
				and String(slot.get("car_id", "")) == ghost["car_id"]
				and String(slot.get("ghost", "")) == ghost["key"]
			):
				taken = true

		if not taken:
			unused.append(ghost)

	var pick: Dictionary = (unused if not unused.is_empty() else ghosts).pick_random()

	race_config.ai_slots.append({
		"pilot": RaceConfig.AIPilot.GHOST,
		"style": AIStyle.DEFAULT_ID,
		"ghost": pick["key"],
		"ghost_name": pick["nickname"],
		"car_id": pick["car_id"],
		"color_id": String(colors[randi() % colors.size()]["id"])
	})
	_sync()


func _on_add_pressed() -> void:
	_add_ai()
	_rebuild_rows()


func _on_fill_pressed() -> void:
	# Tous les pilotes libres du niveau choisi.
	while _free_places() > 0:
		var before := race_config.ai_slots.size()
		_add_ai()

		# Plus aucun pilote (ou fantôme) libre : on s'arrête.
		if race_config.ai_slots.size() == before:
			break

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


## Changement de pilote : le roster fixe le niveau et le style.
func _on_driver_selected(index: int, slot_index: int, selector: OptionButton) -> void:
	var drivers := AIDriverRoster.get_drivers()
	var driver_index := selector.get_item_id(index)

	if driver_index < 0 or driver_index >= drivers.size():
		return

	var driver: Dictionary = drivers[driver_index]
	var slot := race_config.ai_slots[slot_index]
	slot["driver"] = String(driver["id"])
	slot["pilot"] = int(driver["level"])
	slot["style"] = String(driver["style"])
	_sync()
	_rebuild_rows()
	_show_description(slot_index, "driver")


## Choix du pilote parmi ceux du roster : les noms déjà engagés sont
## grisés (un pilote ne court qu'une fois).
func _fill_driver_selector(selector: OptionButton, slot_index: int) -> void:
	var slot := race_config.ai_slots[slot_index]
	var current := RaceConfig.get_slot_driver(slot)
	var used := _used_driver_ids(slot_index)
	var drivers := AIDriverRoster.get_drivers()

	for i in range(drivers.size()):
		var driver: Dictionary = drivers[i]
		var taken := used.has(String(driver["id"]))
		var label := "%s (%s)" % [
			String(driver["name"]), RaceConfig.AI_PILOT_NAMES[int(driver["level"])]
		]
		selector.add_item(label + (" (pris)" if taken else ""), i)
		selector.set_item_disabled(i, taken)

		if not current.is_empty() and driver["id"] == current["id"]:
			selector.select(i)

	selector.item_selected.connect(_on_driver_selected.bind(slot_index, selector))


func _show_car_description(car: CarDefinition) -> void:
	description_label.text = "%s (groupe %s) : %s" % [car.display_name, car.group, car.description]


## Description du niveau choisi pour les IA ajoutées.
func _show_level_hint() -> void:
	if race_config.ai_difficulty == RaceConfig.AIPilot.GHOST:
		description_label.text = GHOST_DESCRIPTION + " « Ajouter » et « Remplir » prennent des fantômes au hasard parmi ceux enregistrés."
		return

	var level := RaceConfig.get_ai_difficulty(race_config.ai_difficulty)
	description_label.text = "Niveau %s : %s — voitures ajoutées : groupe %s (le plus élevé des joueurs)." % [
		RaceConfig.AI_PILOT_NAMES[level],
		AIStyle.LEVEL_DESCRIPTIONS[level],
		CarCatalog.highest_group(_human_car_ids())
	]


## Voitures des joueurs humains (pour le groupe des IA ajoutées).
func _human_car_ids() -> Array:
	var ids: Array = []

	for participant in race_config.participants:
		if not bool(participant.get("is_ai", false)):
			ids.append(String(participant.get("car_id", "")))

	return ids


## Fantômes enregistrés avec la voiture de l'IA : le meilleur (connu
## une fois le circuit choisi), puis ceux de chaque joueur.
func _fill_ghost_selector(selector: OptionButton, slot_index: int) -> void:
	var slot := race_config.ai_slots[slot_index]
	var recorders := _ghost_recorders(slot_index)
	var current := String(slot.get("ghost", ""))

	selector.add_item("Platine (le meilleur)", 0)
	selector.select(0)

	for i in range(recorders.size()):
		selector.add_item(String(recorders[i]["nickname"]), i + 1)

		if recorders[i]["key"] == current:
			selector.select(i + 1)

	# Joueur sans fantôme avec cette voiture : retour au meilleur.
	if selector.selected == 0 and not current.is_empty():
		slot.erase("ghost")
		slot.erase("ghost_name")

	selector.item_selected.connect(_on_ghost_selected.bind(slot_index, recorders))


func _ghost_recorders(slot_index: int) -> Array[Dictionary]:
	return _ghost_recorders_for(String(race_config.get_participant(_participant_index(slot_index)).get("car_id", "")))


func _on_ghost_selected(index: int, slot_index: int, recorders: Array[Dictionary]) -> void:
	var slot := race_config.ai_slots[slot_index]

	if index == 0:
		slot.erase("ghost")
		slot.erase("ghost_name")
	else:
		slot["ghost"] = String(recorders[index - 1]["key"])
		slot["ghost_name"] = String(recorders[index - 1]["nickname"])

	_sync()
	_rebuild_rows()
	_show_description(slot_index, "ghost")


## Description d'un pilote fantôme : ses tours enregistrés par circuit.
func _ghost_description(slot_index: int) -> String:
	var slot := race_config.ai_slots[slot_index]
	var key := String(slot.get("ghost", ""))
	var recorders := _ghost_recorders(slot_index)
	var car := CarCatalog.get_car(String(race_config.get_participant(_participant_index(slot_index)).get("car_id", "")))
	var car_name := car.display_name if car != null else "cette voiture"

	if recorders.is_empty():
		return "Aucun fantôme enregistré avec la %s : ce pilote roulera en Expert. Enregistre des tours en contre-la-montre." % car_name

	var best_by_track: Dictionary = {}

	for recorder in recorders:
		if not key.is_empty() and recorder["key"] != key:
			continue

		for lap in recorder["laps"]:
			var track_id := int(lap["track_id"])

			if not best_by_track.has(track_id) or float(lap["lap_time"]) < float(best_by_track[track_id]["lap_time"]):
				best_by_track[track_id] = {"lap_time": float(lap["lap_time"]), "nickname": recorder["nickname"]}

	var parts: PackedStringArray = []

	for track in TrackCatalog.get_tracks():
		var track_id := int(track.get("id", -1))

		if best_by_track.has(track_id):
			var entry: Dictionary = best_by_track[track_id]
			parts.append("%s %s%s" % [
				String(track.get("name", "")),
				GhostManager._format_time(float(entry["lap_time"])),
				"" if not key.is_empty() else " (%s)" % entry["nickname"]
			])

	var who := "le Platine (meilleur fantôme de tous)" if key.is_empty() else "le fantôme " + String(slot.get("ghost_name", key))
	return "Rejoue %s en %s : %s. Ailleurs, roule en Expert." % [who, car_name, ", ".join(parts)]


## Fiche du pilote : nom, niveau et description de son style.
func _driver_description(slot: Dictionary) -> String:
	var driver := RaceConfig.get_slot_driver(slot)

	if driver.is_empty():
		return ""

	var level := int(driver["level"])
	var style := AIStyle.get_style(String(driver["style"]))
	return "%s (%s) : %s" % [
		String(driver["name"]), RaceConfig.AI_PILOT_NAMES[level], String(style["description"])
	]


## Description sous le tableau : pilote, fantôme ou voiture de l'IA
## survolée / sélectionnée (souris, clavier ou manette).
func _show_description(slot_index: int, kind: String) -> void:
	if slot_index < 0 or slot_index >= race_config.ai_slots.size():
		return

	_description_slot = slot_index
	_description_kind = kind
	var slot := race_config.ai_slots[slot_index]
	var pilot := int(slot.get("pilot", RaceConfig.AIPilot.MEDIUM))

	if kind == "car":
		var car := CarCatalog.get_car(String(race_config.get_participant(_participant_index(slot_index)).get("car_id", "")))

		if car != null:
			_show_car_description(car)
	elif pilot == RaceConfig.AIPilot.GHOST:
		description_label.text = _ghost_description(slot_index) if kind == "ghost" else GHOST_DESCRIPTION
	elif kind == "driver":
		description_label.text = _driver_description(slot)
	else:
		var level := RaceConfig.get_ai_difficulty(pilot)
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

	var count := race_config.ai_slots.size()

	title_label.text = "INTELLIGENCES ARTIFICIELLES (%d / %d)" % [count, race_config.get_max_ai_count()]
	empty_label.visible = count == 0
	add_button.disabled = not _can_add_ai()
	fill_button.disabled = not _can_add_ai()
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
		_show_description(0, "driver")

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


## Largeurs des colonnes (px) : identiques pour toutes les lignes, pour
## que les choix restent alignés.
const COLUMN_WIDTHS := {
	"swatch": 28, "driver": 360, "car": 400, "color": 300, "remove": 140
}
const ICON_SIZE := 44
# Colonnes étirées sur toute la largeur, dans les mêmes proportions pour
# toutes les lignes (la pastille garde sa taille).
const FIXED_COLUMNS := ["swatch"]


## Largeur d'une colonne : minimale, puis étirée dans sa proportion.
func _size_column(control: Control, column: String) -> void:
	control.custom_minimum_size.x = COLUMN_WIDTHS[column]

	if not FIXED_COLUMNS.has(column):
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.size_flags_stretch_ratio = COLUMN_WIDTHS[column] / 100.0


## En-têtes des colonnes, alignés sur les lignes.
func _build_header() -> void:
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	rows_box.add_child(header)

	for column in [
		["swatch", ""], ["driver", "Pilote"], ["car", "Voiture"],
		["color", "Couleur"], ["remove", ""]
	]:
		var label := Label.new()
		label.text = column[1]
		label.clip_text = true
		_size_column(label, column[0])
		label.add_theme_font_size_override("font_size", 24)
		label.modulate = Color(1, 1, 1, 0.75)
		header.add_child(label)


## Choix d'une colonne : largeur fixe, texte aligné à gauche.
func _column_selector(selector_name: String, column: String) -> OptionButton:
	var selector := OptionButton.new()
	selector.name = selector_name
	_size_column(selector, column)
	selector.alignment = HORIZONTAL_ALIGNMENT_LEFT
	selector.clip_text = true
	selector.add_theme_constant_override("icon_max_width", ICON_SIZE)
	selector.get_popup().add_theme_constant_override("icon_max_width", ICON_SIZE)
	return selector


## Pastille de couleur (icône des choix de couleur), mise en cache.
func _color_icon(color: Color) -> Texture2D:
	var key := color.to_html()

	if not _color_icons.has(key):
		var image := Image.create(28, 28, false, Image.FORMAT_RGBA8)
		image.fill(color)
		# Liseré sombre : une couleur claire reste visible.
		for k in range(28):
			for edge in [0, 27]:
				image.set_pixel(k, edge, Color(0, 0, 0, 0.6))
				image.set_pixel(edge, k, Color(0, 0, 0, 0.6))
		_color_icons[key] = ImageTexture.create_from_image(image)

	return _color_icons[key]


## Ligne d'une IA ; renvoie ses commandes (ordre de navigation).
func _build_row(slot_index: int) -> Array[Control]:
	var participant := race_config.get_participant(_participant_index(slot_index))
	var slot := race_config.ai_slots[slot_index]

	var row := HBoxContainer.new()
	row.name = "Row%d" % slot_index
	row.add_theme_constant_override("separation", 12)
	rows_box.add_child(row)

	# Pastille de couleur.
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(COLUMN_WIDTHS["swatch"], 28)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var color_data := ColorCatalog.get_color(String(participant.get("color_id", "")))
	swatch.color = color_data.get("color", Color.WHITE)
	row.add_child(swatch)

	# Pilote : le nom du roster (niveau entre parenthèses) ; pour un
	# fantôme, le joueur dont le fantôme (enregistré avec cette
	# voiture) est rejoué.
	var driver_selector := _column_selector("Driver", "driver")
	var ghost := int(slot.get("pilot", RaceConfig.AIPilot.MEDIUM)) == RaceConfig.AIPilot.GHOST

	if ghost:
		_fill_ghost_selector(driver_selector, slot_index)
	else:
		_fill_driver_selector(driver_selector, slot_index)

	var driver_kind := "ghost" if ghost else "driver"
	driver_selector.focus_entered.connect(_show_description.bind(slot_index, driver_kind))
	driver_selector.mouse_entered.connect(_show_description.bind(slot_index, driver_kind))
	row.add_child(driver_selector)

	# Voiture.
	# Voiture : miniature devant le nom.
	var car_selector := _column_selector("Car", "car")
	var car_id := String(participant.get("car_id", ""))

	for i in range(cars.size()):
		if cars[i].preview_texture != null:
			car_selector.add_icon_item(cars[i].preview_texture, cars[i].display_name, i)
		else:
			car_selector.add_item(cars[i].display_name, i)

		if cars[i].id == car_id:
			car_selector.select(i)

	car_selector.item_selected.connect(_on_car_selected.bind(slot_index, car_selector))
	car_selector.focus_entered.connect(_show_description.bind(slot_index, "car"))
	car_selector.mouse_entered.connect(_show_description.bind(slot_index, "car"))
	# Liste ouverte : description de la voiture survolée.
	car_selector.get_popup().id_focused.connect(func(id: int) -> void: _show_car_description(cars[id]))
	row.add_child(car_selector)

	# Couleur : celles déjà prises pour ce modèle sont grisées.
	# Couleur : pastille devant le nom ; celles déjà prises pour ce modèle
	# sont grisées.
	var color_selector := _column_selector("Color", "color")
	var participant_index := _participant_index(slot_index)

	for i in range(colors.size()):
		var color_id := String(colors[i]["id"])
		var taken := race_config.is_livery_taken(car_id, color_id, participant_index)
		color_selector.add_icon_item(
			_color_icon(colors[i]["color"]),
			String(colors[i]["name"]) + (" (prise)" if taken else ""),
			i
		)
		color_selector.set_item_disabled(i, taken)

		if color_id == String(participant.get("color_id", "")):
			color_selector.select(i)

	color_selector.item_selected.connect(_on_color_selected.bind(slot_index, color_selector))
	row.add_child(color_selector)

	var remove := Button.new()
	remove.name = "Remove"
	remove.text = "RETIRER"
	_size_column(remove, "remove")
	remove.add_to_group("audio_back")
	remove.pressed.connect(_on_remove_pressed.bind(slot_index))
	row.add_child(remove)

	var controls: Array[Control] = [driver_selector, car_selector, color_selector, remove]

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

	for column in range(4):
		var chain: Array[Control] = [toolbar[column]]

		for row: Array in rows:
			chain.append(row[column])

		chain.append(next_button if column >= 2 else back_button)
		focus_manager.set_vertical_navigation(chain, false)

	var footer: Array[Control] = [back_button, next_button]
	focus_manager.set_horizontal_navigation(footer, false)
	var first_row: Control = rows[0][0] if not rows.is_empty() else level_selector
	focus_manager.set_neighbors(back_button, (rows[rows.size() - 1][0] if not rows.is_empty() else level_selector))
	focus_manager.set_neighbors(next_button, (rows[rows.size() - 1][2] if not rows.is_empty() else fill_button))
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
