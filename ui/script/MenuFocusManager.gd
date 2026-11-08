
extends Node
class_name MenuFocusManager


# ============================================================
# CONFIGURATION
# ============================================================

## Chemin du contrôle qui doit recevoir le focus à l'ouverture.
@export var initial_focus_path: NodePath

## Racine du menu contenant les contrôles.
var menu_root: Control

## Dernier contrôle ayant possédé le focus.
var last_focused_control: Control


# ============================================================
# INITIALISATION
# ============================================================

func _ready() -> void:
	menu_root = get_parent() as Control

	if menu_root == null:
		push_error(
			"MenuFocusManager doit être enfant d'un Control."
		)
		return

	# Attend que les contrôles soient prêts et intégrés à l'arbre.
	focus_initial.call_deferred()


# ============================================================
# FOCUS INITIAL
# ============================================================

func focus_initial() -> void:
	if initial_focus_path.is_empty():
		focus_first_available()
		return

	var control := menu_root.get_node_or_null(
		initial_focus_path
	) as Control

	if _is_focusable(control):
		set_focus(control)
	else:
		focus_first_available()


## Donne le focus au premier contrôle disponible du menu.
func focus_first_available() -> void:
	if menu_root == null:
		return

	var controls := _get_focusable_controls(menu_root)

	if controls.is_empty():
		return

	set_focus(controls[0])


## Donne le focus à un contrôle précis.
func set_focus(control: Control) -> void:
	if not _is_focusable(control):
		return

	control.grab_focus()
	last_focused_control = control


# ============================================================
# MÉMORISATION ET RESTAURATION
# ============================================================

## Mémorise le contrôle actuellement sélectionné.
func remember_focus() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()

	if focus_owner is Control:
		var control := focus_owner as Control

		if menu_root.is_ancestor_of(control) or control == menu_root:
			last_focused_control = control


## Restaure le dernier contrôle sélectionné.
## Si celui-ci n'est plus disponible, utilise le focus initial.
func restore_focus() -> void:
	if _is_focusable(last_focused_control):
		set_focus(last_focused_control)
	else:
		focus_initial()


# ============================================================
# NAVIGATION EXPLICITE
# ============================================================

## Définit les quatre voisins d'un contrôle.
## Un paramètre null signifie qu'aucun voisin explicite
## n'est défini dans cette direction.
func set_neighbors(
	current: Control,
	up: Control = null,
	down: Control = null,
	left: Control = null,
	right: Control = null
) -> void:

	if not _is_focusable(current):
		return

	if _is_focusable(up):
		current.focus_neighbor_top = current.get_path_to(up)

	if _is_focusable(down):
		current.focus_neighbor_bottom = current.get_path_to(down)

	if _is_focusable(left):
		current.focus_neighbor_left = current.get_path_to(left)

	if _is_focusable(right):
		current.focus_neighbor_right = current.get_path_to(right)


## Configure une navigation verticale entre plusieurs contrôles.
## Si wrap est activé, le dernier et le premier sont reliés.
func set_vertical_navigation(
	controls: Array[Control],
	_wrap: bool = true
) -> void:

	var available := _filter_focusable(controls)
	var count := available.size()

	if count < 2:
		return

	for i in range(count):
		var previous_index := i - 1
		var next_index := i + 1

		if _wrap:
			previous_index = posmod(previous_index, count)
			next_index = posmod(next_index, count)

		var up: Control = null
		var down: Control = null

		if previous_index >= 0:
			up = available[previous_index]

		if next_index < count:
			down = available[next_index]

		set_neighbors(
			available[i],
			up,
			down
		)


## Configure une navigation horizontale entre plusieurs contrôles.
func set_horizontal_navigation(
	controls: Array[Control],
	_wrap: bool = true
) -> void:

	var available := _filter_focusable(controls)
	var count := available.size()

	if count < 2:
		return

	for i in range(count):
		var previous_index := i - 1
		var next_index := i + 1

		if _wrap:
			previous_index = posmod(previous_index, count)
			next_index = posmod(next_index, count)

		var left: Control = null
		var right: Control = null

		if previous_index >= 0:
			left = available[previous_index]

		if next_index < count:
			right = available[next_index]

		set_neighbors(
			available[i],
			null,
			null,
			left,
			right
		)


# ============================================================
# OUTILS INTERNES
# ============================================================

func _is_focusable(control: Control) -> bool:
	if control == null:
		return false

	if not is_instance_valid(control):
		return false

	if not control.is_inside_tree():
		return false

	if not control.is_visible_in_tree():
		return false

	if control.focus_mode == Control.FOCUS_NONE:
		return false

	if control is BaseButton:
		if (control as BaseButton).disabled:
			return false

	if control is Range:
		if not (control as Range).editable:
			return false

	return true


func _filter_focusable(
	controls: Array[Control]
) -> Array[Control]:

	var result: Array[Control] = []

	for control in controls:
		if _is_focusable(control):
			result.append(control)

	return result


func _get_focusable_controls(
	parent: Node
) -> Array[Control]:

	var result: Array[Control] = []

	for child in parent.get_children():
		if child is Control:
			var control := child as Control

			if _is_focusable(control):
				result.append(control)

		result.append_array(
			_get_focusable_controls(child)
		)

	return result
