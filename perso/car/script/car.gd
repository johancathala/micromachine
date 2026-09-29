"""
Voiture 2D "arcade réaliste" + adhérence modulée par la surface (Godot 4)

Principe surface:
- Un RayCast2D pointe vers le sol (node requis: RayCast2D nommé "GroundRay").
- Le collider touché (TileMap, StaticBody2D, etc.) doit être dans un groupe:
  "asphalt", "gravel", "grass", "mud", "ice" (modifiable).
- Chaque surface influence:
  - grip latéral (tenue de route / drift)
  - résistance au roulement (perte de vitesse)
  - puissance moteur (optionnel, léger)
  - puissance de frein (optionnel, surtout sur glace)

Option alternative (si vous ne voulez pas de groupes):
- Vous pouvez remplacer get_surface_profile() par une lecture de custom_data TileMap.
"""
extends CharacterBody2D

class_name Car

signal speed_changed(new_speed)
# ---------------------------
# NODES
# ---------------------------
@onready var ground_ray: RayCast2D = $GroundRay
@onready var camera: Camera2D = $"Camera2D" # Assurez-vous que la caméra est un enfant nommé "Camera2D"
@export var skid_node_path: NodePath
@onready var skid_node: Node2D = get_node("../SkidMarks")
#@onready var skid_node: Node2D = get_parent().get_node("SkidMarks")
@onready var smoke_left: GPUParticles2D = $SmokeLeft
@onready var smoke_right: GPUParticles2D = $SmokeRight
@onready var engine_idle_sound: AudioStreamPlayer2D = $EngineIdleSound
@onready var engine_running_sound: AudioStreamPlayer2D = $EngineRunningSound
@onready var engine_rupteur_sound: AudioStreamPlayer2D = $EngineRupeurSound
@onready var skid_sound: AudioStreamPlayer2D = $SkidSound
@onready var collision_sound: AudioStreamPlayer2D = $CollisionSound

#CUSTOM CAR MODEL
@onready var model: Node2D = $Model

var car_sprite: AnimatedSprite2D
var definition: CarDefinition

@export var car_name : String = "Voiture"

var car_can_move: bool = false
# ---------------------------
# FX STATE
# ---------------------------
var left_line: Line2D = null
var right_line: Line2D = null
@export var max_points_per_line := 80
var min_distance : float = 5.0
var threshold : float = 0.3
# Variables speed et accélération pour le management des son moteur
var speed: float = 0.0
var acceleration: float = 0.0
var previous_speed: float = 0.0
# Management des sons de collision
var last_collision_time: float = 0.0
@export var collision_cooldown: float = 0.3  # en secondes

# ---------------------------
# COLLISION
# ---------------------------
# Coefficient de rebond (0 = pas de rebond, 1 = rebond parfait)
@export_range(0.0, 3.0, 0.01) var bounce_factor: float = 0.8

# ---------------------------
# TUNING (moteur / vitesses)
# ---------------------------
# Force d'accélération en avant (modulée par la surface)
@export_range(0.0, 5000.0, 0.1) var engine_force: float = 1300.0
# Force de freinage (modulée par la surface)
@export_range(0.0, 5000.0, 0.1) var brake_force: float = 1700.0
# Force d'accélération en marche arrière (modulée par la surface)
@export_range(0.0, 2000.0, 0.1) var reverse_force: float = 900.0
# Vitesse maximale en avant
@export_range(0.0, 3000.0, 0.1) var max_speed: float = 2000.0
# Vitesse maximale en marche arrière
@export_range(0.0, 1000.0, 0.1) var max_reverse_speed: float = 450.0

# ---------------------------
# TUNING (résistances)
# ---------------------------
# Résistance au roulement (perte de vitesse au sol, modulée par la surface)
@export_range(0.0, 1000.0, 0.1) var rolling_resistance: float = 140.0
# Résistance de l'air (freinage aérodynamique à haute vitesse)
@export_range(0.0, 0.01, 0.0001) var air_drag: float = 0.0009

# Grip "de base" (asphalte-like)
# Adhérence latérale de base (résistance au dérapage à basse vitesse)
@export_range(0.0, 50.0, 0.1) var lateral_grip: float = 10.0
# Adhérence latérale à haute vitesse (réduite pour simuler la perte de contrôle)
@export_range(0.0, 50.0, 0.1) var lateral_grip_at_high_speed: float = 2.0
# Vitesse où l'adhérence commence à diminuer
@export_range(0.0, 3000.0, 1.0) var high_speed_grip_start: float = 300.0
# Vitesse où l'adhérence atteint sa valeur haute vitesse
@export_range(0.0, 3000.0, 1.0) var high_speed_grip_end: float = 1600

# ---------------------------
# TUNING (direction)
# ---------------------------
# Angle maximal de braquage des roues
@export_range(0.0, deg_to_rad(90.0), 0.01) var max_steer_angle: float = deg_to_rad(35.0)
# Vitesse de rotation des roues vers l'angle cible
@export_range(0.0, 20.0, 0.1) var steer_speed: float = 4.0
# Vitesse de retour des roues au centre
@export_range(0.0, 20.0, 0.1) var steer_return_speed: float = 6.0
# Efficacité de la direction à basse vitesse
@export_range(0.0, 5.0, 0.01) var steering_response_low_speed: float = 1.0
# Efficacité de la direction à haute vitesse (réduite)
@export_range(0.0, 5.0, 0.01) var steering_response_high_speed: float = 0.45
# Vitesse où la réponse directionnelle commence à diminuer
@export_range(0.0, 3000.0, 1.0) var steering_high_speed_start: float = 300.0
# Vitesse où la réponse directionnelle atteint sa valeur haute vitesse
@export_range(0.0, 3000.0, 1.0) var steering_high_speed_end: float = 1600

# ---------------------------
# TUNING (empattement / rotation)
# ---------------------------
# Distance entre les essieux (affecte la rotation)
@export_range(0.0, 200.0, 0.1) var wheel_base: float = 62.0
# Vitesse minimale pour que la direction fonctionne
@export_range(0.0, 200.0, 0.1) var min_speed_for_steer: float = 30.0
# Distance entre les roues (affecte les trace de dérapage)
@export var wheel_spacing: float = 18.0

# ---------------------------
# TUNING (frein à main optionnel)
# ---------------------------
# Multiplicateur d'adhérence latérale avec frein à main (réduit pour drift)
@export_range(0.0, 1.0, 0.01) var handbrake_grip_multiplier: float = 0.05
# Multiplicateur de force de frein avec frein à main
@export_range(0.0, 1.0, 0.01) var handbrake_brake_multiplier: float = 0.4

# ---------------------------
# CAMERA ZOOM (ajout)
# ---------------------------
# Zoom minimal de la caméra (à haute vitesse)
@export_range(0.1, 4.0, 0.1) var camera_zoom_min: float = 0.3
# Zoom maximal de la caméra (à basse vitesse)
@export_range(0.1, 4.0, 0.1) var camera_zoom_max: float = 1.8
# Vitesse d'adaptation du zoom
@export_range(0.1, 1.0, 0.01) var camera_zoom_speed: float = 0.3

# ---------------------------
# SURFACES
# ---------------------------
class SurfaceProfile:
	var name: String
	var grip_mul: float
	var rolling_mul: float
	var engine_mul: float
	var brake_mul: float
	var skid_color: Color
	var smoke_color: Color
	var sound_volume: float
	var sound_scale: float
	var surface_grip_mul: float
	var surface_rolling_mul: float
	var surface_engine_mul: float
	var surface_brake_mul: float
	
	func _init(_name: String, _grip_mul: float, _rolling_mul: float, _engine_mul: float, _brake_mul: float, _skid_color: Color, _smoke_color: Color, _sound_volume: float, _sound_scale: float) -> void:
		name = _name
		grip_mul = _grip_mul
		rolling_mul = _rolling_mul
		engine_mul = _engine_mul
		brake_mul = _brake_mul
		skid_color = _skid_color
		smoke_color = _smoke_color
		sound_volume = _sound_volume
		sound_scale = _sound_scale
		surface_grip_mul = 1.0
		surface_rolling_mul = 1.0
		surface_engine_mul = 1.0
		surface_brake_mul = 1.0

# Profils par défaut (à adapter à votre jeu)
"""	- Chaque surface influence:
  	- grip latéral (tenue de route / drift)
  	- résistance au roulement (perte de vitesse)
  	- puissance moteur (optionnel, léger)
  	- puissance de frein (optionnel, surtout sur glace)	"""
var SURFACE_ASPHALT: SurfaceProfile = SurfaceProfile.new("asphalt", 1.00, 1.00, 1.00, 1.00, Color(0,0,0,0.8), Color(0.8,0.8,0.8), -5.0, 0.4)
var SURFACE_GRAVEL: SurfaceProfile = SurfaceProfile.new("gravel", 0.05, 3.50, 0.60, 0.80, Color(0.4,0.3,0.2,0.6), Color(0.445, 0.317, 0.211, 1.0), -9.0, 0.1)
var SURFACE_GRASS: SurfaceProfile = SurfaceProfile.new("grass", 0.10, 1.60, 0.85, 0.20, Color(0.2,0.5,0.2,0.5), Color(0.275, 0.431, 0.275, 1.0), -8.0, 0.15)
var SURFACE_MUD: SurfaceProfile = SurfaceProfile.new("mud", 0.50, 1.75, 0.72, 0.82, Color(0.3,0.2,0.1,0.8), Color(0.8,0.8,0.8), 0.0, 1.0)
var SURFACE_ICE: SurfaceProfile = SurfaceProfile.new("ice", 0.02, 0.85, 0.95, 0.55, Color(0.005, 0.186, 0.824, 0.502), Color(0.664, 0.642, 1.0, 1.0), -6.0, 0.3)
var SURFACE_DEFAULT: SurfaceProfile = SurfaceProfile.new("default", 0.70, 1.20, 0.80, 0.80, Color(0,0,0,0.5), Color(0.721, 0.151, 0.467, 1.0), -6.0, 0.4)
var _surface: SurfaceProfile = SURFACE_DEFAULT

# Vitesse de transition des effets de surface
@export var surface_blend_speed: float = 25.0

# Active l'affichage debug (vecteurs de vitesse, etc.)
@export var debug_draw: bool = false
var _steer_angle: float = 0.0
#var _surface_name: String = "default"

func setup_car(car_def: CarDefinition, color: Color = Color.WHITE) -> void:
	if car_def == null:
		push_error("Car.setup_car() : CarDefinition invalide.")
		return

	definition = car_def

	_apply_car_definition()
	_load_car_model()
	_apply_car_color(color)

func _apply_car_definition() -> void:
	if definition == null:
		return

	car_name = definition.display_name

	engine_force = definition.engine_force
	brake_force = definition.brake_force
	reverse_force = definition.reverse_force

	max_speed = definition.max_speed
	max_reverse_speed = definition.max_reverse_speed

	rolling_resistance = definition.rolling_resistance
	air_drag = definition.air_drag

	lateral_grip = definition.lateral_grip
	lateral_grip_at_high_speed = definition.lateral_grip_at_high_speed
	high_speed_grip_start = definition.high_speed_grip_start
	high_speed_grip_end = definition.high_speed_grip_end

	max_steer_angle = definition.max_steer_angle
	steer_speed = definition.steer_speed
	steer_return_speed = definition.steer_return_speed

	steering_response_low_speed = definition.steering_response_low_speed
	steering_response_high_speed = definition.steering_response_high_speed

	steering_high_speed_start = definition.steering_high_speed_start
	steering_high_speed_end = definition.steering_high_speed_end

	wheel_base = definition.wheel_base
	wheel_spacing = definition.wheel_spacing
	min_speed_for_steer = definition.min_speed_for_steer

	handbrake_grip_multiplier = definition.handbrake_grip_multiplier
	handbrake_brake_multiplier = definition.handbrake_brake_multiplier

	camera_zoom_min = definition.camera_zoom_min
	camera_zoom_max = definition.camera_zoom_max
	camera_zoom_speed = definition.camera_zoom_speed

func _load_car_model() -> void:
	if model == null:
		push_error("Car : node Model manquant.")
		return

	for child in model.get_children():
		child.queue_free()

	if definition == null:
		return

	if definition.model_scene == null:
		push_warning(
			"CarDefinition '%s' n'a pas de model_scene."
			% definition.id
		)
		return

	var model_instance := definition.model_scene.instantiate()
	model.add_child(model_instance)

	_find_car_sprite(model_instance)

func _apply_car_color(color: Color) -> void:
	if model == null:
		return

	model.modulate = color

func _find_car_sprite(root: Node) -> void:
	car_sprite = root.find_child(
		"AnimatedSprite2D",
		true,
		false
	) as AnimatedSprite2D

	if car_sprite == null:
		push_warning(
			"Le modèle '%s' ne contient pas d'AnimatedSprite2D."
			% root.name
		)

func _ready() -> void:
	if ground_ray == null:
		push_warning("GroundRay manquant: ajoutez un RayCast2D nommé 'GroundRay' sous la voiture.")
	else:
		ground_ray.enabled = true

func _physics_process(delta: float) -> void:
	# Mise à jour des effets de surface
	_update_surface(delta)

	# Calcul des directions, vitesse et accélerration
	var fwd: Vector2 = Vector2.RIGHT.rotated(rotation)
	var right: Vector2 = fwd.orthogonal()
	var v: Vector2 = velocity
	speed = v.length()
	acceleration = (speed - previous_speed) / delta
	previous_speed = speed

	# Gestion des inputs
	var throttle: float = 0
	var brake: float = 0
	var steer_input: float = 0
	var handbrake: bool = false
	if car_can_move:
		throttle = Input.get_action_strength("up")
		brake = Input.get_action_strength("down")
		steer_input = Input.get_action_strength("right") - Input.get_action_strength("left")
		handbrake = Input.is_action_pressed("handbrake") if InputMap.has_action("handbrake") else false

	# Lissage de la direction
	_smooth_steering(delta, steer_input)

	# Efficacité de la direction selon la vitesse
	var steer_t: float = inverse_lerp(steering_high_speed_start, steering_high_speed_end, speed)
	var steer_eff: float = lerp(steering_response_low_speed, steering_response_high_speed, clamp(steer_t, 0.0, 1.0))

	# Décomposition de la vélocité
	var v_long_scalar: float = v.dot(fwd)
	var v_lat_scalar: float = v.dot(right)
	var v_long: Vector2 = fwd * v_long_scalar
	var v_lat: Vector2 = right * v_lat_scalar

	# Forces longitudinales
	var force_long: float = _calculate_longitudinal_forces(speed, throttle, brake, handbrake, v_long_scalar)
	var grip_mult: float = 1.0 if not handbrake else handbrake_grip_multiplier

	# Apply longitudinal acceleration
	v_long += fwd * (force_long * delta)

	# Résistances
	var result = _apply_resistances(delta, right, v_long, v_lat_scalar, v_lat)
	v_long = result[0]
	v_lat = result[1]

	# Adhérence latérale
	v_lat = _apply_lateral_grip(delta, speed, grip_mult, v_lat)

	# Modèle de rotation
	var v_long_after: float = v_long.dot(fwd)
	_apply_rotation(delta, v_long_after, steer_eff)

	# Recombinaison et clamp de la vélocité
	_clamp_velocity(fwd, v_long, v_lat)
	
	# Gestion des colisions
	last_collision_time += delta
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		_on_Car_body_entered(delta, collider)

	# Mise à jour du zoom caméra
	_update_camera_zoom(delta, speed)
	
	# ======================
	# FX SYSTEM
	# ======================
	var slip = _compute_slip_intensity(v_lat_scalar, speed)

	_apply_surface_fx()
	_update_skidmarks(slip)
	_update_smoke(slip)
	_update_skid_sound(slip)
	_update_engine_sound()
	
	speed_changed.emit(speed)
	
	# Debug
	if debug_draw:
		queue_redraw()

# Sous-fonctions pour la lisibilité

# ---------------------------
# SLIP
# ---------------------------
func _compute_slip_intensity(v_lat_scalar, _speed):
	var slip = abs(v_lat_scalar)
	#return clamp((slip / 400.0) * (speed / 300.0), 0.0, 1.0)
	return clamp((slip / 400.0) * (_speed / max_speed * 0.8), 0.0, 1.0)

# ---------------------------
# FX : SKIDMARKS
# ---------------------------
func _update_skidmarks(slip):
	
	var fwd = Vector2.RIGHT.rotated(rotation)
	var right = fwd.orthogonal()

	var rear_offset = -fwd * wheel_base * 0.5

	var left_pos = global_position + rear_offset - right * wheel_spacing
	var right_pos = global_position + rear_offset + right * wheel_spacing
	
	if slip > threshold:
		var color = _surface.skid_color
		# LEFT
		if left_line == null:	
			left_line = Line2D.new()
			left_line.default_color = color
			left_line.width = 5
			left_line.z_index = -1
			skid_node.add_child(left_line)
		else:
			if left_line.default_color != color:
				left_line = Line2D.new()
				left_line.default_color = color
				left_line.width = 5
				left_line.z_index = -1
				skid_node.add_child(left_line)
			
		_add_point_safe(left_line,skid_node.to_local(left_pos))
		if left_line.get_point_count() > max_points_per_line:
			left_line.remove_point(0)

		# RIGHT
		if right_line == null:
			right_line = Line2D.new()
			right_line.width = 5
			right_line.z_index = -1
			skid_node.add_child(right_line)
		else:
			if right_line.default_color != color:
				right_line = Line2D.new()
				right_line.default_color = color
				right_line.width = 5
				right_line.z_index = -1
				skid_node.add_child(right_line)
				
		if right_line.get_point_count() > max_points_per_line:
				right_line.remove_point(0)
		_add_point_safe(right_line,skid_node.to_local(right_pos))
	else:
		left_line = null
		right_line = null

func _add_point_safe(line: Line2D, pos: Vector2):
	if line.get_point_count() == 0:
		line.add_point(pos)
		return

	var last = line.get_point_position(line.get_point_count() - 1)
	if last.distance_to(pos) > min_distance:
		line.add_point(pos)


# ---------------------------
# FX : SMOKE
# ---------------------------
func _update_smoke(slip: float):

	if slip < threshold:
		smoke_left.emitting = false
		smoke_right.emitting = false
		return

	smoke_left.emitting = true
	smoke_right.emitting = true
	# Gère le nombre de particules
	smoke_left.amount = int(lerp(50, 300, slip))
	smoke_right.amount = int(lerp(50, 300, slip))
	# Durée de vie des particules
	smoke_left.lifetime = 1.5 + slip * 2.0
	smoke_right.lifetime = 1.5 + slip * 2.0

	var mat_left := smoke_left.process_material as ParticleProcessMaterial
	if mat_left == null:
		push_warning("Smoke left has no process material")
		return
	var mat_right := smoke_right.process_material as ParticleProcessMaterial
	if mat_right == null:
		push_warning("Smoke right has no process material")
		return

	var vel_dir = velocity.normalized()

	mat_left.direction = Vector3(-vel_dir.x, -vel_dir.y, 0.0)
	mat_right.direction = Vector3(-vel_dir.x, -vel_dir.y, 0.0)
	mat_left.scale_min = 1.0 + slip * 1.5
	mat_right.scale_min = 1.0 + slip * 1.5
	mat_left.scale_max = 2.0 + slip * 3.0
	mat_right.scale_max = 2.0 + slip * 3.0
	# Vitesse (trop rapide = fumée dispersée, plus lent = fumée compacte)
	mat_left.initial_velocity_min = 10 + slip * 2
	mat_right.initial_velocity_min = 10 + slip * 2
	mat_left.initial_velocity_max = 40 + slip * 40
	mat_right.initial_velocity_max = 40 + slip * 40
	# Densité (trop élevé = fumée dispersée, plus faible = fumée dense)
	mat_left.spread = 20 + slip * 20
	mat_right.spread = 20 + slip * 20
	# Gravité (effet lourd)
	mat_right.gravity = Vector3(0, 20, 0)
	mat_right.gravity = Vector3(0, 20, 0)


# ---------------------------
# FX : SOUND
# ---------------------------
func _update_engine_sound():
	# Si la voiture est presque arrêtée, jouer le son au ralenti
	if speed < 1.0:
		if not engine_idle_sound.playing:
			engine_idle_sound.play()
		if engine_running_sound.playing:
			engine_running_sound.stop()
		if engine_rupteur_sound.playing:
			engine_rupteur_sound.stop()
	else:
		if speed < max_speed:
			# Voiture en mouvement : jouer le son moteur dynamique
			if not engine_running_sound.playing:
					engine_running_sound.play()
			# Arrêter le son au ralenti et au rupteur
			if engine_rupteur_sound.playing:
				engine_rupteur_sound.stop()
			if engine_idle_sound.playing:
				engine_idle_sound.stop()
		
			# Moduler le pitch en fonction de la vitesse (exemple simple)
			var pitch = lerp(1.0, 3.0, clamp(speed / max_speed, 0, 1))
			engine_running_sound.pitch_scale = pitch
		
			# Moduler le volume en fonction de l'accélération (plus fort à l'accélération)
			var volume = lerp(-15, 0, clamp(acceleration / 1000.0, 0, 1))
			engine_running_sound.volume_db = volume
		else:
			# Voiture en vitesse max : jouer le son moteur rupteur
			if not engine_rupteur_sound.playing:
					engine_rupteur_sound.play()
			# Arrêter le son au ralenti et acceleration
			if engine_idle_sound.playing:
				engine_idle_sound.stop()
			if engine_running_sound.playing:
				engine_running_sound.stop()
			
			

func _update_skid_sound(slip: float):
	if slip < threshold:
		if skid_sound.playing:
			skid_sound.stop()
		return
	if not skid_sound.playing:
		skid_sound.play()

	skid_sound.volume_db = lerp(-30, -5, slip)
	skid_sound.pitch_scale = lerp(0.7, 1.4, slip)

func _play_collision_sound():
	if last_collision_time > collision_cooldown:
		if collision_sound.playing:
			collision_sound.stop()
		collision_sound.play()
		last_collision_time = 0.0

func _apply_surface_fx():
	smoke_left.modulate = _surface.smoke_color
	smoke_right.modulate = _surface.smoke_color
	skid_sound.volume_db = _surface.sound_volume
	skid_sound.pitch_scale = _surface.sound_scale

#Mise à jour du type de surface en fonction du groupe du sol (TileMapLayer)
func get_surface_profile() -> SurfaceProfile:
	# Si pas de raycast ou pas de collision: profil par défaut
	if ground_ray == null or not ground_ray.is_colliding():
		return SURFACE_DEFAULT

	var collider := ground_ray.get_collider()
	if collider == null:
		return SURFACE_DEFAULT
	# IMPORTANT:
	# - Si votre sol est un TileMap, le collider peut être le TileMap.
	# - Si votre sol est un StaticBody2D/CharacterBody2D, ça peut être ce node.
	# Dans les deux cas, les groupes fonctionnent bien.
	if collider.is_in_group("asphalt"):
		return SURFACE_ASPHALT
	if collider.is_in_group("gravel"):
		return SURFACE_GRAVEL
	if collider.is_in_group("grass"):
		return SURFACE_GRASS
	if collider.is_in_group("mud"):
		return SURFACE_MUD
	if collider.is_in_group("ice"):
		return SURFACE_ICE

	return SURFACE_DEFAULT

# Mise à jour des variables influencées par la surface roulée
func _update_surface(delta: float) -> void:
	var old_surface: SurfaceProfile = _surface
	var target_profile: SurfaceProfile = get_surface_profile()
	_surface = target_profile
	_surface.surface_grip_mul = move_toward(old_surface.surface_grip_mul, target_profile.grip_mul, surface_blend_speed * delta)
	_surface.surface_rolling_mul = move_toward(old_surface.surface_rolling_mul, target_profile.rolling_mul, surface_blend_speed * delta)
	_surface.surface_engine_mul = move_toward(old_surface.surface_engine_mul, target_profile.engine_mul, surface_blend_speed * delta)
	_surface.surface_brake_mul = move_toward(old_surface.surface_brake_mul, target_profile.brake_mul, surface_blend_speed * delta)

func _smooth_steering(delta: float, steer_input: float) -> void:
	var target_steer: float = steer_input * max_steer_angle
	if abs(steer_input) > 0.001:
		_steer_angle = move_toward(_steer_angle, target_steer, steer_speed * delta)
	else:
		_steer_angle = move_toward(_steer_angle, 0.0, steer_return_speed * delta)

func _calculate_longitudinal_forces(_speed: float, throttle: float, brake: float, handbrake: bool, v_long_scalar: float) -> float:
	var force_long: float = 0.0

	# Engine (forward)
	if throttle > 0.001:
		var engine_fade: float = 1.0 - clamp(_speed / max_speed, 0.0, 1.0) * 0.35
		force_long += engine_force * _surface.surface_engine_mul * throttle * engine_fade

	# Brake or reverse
	if brake > 0.001:
		if v_long_scalar > 60.0:
			force_long -= brake_force * _surface.surface_brake_mul * brake
		else:
			if v_long_scalar < 10.0:
				var rev_fade: float = 1.0 - clamp(_speed / max_reverse_speed, 0.0, 1.0) * 0.35
				#force_long -= reverse_force * _surface.surface_engine_mul * brake * rev_fade
				force_long -= reverse_force * ((_surface.surface_engine_mul + 1)/2) * brake * rev_fade

	# Handbrake: extra brake
	if handbrake:
		if v_long_scalar > 10.0:
			force_long -= brake_force * _surface.surface_brake_mul * handbrake_brake_multiplier

	return force_long

func _apply_resistances(delta: float, right: Vector2, v_long: Vector2, v_lat_scalar: float, v_lat: Vector2) -> Array:
	# Rolling resistance (surface-modulated)
	if v_long.length() > 0.0:
		var rr: float = rolling_resistance * _surface.surface_rolling_mul * delta
		var new_len: float = max(v_long.length() - rr, 0.0)
		v_long = v_long.normalized() * new_len

	# Air drag (global)
	var v: Vector2 = v_long + v_lat
	var _speed: float = v.length()
	v -= v * (air_drag * _speed * delta)

	# Recompute lateral component after drag
	v_lat_scalar = v.dot(right)
	v_lat = right * v_lat_scalar

	return [v_long, v_lat]

func _apply_lateral_grip(delta: float, _speed: float, grip_mult: float, v_lat: Vector2) -> Vector2:
	var grip_t: float = inverse_lerp(high_speed_grip_start, high_speed_grip_end, _speed)
	var base_grip: float = lerp(lateral_grip, lateral_grip_at_high_speed, clamp(grip_t, 0.0, 1.0))

	var grip: float = base_grip * _surface.surface_grip_mul * grip_mult

	# Stronger correction at low speed feels better; clamp for stability
	var lat_k: float = clamp(grip * delta, 0.0, 1.0)
	v_lat = v_lat * (1.0 - lat_k)

	return v_lat

func _apply_rotation(delta: float, v_long_after: float, steer_eff: float) -> void:
	if abs(v_long_after) > min_speed_for_steer:
		# slight understeer saturation at high speed + low grip surfaces
		var surface_understeer: float = clamp(1.15 - _surface.surface_grip_mul, 0.0, 0.55) # more understeer if low grip
		var understeer_mul: float = 1.0 - surface_understeer
		var effective_steer: float = _steer_angle * steer_eff * understeer_mul

		var yaw_rate: float = (v_long_after / max(wheel_base, 1.0)) * tan(effective_steer)
		rotation += yaw_rate * delta

func _clamp_velocity(fwd: Vector2, v_long: Vector2, v_lat: Vector2) -> void:
	var v: Vector2 = v_long + v_lat

	# Clamp speeds (forward/back along forward axis)
	var v_long_final: float = v.dot(fwd)
	if v_long_final > max_speed:
		v -= fwd * (v_long_final - max_speed)
	elif v_long_final < -max_reverse_speed:
		v -= fwd * (v_long_final + max_reverse_speed)

	# Optional total clamp to avoid insane drift spikes
	var v_max_total: float = max_speed * 1.15
	if v.length() > v_max_total:
		v = v.normalized() * v_max_total

	velocity = v
	move_and_slide()

# Mise à jour du zoom de la caméra, la caméra s'éloigne avec la vitesse
func _update_camera_zoom(delta: float, _speed: float) -> void:
	if camera != null:
		var target_zoom: float = lerp(camera_zoom_max, camera_zoom_min, clamp(_speed / max_speed, 0.0, 1.0))
		var current_zoom: float = camera.zoom.x # zoom.x == zoom.y for uniform zoom
		var new_zoom: float = move_toward(current_zoom, target_zoom, camera_zoom_speed * delta)
		camera.zoom = Vector2(new_zoom, new_zoom)

# Info affichées si le débug est activé
func _draw() -> void:
	if not debug_draw:
		return
	var fwd: Vector2 = Vector2.RIGHT.rotated(rotation)
	var right: Vector2 = fwd.orthogonal()
	var p := Vector2.ZERO

	draw_line(p, p + fwd * 80, Color(0.2, 0.9, 0.3), 3.0)
	draw_line(p, p + right * 60, Color(0.2, 0.6, 1.0), 3.0)
	draw_line(p, p + velocity * 0.08, Color(1.0, 0.3, 0.3), 3.0)
	draw_line(p, p + fwd.rotated(_steer_angle) * 55, Color(1.0, 0.85, 0.2), 3.0)

	# Petit label debug (sans dépendre d'un Label node)
	draw_string(ThemeDB.fallback_font, p + Vector2(-70, -55), "surface: %s" % _surface.name, HORIZONTAL_ALIGNMENT_LEFT, 300, 14, Color(1,1,1,0.9))

func _on_Car_body_entered(delta: float, body: Node) -> void:
	#if collider.collision_layer & OBSTACLE_LAYER != 0:
	if body.is_in_group("obstacle") && speed > 100:  # Assure-toi que tes obstacles sont dans ce groupe
		var collision = move_and_collide(velocity * delta)
		if collision:
			var normal = collision.get_normal()
			

			# Calcul du rebond
			velocity = velocity - 2 * velocity.dot(normal) * normal
			velocity *= bounce_factor
		_play_collision_sound()

func _car_can_move(can_move: bool) -> void:
	car_can_move = can_move
