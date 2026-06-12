extends Node
class_name Typewriter

signal finished  # émis quand l'animation se termine (ou skip/annulation)

var _play_id: int = 0  # identifiant pour annuler une lecture en cours

func cancel() -> void:
	# Invalide la lecture en cours (si présente)
	_play_id += 1

func play(
	node: Control,
	full_text: String,
	cps: float = 40.0,
	punct_pause_ms: int = 80,
	allow_skip: bool = true
) -> void:
	# Nouvelle session → invalide la précédente
	_play_id += 1
	var my_id: int = _play_id

	if node == null or not is_instance_valid(node):
		emit_signal("finished")
		return

	var is_rich: bool = node is RichTextLabel

	# Init: on part d'un texte vide
	if is_rich:
		var rtl: RichTextLabel = node as RichTextLabel
		rtl.clear()
	else:
		var lbl: Label = node as Label
		lbl.text = ""

	# Sécurité vitesse
	var safe_cps: float = max(1.0, cps)
	var delay_per_char: float = 1.0 / safe_cps

	var i: int = 0
	var n: int = full_text.length()

	while i < n:
		# Annulé entre-temps ?
		if my_id != _play_id or not is_instance_valid(node):
			emit_signal("finished")
			return

		# Skip ?
		if allow_skip and Input.is_action_just_pressed("ui_accept"):
			_set_full(node, full_text, is_rich)
			emit_signal("finished")
			return

		var ch: String = full_text.substr(i, 1)
		_append_char(node, ch, is_rich)
		i += 1

		# Attente “tape au clavier”
		var t: SceneTreeTimer = get_tree().create_timer(delay_per_char)
		await t.timeout

		# Pause ponctuation (un poil plus longue pour "...")
		if punct_pause_ms > 0:
			if ch == ".":
				var extra: float = float(punct_pause_ms) / 1000.0
				# Ellipsis "..." => pause double
				if i + 1 < n and full_text.substr(i, 2) == "..":
					extra *= 2.0
				await get_tree().create_timer(extra).timeout
			elif ch == "," or ch == "!" or ch == "?" or ch == ":" or ch == ";":
				await get_tree().create_timer(float(punct_pause_ms) / 1000.0).timeout

	# Terminé
	emit_signal("finished")


# ---------- Helpers internes ----------

func _append_char(node: Control, ch: String, is_rich: bool) -> void:
	if not is_instance_valid(node):
		return
	if is_rich:
		var rtl: RichTextLabel = node as RichTextLabel
		rtl.append_text(ch)  # append = wrap naturel, pas de clear à chaque tick
	else:
		var lbl: Label = node as Label
		lbl.text += ch

func _set_full(node: Control, text: String, is_rich: bool) -> void:
	if not is_instance_valid(node):
		return
	if is_rich:
		var rtl: RichTextLabel = node as RichTextLabel
		rtl.clear()
		rtl.append_text(text)
	else:
		var lbl: Label = node as Label
		lbl.text = text
