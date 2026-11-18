extends HBoxContainer
class_name RaceParticipantHUD


@onready var name_label: Label = $Name
@onready var position_label: Label = $Position
@onready var lap_label: Label = $Lap
@onready var lap_time_label: Label = $LapTime
@onready var delta_label: Label = $Delta
@onready var best_lap_label: Label = $BestLap


var participant: RaceParticipantState = null
var race_controller: RaceController = null


const PLACE := {
	0: "XXXX",
	1: "1er",
	2: "2ème",
	3: "3ème",
	4: "4ème",
	5: "5ème",
	6: "6ème",
	7: "7ème",
	8: "8ème",
}


const POSITION_COLORS := {
	1: Color("#FFD700"),
	2: Color("#C0C0C0"),
	3: Color("#CD7F32"),
}


func setup(
	p_participant: RaceParticipantState,
	p_race_controller: RaceController
) -> void:

	participant = p_participant
	race_controller = p_race_controller

	name_label.text = " | " + participant.nickname

	# Joueurs humains : nom et informations à la couleur de leur voiture
	# (la position garde l'or, l'argent, le bronze ; l'écart, le vert
	# ou le rouge).
	if not participant.is_ai:
		var color := car_display_color(participant.car)

		for label in [name_label, lap_label, lap_time_label, best_lap_label]:
			label.modulate = color

	refresh()


## Couleur des joueurs humains si celle de la voiture est introuvable.
const HUMAN_COLOR := Color("#5ce1ff")

# Teinte moyenne de la carrosserie, par modèle (texture -> couleur).
static var _body_tints: Dictionary = {}


## Couleur visible de la carrosserie : teinte du dessin du modèle,
## multipliée par la couleur choisie (« Aucune » : teinte d'origine).
## Éclaircie si besoin pour rester lisible sur la piste.
static func car_display_color(car: Car) -> Color:
	if not is_instance_valid(car) or car.model == null:
		return HUMAN_COLOR

	var body := car.model.find_child("Body", true, false) as CanvasItem
	var tint_node: CanvasItem = body if body != null else car.model
	var sprite: AnimatedSprite2D = null

	for child in tint_node.find_children("*", "AnimatedSprite2D", true, false):
		sprite = child
		break

	var base := Color.WHITE

	if sprite != null and sprite.sprite_frames != null:
		var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)

		if texture != null:
			base = _body_tint(texture)

	var color := base * tint_node.modulate
	color.a = 1.0

	if color.get_luminance() < 0.45:
		color = color.lightened(0.45 - color.get_luminance() + 0.2)

	return color


## Teinte dominante d'un dessin : moyenne des pixels colorés (sinon de
## tous les pixels opaques).
static func _body_tint(texture: Texture2D) -> Color:
	if _body_tints.has(texture):
		return _body_tints[texture]

	var image := texture.get_image()
	var tint := Color.WHITE

	if image != null:
		if image.is_compressed():
			image.decompress()

		var colored := Vector3.ZERO
		var colored_count := 0
		var opaque := Vector3.ZERO
		var opaque_count := 0
		var step := maxi(1, int(image.get_width() * image.get_height() / 4096))

		for i in range(0, image.get_width() * image.get_height(), step):
			var pixel := image.get_pixel(i % image.get_width(), i / image.get_width())

			if pixel.a < 0.5:
				continue

			opaque += Vector3(pixel.r, pixel.g, pixel.b)
			opaque_count += 1

			if pixel.s > 0.35 and pixel.v > 0.25:
				colored += Vector3(pixel.r, pixel.g, pixel.b)
				colored_count += 1

		if colored_count > 0:
			var mean := colored / colored_count
			tint = Color(mean.x, mean.y, mean.z)
		elif opaque_count > 0:
			var mean := opaque / opaque_count
			tint = Color(mean.x, mean.y, mean.z)

	_body_tints[texture] = tint
	return tint


func refresh() -> void:

	if participant == null:
		return

	if race_controller == null:
		return

	# ============================================================
	# POSITION
	# ============================================================
	position_label.text = PLACE.get(
		participant.race_position,
		"XXXX"
	)

	_update_position_color()


	# ============================================================
	# TOUR
	# ============================================================
	lap_label.text = (
		" | TOUR %d"
		% participant.current_lap
	)

	# (Usure des pneus : jauge en bas à gauche de l'écran, TireGauge.)

	# Voie des stands : vitesse bridée.
	if not participant.is_ai and is_instance_valid(participant.car) and participant.car.is_speed_limited():
		lap_label.text += " | LIMITEUR"

	# Mode élimination : points et état dans la manche.
	if race_controller.is_elimination_mode():
		lap_label.text = " | %d PTS" % participant.points
		lap_time_label.text = (
			" | ÉLIMINÉ" if participant.eliminated else " | EN PISTE"
		)
		delta_label.text = ""
		best_lap_label.text = ""
		return


	# ============================================================
	# TEMPS DU TOUR EN COURS
	# ============================================================
	if participant.has_started_lap:

		var current_lap_time := (
			race_controller.get_race_time()
			- participant.lap_start_time
		)

		lap_time_label.text = (
			" | En cours: %s"
			% _format_time(current_lap_time)
		)

	else:

		lap_time_label.text = " | En cours: --:--.--"


	# ============================================================
	# DELTA DERNIER SECTEUR
	# ============================================================
	delta_label.text = (
		get_delta()
	)
	
	_update_delta_color()

	# ============================================================
	# MEILLEUR TOUR
	# ============================================================
	best_lap_label.text = (
		"Meilleur: %s"
		% _format_time(participant.best_lap_time)
	)


func get_delta() -> String:

	if participant.last_section_index < 0:
		return "--.---"

	if (
		participant.last_section_index
		>= participant.best_section_times.size()
	):
		return "--.---"

	var best_section_time := (
		participant.best_section_times[
			participant.last_section_index
		]
	)

	if best_section_time <= 0.0:
		return "--.---"

	return (
		"%+.3f"
		% participant.last_section_delta
	)

func _update_delta_color() -> void:

	var delta: float = participant.last_section_delta

	if participant.last_section_index < 0:
		delta_label.modulate = Color.WHITE
	elif delta < 0.0:
		delta_label.modulate = Color("#55DD55")
	elif delta > 0.0:
		delta_label.modulate = Color("#FF6666")
	else:
		delta_label.modulate = Color.WHITE

func _update_position_color() -> void:

	var race_position := participant.race_position

	if POSITION_COLORS.has(race_position):

		position_label.modulate = (
			POSITION_COLORS[race_position]
		)

	else:

		position_label.modulate = Color.WHITE


func _speed_to_kmh(speed: float) -> float:

	return speed * 0.1


func _format_time(time_seconds: float) -> String:

	if time_seconds <= 0.0:
		return "--:--.--"

	var minutes := int(time_seconds / 60)
	var seconds := int(time_seconds) % 60

	var centiseconds := int(
		(time_seconds - floor(time_seconds)) * 100.0
	)

	return "%02d:%02d.%02d" % [
		minutes,
		seconds,
		centiseconds
	]
