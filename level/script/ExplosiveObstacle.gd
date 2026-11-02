
extends StaticBody2D
class_name ExplosiveObstacle


# ============================================================
# CONFIGURATION
# ============================================================

@export_group("Explosion")

# Rayon de propagation de l'explosion, en pixels.
@export_range(0.0, 2000.0, 10.0)
var explosion_radius: float = 180.0

# Durée pendant laquelle le rayon de dégâts reste actif.
@export_range(0.1, 5.0, 0.1)
var blast_duration: float = 0.5


# ============================================================
# NŒUDS
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var blast_area: Area2D = $BlastArea
@onready var blast_shape: CollisionShape2D = $BlastArea/CollisionShape2D


# ============================================================
# ÉTAT
# ============================================================

var detonated: bool = false


# ============================================================
# INITIALISATION
# ============================================================

func _ready() -> void:
	add_to_group("obstacle")

	# Le rayon de dégâts est inactif tant que le baril
	# n'a pas explosé.
	blast_area.monitoring = false

	# Configuration du rayon.
	var circle := blast_shape.shape as CircleShape2D

	if circle == null:
		push_error(
			"ExplosiveObstacle : BlastArea doit utiliser un CircleShape2D."
		)
		return

	circle.radius = explosion_radius

	# Animation initiale.
	sprite.play("idle")

	# Détection des voitures et des autres obstacles.
	blast_area.body_entered.connect(_on_blast_body_entered)

	# Fin de l'animation d'explosion.
	sprite.animation_finished.connect(_on_animation_finished)


# ============================================================
# DÉTONATION
# ============================================================

func detonate() -> void:
	if detonated:
		return

	detonated = true

	# Animation de l'explosion.
	sprite.play("explosion")

	# Activation du rayon de dégâts et de propagation.
	blast_area.set_deferred("monitoring", true)

	# Désactivation automatique du rayon après sa durée.
	_disable_blast_after_delay()


func _disable_blast_after_delay() -> void:
	await get_tree().create_timer(blast_duration).timeout

	if is_instance_valid(blast_area):
		blast_area.set_deferred("monitoring", false)


# ============================================================
# DÉGÂTS ET PROPAGATION
# ============================================================

func _on_blast_body_entered(body: Node2D) -> void:

	# Une voiture touchée par l'explosion explose immédiatement.
	if body is Car:
		var car := body as Car
		car.explosion()
		return

	# Un autre obstacle explosif est déclenché à son tour.
	if body is ExplosiveObstacle:
		await get_tree().create_timer(0.5).timeout
		var obstacle := body as ExplosiveObstacle
		obstacle.detonate()


# ============================================================
# FIN DE L'ANIMATION
# ============================================================

func _on_animation_finished() -> void:

	if sprite.animation == "explosion":
		# Le baril reste visible et continue de brûler.
		sprite.play("burning")
