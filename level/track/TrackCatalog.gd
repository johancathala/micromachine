extends Node
class_name TrackCatalog


const TRACKS := [
	{
		"id": 0,
		"name": "Brissac",
		"scene": "res://level/track/Track01.tscn"
	},
	# Variantes de Brissac : même carte, autre cheminement
	# (générées par tools/track/build_brissac_variants.gd).
	{
		"id": 1,
		"name": "Brissac Paddock 1",
		"scene": "res://level/track/Track02.tscn"
	},
	{
		"id": 2,
		"name": "Brissac Paddock 2",
		"scene": "res://level/track/Track03.tscn"
	},
	{
		"id": 4,
		"name": "Brissac Reverse",
		"scene": "res://level/track/Track05.tscn"
	},
	{
		"id": 5,
		"name": "Alès - Pôle Mécanique",
		"scene": "res://level/track/TrackAles.tscn"
	}
]

## Aperçu du circuit (généré par tools/track/render_track_previews.gd).
static func get_preview(track_id: int) -> Texture2D:
	var path := "res://level/sprite/minia/track_%d.png" % track_id

	if ResourceLoader.exists(path):
		return load(path) as Texture2D

	return null


static func get_tracks() -> Array:
	return TRACKS


static func get_track(track_id: int) -> Dictionary:
	for track_data: Dictionary in TRACKS:
		if track_data["id"] == track_id:
			return track_data

	push_warning("Circuit introuvable : " + str(track_id))
	return {}
