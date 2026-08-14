class_name FreeCamera2D
extends Node2D

@export_range(100.0, 3000.0, 10.0, "or_greater") var pan_speed: float = 1083.333
@export var movement_bounds: Rect2 = Rect2(0.0, 0.0, 4000.0, 1500.0)

@onready var camera: Camera2D = $Camera2D

var _last_tick_usec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_tick_usec = Time.get_ticks_usec()
	# Resolve the authored position against the actual viewport before the first
	# input. This keeps startup framing correct when the project resolution changes.
	_clamp_to_bounds()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_delta := minf(float(now - _last_tick_usec) / 1_000_000.0, 0.05)
	_last_tick_usec = now

	var input_direction := Input.get_vector(
		"camera_left", "camera_right", "camera_up", "camera_down"
	)
	if input_direction != Vector2.ZERO:
		global_position += input_direction * pan_speed * real_delta
		_clamp_to_bounds()


func _clamp_to_bounds() -> void:
	var half_view := get_viewport_rect().size * 0.5 / camera.zoom
	var minimum := movement_bounds.position + half_view
	var maximum := movement_bounds.end - half_view

	# If a viewport is larger than one dimension of the level, center that dimension.
	if minimum.x > maximum.x:
		global_position.x = movement_bounds.get_center().x
	else:
		global_position.x = clampf(global_position.x, minimum.x, maximum.x)
	if minimum.y > maximum.y:
		global_position.y = movement_bounds.get_center().y
	else:
		global_position.y = clampf(global_position.y, minimum.y, maximum.y)
