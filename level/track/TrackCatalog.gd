extends Node
class_name TrackCatalog


const TRACKS := [
	{
		"id": 0,
		"name": "Classic",
		"scene": "res://level/track/Track01.tscn"
	},
	{
		"id": 1,
		"name": "Padock 1",
		"scene": "res://level/track/Track02.tscn"
	},
	{
		"id": 2,
		"name": "Padock 2",
		"scene": "res://level/track/Track03.tscn"
	},
	{
		"id": 3,
		"name": "Padock 3",
		"scene": "res://level/track/Track04.tscn"
	},
	{
		"id": 4,
		"name": "Reverse",
		"scene": "res://level/track/Track05.tscn"
	}
]

static func get_tracks() -> Array:
	return TRACKS


static func get_track(track_id: int) -> Dictionary:
	for track_data: Dictionary in TRACKS:
		if track_data["id"] == track_id:
			return track_data

	push_warning("Circuit introuvable : " + str(track_id))
	return {}
