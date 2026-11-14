extends SceneTree

# ============================================================
# Séparation carte / circuit
#
#   godot --headless --path . -s tools/track/split_track_maps.gd
#
# Une CARTE (level/map/) ne contient que le décor et la physique du
# lieu : couches de tuiles, obstacles, eau, fond. Un CIRCUIT
# (level/track/) intègre une carte et définit sa propre logique de
# course : Sections, SpawnPoints, PitStop, feux de départ, trajectoire
# de l'IA (RacingLine). Plusieurs circuits partagent ainsi une même
# carte sans dupliquer ses sections ni son stand.
#
# 1. Brissac (Track01) : la carte est extraite dans level/map/, le
#    circuit garde sa logique et intègre la carte.
# 2. Variantes de Brissac (Track02, Track03, Track05) : elles
#    intégraient Track01 en entier (sections et stand compris) ; elles
#    intègrent désormais la seule carte, et reprennent le stand de
#    Brissac (même voie des stands).
#
# Les identifiants (uid) des scènes de circuit sont conservés.
# ============================================================

## Nœuds de logique de course (restent dans le circuit).
const LOGIC_NODES := ["Sections", "SpawnPoints", "PitStop", "RaceStartLightsMap", "Cars", "RacingLine"]

const SPLITS := [
	{
		"track": "res://level/track/Track01.tscn",
		"map": "res://level/map/BrissacMap.tscn",
		"map_root": "BrissacMap",
		"instance_name": "Brissac"
	}
]

const BRISSAC_TRACK := "res://level/track/Track01.tscn"
const BRISSAC_MAP := "res://level/map/BrissacMap.tscn"
const VARIANTS := [
	"res://level/track/Track02.tscn",
	"res://level/track/Track03.tscn",
	"res://level/track/Track05.tscn"
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://level/map"))

	for split in SPLITS:
		if not _split(split):
			quit(1)
			return

	for path in VARIANTS:
		if not _update_variant(path):
			quit(1)
			return

	quit()


func _split(split: Dictionary) -> bool:
	var track_path: String = split["track"]
	var packed := load(track_path) as PackedScene
	var track := packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as Node2D

	if track.get_node_or_null(String(split["instance_name"])) != null:
		print("%s : déjà séparé" % track_path)
		track.free()
		return true

	# ---- Carte : tout sauf la logique de course ----
	var map_root := Node2D.new()
	map_root.name = split["map_root"]
	map_root.y_sort_enabled = track.y_sort_enabled

	for child in track.get_children():
		if LOGIC_NODES.has(String(child.name)):
			continue

		track.remove_child(child)
		map_root.add_child(child)
		_reown(child, track, map_root)

	var map_scene := PackedScene.new()

	if map_scene.pack(map_root) != OK or ResourceSaver.save(map_scene, split["map"]) != OK:
		push_error("Échec de l'enregistrement de " + String(split["map"]))
		return false

	map_root.free()

	# ---- Circuit : carte intégrée + logique ----
	var map_instance := (load(split["map"]) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	map_instance.name = split["instance_name"]
	track.add_child(map_instance)
	track.move_child(map_instance, 0)
	map_instance.owner = track

	if packed.pack(track) != OK or ResourceSaver.save(packed, track_path) != OK:
		push_error("Échec de l'enregistrement de " + track_path)
		return false

	print("%s : carte -> %s ; circuit : %s" % [
		track_path, split["map"], ", ".join(track.get_children().map(func(n): return String(n.name)))
	])
	track.free()
	return true


func _update_variant(path: String) -> bool:
	var packed := load(path) as PackedScene
	var variant := packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as Node2D
	var old_map := variant.get_node_or_null("Brissac")

	if old_map == null:
		push_error(path + " : nœud Brissac absent")
		return false

	var index := old_map.get_index()
	variant.remove_child(old_map)
	old_map.free()

	var map_instance := (load(BRISSAC_MAP) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	map_instance.name = "Brissac"
	variant.add_child(map_instance)
	variant.move_child(map_instance, index)
	map_instance.owner = variant

	# Stand : celui de Brissac (même voie des stands).
	var old_pit := variant.get_node_or_null("PitStop")
	var pit_index := variant.get_child_count()

	if old_pit != null:
		pit_index = old_pit.get_index()
		variant.remove_child(old_pit)
		old_pit.free()

	var brissac := (load(BRISSAC_TRACK) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	var pit := brissac.get_node("PitStop").duplicate()
	variant.add_child(pit)
	variant.move_child(pit, pit_index)
	_reown(pit, null, variant, true)
	brissac.free()

	if packed.pack(variant) != OK or ResourceSaver.save(packed, path) != OK:
		push_error("Échec de l'enregistrement de " + path)
		return false

	print("%s : carte Brissac seule, stand de Brissac (%d zones)" % [path, pit.get_child_count()])
	variant.free()
	return true


## Propriétaire des nœuds déplacés : ceux qui appartenaient à l'ancienne
## racine (ou à personne, `force`) passent à la nouvelle. Les nœuds
## internes d'une scène instanciée gardent leur propriétaire.
func _reown(node: Node, old_owner: Node, new_owner: Node, force: bool = false) -> void:
	if node != new_owner and (node.owner == old_owner or force):
		node.owner = new_owner

	# On descend aussi dans les scènes instanciées : des nœuds ajoutés
	# dans le circuit sous une instance (zones d'eau...) appartiennent à
	# l'ancienne racine. Les nœuds propres à l'instance ne sont pas
	# touchés (autre propriétaire), sauf en mode `force`.
	if force and not node.scene_file_path.is_empty() and node != new_owner:
		return

	for child in node.get_children():
		_reown(child, old_owner, new_owner, force)
