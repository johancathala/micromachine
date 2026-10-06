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

# ---------------------------
# NODES
# ---------------------------
@onready var ground_ray: RayCast2D = $GroundRay
@onready var smoke_left: GPUParticles2D = $SmokeLeft
@onready var smoke_right: GPUParticles2D = $SmokeRight
@onready var engine_idle_sound: AudioStreamPlayer2D = $EngineIdleSound
@onready var engine_running_sound: AudioStreamPlayer2D = $EngineRunningSound
@onready var engine_rupteur_sound: AudioStreamPlayer2D = $EngineRupeurSound
@onready var skid_sound: AudioStreamPlayer2D = $SkidSound
@onready var collision_sound: AudioStreamPlayer2D = $CollisionSound
@onready var model: Node2D = $Model

var definition: CarDefinition
var skid_node: Node2D = null

@export var car_name : String = "Voiture"
var participant_id: int = -1
var is_ai: bool = false
var input_device_type: String = ""
var input_device_id: int = -1

var throttle: float = 0.0
var	brake: float = 0.0
var	steer_input: float = 0.0
var	handbrake: bool = false

var _current_grip_mul: float = 1.0
var _current_rolling_mul: float = 1.0
var _current_engine_mul: float = 1.0
var _current_brake_mul: float = 1.0

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

var _surface: SurfaceProfile = SurfaceCatalog.DEFAULT

# Vitesse de transition des effets de surface
@export var surface_blend_speed: float = 25.0

# Active l'affichage debug (vecteurs de vitesse, etc.)
@export var debug_draw: bool = false
var _steer_angle: float = 0.0
#var _surface_name: String = "default"

func setup_car(
	car_definition: CarDefinition,
	color: Color,
	p_id: int = -1,
	ai: bool = false,
	device_type: String = "",
	device_id: int = -1,
	skid_marks_root: Node2D = null
) -> void:
	if car_definition == null:
		push_error("Car.setup_car() : CarDefinition invalide.")
		return

	definition = car_definition

	participant_id = p_id
	is_ai = ai
	input_device_type = device_type
	input_device_id = device_id

	skid_node = skid_marks_root

	_apply_car_definition()
	_load_car_model()
	
	_update_engine_sound()
	
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

func _load_car_model() -> void:
	if model == null:
		push_error("Car : node Model manquant.")
		return

	for child in model.get_children():
		child.queue_free()

	if definition == null or definition.model_scene == null:
		push_warning("Aucun modèle pour la voiture.")
		return

	var model_instance := definition.model_scene.instantiate()
	model.add_child(model_instance)

func _apply_car_color(color: Color) -> void:
	if model == null:
		return

	var body := model.find_child("Body", true, false)

	if body != null:
		body.modulate = color
	else:
		model.modulate = color

func _ready() -> void:
	if ground_ray == null:
		push_warning("GroundRay manquant: ajoutez un RayCast2D nommé 'GroundRay' sous la voiture.")
	else:
		ground_ray.enabled = true

func _physics_process(delta: float) -> void:
	
	if not car_can_move:
		return
	
	# Gestion des inputs
	if is_ai:
		_process_ai_input(delta)
	else:
		_process_human_input(delta)

	# Mise à jour des effets de surface
	_update_surface(delta)

	_process_movement(delta)
	
	# Debug
	if debug_draw:
		queue_redraw()

# Sous-fonctions pour la lisibilité
func _process_movement(_delta: float) -> void:
	# Calcul des directions, vitesse et accélerration
	var fwd: Vector2 = Vector2.RIGHT.rotated(rotation)
	var right: Vector2 = fwd.orthogonal()
	var v: Vector2 = velocity
	speed = v.length()
	acceleration = (speed - previous_speed) / _delta
	previous_speed = speed

	# Lissage de la direction
	_smooth_steering(_delta)

	# Efficacité de la direction selon la vitesse
	var steer_t: float = inverse_lerp(steering_high_speed_start, steering_high_speed_end, speed)
	var steer_eff: float = lerp(steering_response_low_speed, steering_response_high_speed, clamp(steer_t, 0.0, 1.0))

	# Décomposition de la vélocité
	var v_long_scalar: float = v.dot(fwd)
	var v_lat_scalar: float = v.dot(right)
	var v_long: Vector2 = fwd * v_long_scalar
	var v_lat: Vector2 = right * v_lat_scalar

	# Forces longitudinales
	var force_long: float = _calculate_longitudinal_forces(speed, v_long_scalar)
	var grip_mult: float = 1.0 if not handbrake else handbrake_grip_multiplier

	# Apply longitudinal acceleration
	v_long += fwd * (force_long * _delta)

	# Résistances
	var result = _apply_resistances(_delta, right, v_long, v_lat_scalar, v_lat)
	v_long = result[0]
	v_lat = result[1]

	# Adhérence latérale
	v_lat = _apply_lateral_grip(_delta, speed, grip_mult, v_lat)

	# Modèle de rotation
	var v_long_after: float = v_long.dot(fwd)
	_apply_rotation(_delta, v_long_after, steer_eff)

	# Recombinaison et clamp de la vélocité
	_clamp_velocity(fwd, v_long, v_lat)
	speed = velocity.length()
	
	last_collision_time += _delta
	_process_collisions()
	
	# ======================
	# FX SYSTEM
	# ======================
	var slip = _compute_slip_intensity(v_lat_scalar, speed)

	_apply_surface_fx()
	_update_skidmarks(slip)
	_update_smoke(slip)
	_update_skid_sound(slip)
	_update_engine_sound()


func _process_collisions() -> void:
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)

		if collision == null:
			continue

		var collider := collision.get_collider()

		if collider == null:
			continue

		if not collider.is_in_group("obstacle"):
			continue

		_handle_obstacle_collision(collision)

func _handle_obstacle_collision(collision: KinematicCollision2D) -> void:
	if speed <= 100.0:
		return

	var normal: Vector2 = collision.get_normal()

	# Composante de la vitesse dirigée vers l'obstacle.
	var velocity_into_surface: float = velocity.dot(normal)

	# Si la voiture s'éloigne déjà de l'obstacle,
	# il n'y a pas de rebond à appliquer.
	if velocity_into_surface >= 0.0:
		return

	# Réflexion de la vitesse par rapport à la normale.
	velocity = velocity - 2.0 * velocity_into_surface * normal

	# Amortissement du rebond.
	velocity *= bounce_factor

	_play_collision_sound()
	
func _process_human_input(_delta: float) -> void:
	var input_state := InputManager.get_player_input(
		input_device_type,
		input_device_id
		)
	
	throttle = input_state.throttle
	brake = input_state.brake
	steer_input = input_state.steering
	handbrake = input_state.handbrake

func _process_ai_input(_delta: float) -> void:
	pass

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
	
	if skid_node == null:
		return

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
	if ground_ray == null or not ground_ray.is_colliding():
		return SurfaceCatalog.DEFAULT

	var collider := ground_ray.get_collider()

	if collider == null:
		return SurfaceCatalog.DEFAULT

	if collider.is_in_group("asphalt"):
		return SurfaceCatalog.ASPHALT

	if collider.is_in_group("gravel"):
		return SurfaceCatalog.GRAVEL

	if collider.is_in_group("grass"):
		return SurfaceCatalog.GRASS

	if collider.is_in_group("mud"):
		return SurfaceCatalog.MUD

	if collider.is_in_group("ice"):
		return SurfaceCatalog.ICE

	return SurfaceCatalog.DEFAULT

# Mise à jour des variables influencées par la surface roulée
func _update_surface(delta: float) -> void:
	var target_profile: SurfaceProfile = get_surface_profile()

	_current_grip_mul = move_toward(
		_current_grip_mul,
		target_profile.grip_mul,
		surface_blend_speed * delta
	)

	_current_rolling_mul = move_toward(
		_current_rolling_mul,
		target_profile.rolling_mul,
		surface_blend_speed * delta
	)

	_current_engine_mul = move_toward(
		_current_engine_mul,
		target_profile.engine_mul,
		surface_blend_speed * delta
	)

	_current_brake_mul = move_toward(
		_current_brake_mul,
		target_profile.brake_mul,
		surface_blend_speed * delta
	)

	_surface = target_profile


func _smooth_steering(_delta: float) -> void:
	var target_steer: float = steer_input * max_steer_angle
	if abs(steer_input) > 0.001:
		_steer_angle = move_toward(_steer_angle, target_steer, steer_speed * _delta)
	else:
		_steer_angle = move_toward(_steer_angle, 0.0, steer_return_speed * _delta)

func _calculate_longitudinal_forces(_speed: float, v_long_scalar: float) -> float:
	var force_long: float = 0.0

	# Engine (forward)
	if throttle > 0.001:
		var engine_fade: float = 1.0 - clamp(_speed / max_speed, 0.0, 1.0) * 0.35
		force_long += engine_force * _current_engine_mul * throttle * engine_fade

	# Brake or reverse
	if brake > 0.001:
		if v_long_scalar > 60.0:
			force_long -= brake_force * _current_brake_mul * brake
		else:
			if v_long_scalar < 10.0:
				var rev_fade: float = 1.0 - clamp(_speed / max_reverse_speed, 0.0, 1.0) * 0.35
				#force_long -= reverse_force * _current_engine_mul * brake * rev_fade
				force_long -= reverse_force * ((_current_engine_mul + 1)/2) * brake * rev_fade

	# Handbrake: extra brake
	if handbrake:
		if v_long_scalar > 10.0:
			force_long -= brake_force * _current_brake_mul * handbrake_brake_multiplier

	return force_long

func _apply_resistances(delta: float, right: Vector2, v_long: Vector2, v_lat_scalar: float, v_lat: Vector2) -> Array:
	# Rolling resistance (surface-modulated)
	if v_long.length() > 0.0:
		var rr: float = rolling_resistance * _current_rolling_mul * delta
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

	var grip: float = base_grip * _current_grip_mul * grip_mult

	# Stronger correction at low speed feels better; clamp for stability
	var lat_k: float = clamp(grip * delta, 0.0, 1.0)
	v_lat = v_lat * (1.0 - lat_k)

	return v_lat

func _apply_rotation(delta: float, v_long_after: float, steer_eff: float) -> void:
	if abs(v_long_after) > min_speed_for_steer:
		# slight understeer saturation at high speed + low grip surfaces
		var surface_understeer: float = clamp(1.15 - _current_grip_mul, 0.0, 0.55) # more understeer if low grip
		var understeer_mul: float = 1.0 - surface_understeer
		var effective_steer: float = _steer_angle * steer_eff * understeer_mul

		var yaw_rate: float = (v_long_after / max(wheel_base, 1.0)) * tan(effective_steer)
		rotation += yaw_rate * delta

func _clamp_velocity(fwd: Vector2, v_long: Vector2, v_lat: Vector2) -> void:
	var v: Vector2 = v_long + v_lat

	# Limitation de la vitesse longitudinale
	var v_long_final: float = v.dot(fwd)

	if v_long_final > max_speed:
		v -= fwd * (v_long_final - max_speed)
	elif v_long_final < -max_reverse_speed:
		v -= fwd * (v_long_final + max_reverse_speed)

	# Limitation globale de sécurité
	var v_max_total: float = max_speed * 1.15

	if v.length() > v_max_total:
		v = v.normalized() * v_max_total

	velocity = v

	# Unique déplacement physique de la voiture.
	move_and_slide()


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


func set_can_move(can_move: bool) -> void:
	car_can_move = can_move
