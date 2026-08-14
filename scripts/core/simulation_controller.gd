class_name SimulationController
extends Node

signal pause_changed(is_paused: bool)
signal speed_changed(multiplier: float)

const VALID_SPEEDS: Array[float] = [1.0, 2.0, 4.0]

@export_enum("1x:1", "2x:2", "4x:4") var initial_speed: int = 1

var speed_multiplier: float = 1.0
var pause_locked: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	set_speed(float(initial_speed))
	pause_changed.emit(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("simulation_pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("simulation_speed_1"):
		set_speed(1.0)
	elif event.is_action_pressed("simulation_speed_2"):
		set_speed(2.0)
	elif event.is_action_pressed("simulation_speed_4"):
		set_speed(4.0)


func toggle_pause() -> void:
	if pause_locked:
		return
	set_paused(not get_tree().paused)


func set_paused(should_pause: bool) -> void:
	if pause_locked and not should_pause:
		return
	if get_tree().paused == should_pause:
		return
	get_tree().paused = should_pause
	pause_changed.emit(should_pause)


func set_pause_locked(should_lock: bool) -> void:
	if should_lock and not get_tree().paused:
		set_paused(true)
	pause_locked = should_lock


func set_speed(multiplier: float) -> void:
	if not VALID_SPEEDS.has(multiplier):
		push_warning("Unsupported simulation speed: %s" % multiplier)
		return
	if is_equal_approx(speed_multiplier, multiplier) and is_equal_approx(Engine.time_scale, multiplier):
		speed_changed.emit(speed_multiplier)
		return
	speed_multiplier = multiplier
	Engine.time_scale = multiplier
	speed_changed.emit(speed_multiplier)


func _exit_tree() -> void:
	# Do not leak scene-local simulation settings into editor test runs or later scenes.
	Engine.time_scale = 1.0
	if get_tree() != null:
		get_tree().paused = false
