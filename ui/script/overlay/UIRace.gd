extends CanvasLayer

signal ready_run()
signal start_run()

@onready var speed_label: Label = %Speed

@onready var light_start: Node2D = %FeuDepart
@onready var timer_start: Timer = %TimerStart

@onready var label_timer_general: Label = %TimeRun
var start : bool = false
var timer_general: float = 0.0

@onready var label_tour: Label = %Tour
var tour: int = 0
var nb_tour: int = 3
@onready var label_timer_lap: Label = %TimeLap
@onready var label_timer_last_lap: Label = %TimeLastLap
@onready var label_timer_best_lap: Label = %TimeBestLap
@onready var label_delta: Label = %TimeDelta
var start_lap : bool = false
var timer_lap: float = 0.0
var timer_last_lap: float = 0.0
var timer_best_lap: float = 0.0
var delta_time: float = 0.0

var tab_timer_inter: Array[float]
var tab_timer: Array[Array]
var tab_best_time: Array[float]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_on_ready_light()
	update_nb_lap()

func _process(delta: float) -> void:
	if start:
		timer_general += delta
		label_timer_general.text = "Temps de course : "+String.num(timer_general, 2)
	if start_lap:
		timer_lap += delta
		label_timer_lap.text = "Tour en cours : "+String.num(timer_lap, 2)


func _on_changed_speed(speed: float) -> void:
	var km : int = round(speed * 140 / 2000)
	speed_label.text = str(km) + " km/h"
	
func _on_start() -> void:
	start = true
	_on_start_light()

func _on_start_light() -> void:
	start_run.emit()
	var all_light : Array[Node] = light_start.get_children()
	for light:AnimatedSprite2D in all_light:
		light.set_frame(1)
	await get_tree().create_timer(2.0).timeout
	light_start.visible = false

func _on_ready_light() -> void:
	start = false
	ready_run.emit()
	var all_light : Array[Node] = light_start.get_children()
	for light:AnimatedSprite2D in all_light:
		light.set_frame(0)
	light_start.visible = true
	timer_start.start()
	speed_label.text = "0 km/h"

func _on_cut_section(id: int, all_section: Array[Node]) -> void:
	
	print("UI course")
	if all_section[id].valid_section != true:
		print("Prise en compte section")
		print(id)
		if start_lap == true:
			if id == 0:
				print("nouveau tour")
				for s:Area2D in all_section:
					s.valid_section = false
				all_section[0].valid_section = true
				tab_timer_inter.append(timer_lap)
				calc_delta(tab_timer_inter.size()-1)
				end_lap()
			else:
				var i: int = 0
				for s:Area2D in all_section:
					if i < id && s.valid_section == false:
						cut_detect(i)
						return
					if i == id:
						print("Validation section")
						s.valid_section = true
						tab_timer_inter.append(timer_lap)
						calc_delta(id)
					i += 1
				if id == all_section.size()-1:
					print("Dernière section")
					all_section[0].valid_section = false
		else:
			if id == 0:
				print("départ")
				timer_lap = 0.0
				tour += 1
				update_nb_lap()
				tab_timer_inter.append(timer_lap)
				start_lap = true
				all_section[0].valid_section = true
			

func calc_delta(id: int) -> void:
	if timer_best_lap != 0:
		delta_time = tab_timer_inter[id]-tab_best_time[id]
		label_delta.text = "Ecart : "+String.num(delta_time, 3)

func end_lap() -> void:
	timer_last_lap = timer_lap
	timer_lap = 0.0
	label_timer_last_lap.text = "Dernier tour : "+String.num(timer_last_lap, 2)
	if timer_last_lap < timer_best_lap || timer_best_lap == 0:
		timer_best_lap = timer_last_lap
		tab_best_time = tab_timer_inter
		label_timer_best_lap.text = "Meilleur tour : "+String.num(timer_best_lap, 2)
	tab_timer_inter = [0.0]
	tour += 1
	update_nb_lap()

func update_nb_lap() -> void:
	label_tour.text = "Tour "+String.num(tour, 0)+"/"+String.num(nb_tour, 0)

func cut_detect(id: int) -> void:
	print("cut détecté")
	print(id)
