class_name Creature
extends CharacterBody2D

## Deterministic autonomous movement for the foundation creature.

signal state_changed(previous: State, current: State)
signal dig_step_requested(creature: Creature)

enum State {
	WALKING,
	FALLING,
	DIGGING,
	EXITING,
	DEAD,
}

@export_range(10.0, 600.0, 1.0, "or_greater") var walk_speed: float = 166.667
@export_range(100.0, 5000.0, 10.0, "or_greater") var gravity: float = 2000.0
@export_range(100.0, 4000.0, 10.0, "or_greater") var maximum_fall_speed: float = 1500.0
@export_range(0.05, 1.0, 0.01, "or_greater") var dig_step_interval: float = 0.14
@export_range(10.0, 300.0, 1.0, "or_greater") var dig_descent_speed: float = 72.0
@export var show_state_label: bool = false

var direction: int = 1
var current_state: State = State.FALLING
var _dig_step_time_remaining: float = 0.0

@onready var visual_root: Node2D = $VisualRoot
@onready var selection_highlight: Polygon2D = $SelectionHighlight
@onready var dig_effect: Polygon2D = $DigEffect
@onready var state_label: Label = $StateLabel


func _ready() -> void:
	_apply_facing()
	_update_state_label()


func _physics_process(delta: float) -> void:
	if current_state == State.EXITING or current_state == State.DEAD:
		return
	if current_state == State.DIGGING:
		velocity = Vector2(0.0, dig_descent_speed)
		move_and_slide()
		_dig_step_time_remaining -= delta
		if _dig_step_time_remaining <= 0.0:
			_dig_step_time_remaining += dig_step_interval
			dig_step_requested.emit(self)
		return

	velocity.x = walk_speed * float(direction)
	velocity.y = minf(velocity.y + gravity * delta, maximum_fall_speed)
	move_and_slide()

	_turn_around_when_blocked()
	_transition_to(State.WALKING if is_on_floor() else State.FALLING)


func configure(spawn_direction: int) -> void:
	direction = -1 if spawn_direction < 0 else 1
	_apply_facing()


func begin_dig() -> bool:
	if current_state != State.WALKING:
		return false
	_dig_step_time_remaining = dig_step_interval
	dig_effect.visible = true
	_transition_to(State.DIGGING)
	return true


func finish_dig() -> void:
	if current_state != State.DIGGING:
		return
	dig_effect.visible = false
	velocity = Vector2.ZERO
	_transition_to(State.WALKING)


func set_target_highlighted(is_highlighted: bool) -> void:
	selection_highlight.visible = is_highlighted


func exit_level() -> bool:
	if current_state == State.EXITING or current_state == State.DEAD:
		return false

	_transition_to(State.EXITING)
	_finish_lifecycle()
	return true


func die() -> bool:
	if current_state == State.EXITING or current_state == State.DEAD:
		return false

	_transition_to(State.DEAD)
	_finish_lifecycle()
	return true


func _turn_around_when_blocked() -> void:
	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var normal := collision.get_normal()
		if absf(normal.x) > 0.7 and normal.x * float(direction) < -0.5:
			direction *= -1
			velocity.x = walk_speed * float(direction)
			_apply_facing()
			return


func _transition_to(next_state: State) -> void:
	if current_state == next_state:
		return

	var previous := current_state
	current_state = next_state
	_update_state_label()
	state_changed.emit(previous, current_state)


func _finish_lifecycle() -> void:
	set_target_highlighted(false)
	dig_effect.visible = false
	velocity = Vector2.ZERO
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	visible = false
	queue_free()


func _apply_facing() -> void:
	if is_instance_valid(visual_root):
		visual_root.scale.x = float(direction)


func _update_state_label() -> void:
	if not is_instance_valid(state_label):
		return
	state_label.visible = show_state_label
	state_label.text = State.keys()[current_state]
