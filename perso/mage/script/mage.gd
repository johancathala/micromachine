extends CharacterBody2D
class_name Player

# --- Config ---
@export var SPEED: float = 140.0
const BASE_WALK_SPEED := 85.0

enum Direction { NONE, RIGHT, LEFT, DOWN, UP }
var current_dir: Direction = Direction.DOWN

@onready var anim: AnimationPlayer = $AnimationPlayer

#func _ready() -> void:
#	anim.play("front_idle")

func _physics_process(_delta: float) -> void:
	# 1) Récupère un vecteur d'entrée normalisé (haut/bas/gauche/droite)
	var input_dir: Vector2 = Input.get_vector("left", "right", "up", "down")
	
	# 2) Bloquer la diagonale : si les deux axes sont actifs, on ne garde qu'un axe
	#input_dir = cancel_diag(input_dir)
	
	# 3) Calcul de la vélocité en px/s
	velocity = input_dir * SPEED
	
	# 4) Mémorise la direction "facing" seulement si on bouge
	if input_dir != Vector2.ZERO:
		current_dir = _vector_to_dir(input_dir)
	
	# 5) Déplacement
	move_and_slide()
	
	# 6) Animation
	_play_anim_and_sync_speed(velocity)
	
func cancel_diag(input_dir: Vector2) -> Vector2:
	# 2) Bloquer la diagonale : si les deux axes sont actifs, on ne garde qu'un axe
	if input_dir.x != 0.0 and input_dir.y != 0.0:
		match current_dir:
			Direction.LEFT, Direction.RIGHT:
				input_dir.y = 0.0   # Priorité à l'horizontal si on “faisait face” gauche/droite
			Direction.UP, Direction.DOWN:
				input_dir.x = 0.0   # Priorité au vertical si on “faisait face” haut/bas
			_:
				input_dir.y = 0.0   # Fallback : horizontal
	return input_dir

func _vector_to_dir(v: Vector2) -> Direction:
	# Choisit l'axe dominant pour déterminer la direction
	if absf(v.x) > absf(v.y):
		return Direction.RIGHT if v.x > 0.0 else Direction.LEFT
	else:
		return Direction.DOWN if v.y > 0.0 else Direction.UP

func _play_anim_and_sync_speed(v: Vector2) -> void:
	var is_moving := v != Vector2.ZERO	
	_play_anim(is_moving)

	# --- synchronisation vitesse anim <-> vitesse déplacement ---
	# Si tu sprintes ou si tu ralentis, l’anim suit automatiquement.
	if is_moving:
		var speed := v.length() # px/s
		# Ratio par rapport à l’anim de référence
		var anim_scale := speed / BASE_WALK_SPEED
		# Evite des valeurs absurdes
		anim.speed_scale = clamp(anim_scale, 0.25, 3.0)
	else:
		anim.speed_scale = 1.0  # idle à vitesse “normale”

func _play_anim(is_moving: bool) -> void:
	match current_dir:
		Direction.RIGHT:
			if is_moving:
				anim.play("side_walk_right")
			else:
				anim.play("side_idle")
		Direction.LEFT:
			if is_moving:
				anim.play("side_walk_left")
			else:
				anim.play("side_idle")
		Direction.DOWN:
			if is_moving:
				anim.play("front_walk")
			else:
				anim.play("front_idle")
		Direction.UP:
			if is_moving:
				anim.play("back_walk")
			else:
				anim.play("back_idle")
		_:
			# Fallback raisonnable
			anim.play("front_idle")
