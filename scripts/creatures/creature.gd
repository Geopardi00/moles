class_name Creature
extends CharacterBody2D

## Deterministic autonomous movement for the foundation creature.

signal state_changed(previous: State, current: State)
signal dig_step_requested(creature: Creature)
signal mine_step_requested(creature: Creature)
signal build_step_requested(creature: Creature, step_index: int)
signal blocker_redirected(blocker: Creature, creature: Creature)
signal bomb_detonated(creature: Creature)

enum State {
	WALKING,
	FALLING,
	DIGGING,
	MINING,
	BUILDING,
	BLOCKING,
	BOMBING,
	EXITING,
	DEAD,
}

@export_range(10.0, 600.0, 1.0, "or_greater") var walk_speed: float = 166.667
@export_range(100.0, 5000.0, 10.0, "or_greater") var gravity: float = 2000.0
@export_range(100.0, 4000.0, 10.0, "or_greater") var maximum_fall_speed: float = 1500.0
@export_range(0.05, 1.0, 0.01, "or_greater") var dig_step_interval: float = 0.14
@export_range(10.0, 300.0, 1.0, "or_greater") var dig_descent_speed: float = 72.0
@export_range(0.05, 1.0, 0.01, "or_greater") var mine_step_interval: float = 0.14
@export_range(10.0, 300.0, 1.0, "or_greater") var mine_horizontal_speed: float = 64.0
@export_range(10.0, 300.0, 1.0, "or_greater") var mine_descent_speed: float = 52.0
@export_range(0.05, 1.0, 0.01, "or_greater") var build_step_interval: float = 0.14
@export_range(1, 32, 1, "or_greater") var build_step_count: int = 12
@export_range(0.5, 30.0, 0.1, "or_greater") var block_duration: float = 5.5
@export_range(0.25, 10.0, 0.05, "or_greater") var bomb_fuse_duration: float = 1.5
@export var show_state_label: bool = false

var direction: int = 1
var current_state: State = State.FALLING
var _dig_step_time_remaining: float = 0.0
var _mine_step_time_remaining: float = 0.0
var _build_step_time_remaining: float = 0.0
var _build_step_index: int = 0
var _block_time_remaining: float = 0.0
var _bomb_time_remaining: float = 0.0

@onready var visual_root: Node2D = $VisualRoot
@onready var selection_highlight: Polygon2D = $SelectionHighlight
@onready var dig_effect: Polygon2D = $DigEffect
@onready var mine_effect: Polygon2D = $VisualRoot/MineEffect
@onready var build_effect: Polygon2D = $VisualRoot/BuildEffect
@onready var block_effect: Polygon2D = $VisualRoot/BlockEffect
@onready var blocker_area: Area2D = $BlockerArea
@onready var bomb_effect: Polygon2D = $VisualRoot/BombEffect
@onready var state_label: Label = $StateLabel


func _ready() -> void:
	blocker_area.body_entered.connect(_on_blocker_area_body_entered)
	_apply_facing()
	_update_state_label()


func _physics_process(delta: float) -> void:
	# Pausing can be requested by an always-processing controller during the
	# current physics frame. Guard explicitly so an action assigned in that
	# frame cannot advance before the next unpaused frame.
	if get_tree().paused:
		return
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
	if current_state == State.MINING:
		velocity = Vector2(
			mine_horizontal_speed * float(direction),
			mine_descent_speed
		)
		move_and_slide()
		_mine_step_time_remaining -= delta
		if _mine_step_time_remaining <= 0.0:
			_mine_step_time_remaining += mine_step_interval
			mine_step_requested.emit(self)
		return
	if current_state == State.BUILDING:
		velocity = Vector2.ZERO
		_build_step_time_remaining -= delta
		if _build_step_time_remaining <= 0.0:
			_build_step_time_remaining += build_step_interval
			build_step_requested.emit(self, _build_step_index)
			if current_state == State.BUILDING:
				_build_step_index += 1
				if _build_step_index >= build_step_count:
					finish_build()
		return
	if current_state == State.BLOCKING:
		velocity = Vector2.ZERO
		_block_time_remaining -= delta
		if _block_time_remaining <= 0.0:
			finish_block()
		return
	if current_state == State.BOMBING:
		velocity = Vector2.ZERO
		_bomb_time_remaining -= delta
		if _bomb_time_remaining <= 0.0:
			bomb_detonated.emit(self)
			if current_state == State.BOMBING:
				die()
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


func begin_mine() -> bool:
	if current_state != State.WALKING:
		return false
	_mine_step_time_remaining = mine_step_interval
	mine_effect.visible = true
	_transition_to(State.MINING)
	return true


func finish_mine() -> void:
	if current_state != State.MINING:
		return
	mine_effect.visible = false
	velocity = Vector2.ZERO
	_transition_to(State.WALKING)


func begin_build() -> bool:
	if current_state != State.WALKING:
		return false
	_build_step_time_remaining = build_step_interval
	_build_step_index = 0
	build_effect.visible = true
	_transition_to(State.BUILDING)
	return true


func finish_build() -> void:
	if current_state != State.BUILDING:
		return
	build_effect.visible = false
	velocity = Vector2.ZERO
	_transition_to(State.WALKING)


func begin_block() -> bool:
	if current_state != State.WALKING:
		return false
	_block_time_remaining = block_duration
	block_effect.visible = true
	blocker_area.monitoring = true
	velocity = Vector2.ZERO
	_transition_to(State.BLOCKING)
	return true


func finish_block() -> void:
	if current_state != State.BLOCKING:
		return
	blocker_area.set_deferred("monitoring", false)
	block_effect.visible = false
	velocity = Vector2.ZERO
	_transition_to(State.WALKING)


func redirect_from_blocker(blocker_x: float) -> bool:
	if current_state != State.WALKING:
		return false
	var horizontal_offset := global_position.x - blocker_x
	var is_approaching := (
		(horizontal_offset < 0.0 and direction > 0)
		or (horizontal_offset > 0.0 and direction < 0)
	)
	if not is_approaching:
		return false
	_reverse_direction()
	return true


func begin_bomb() -> bool:
	if current_state != State.WALKING:
		return false
	_bomb_time_remaining = bomb_fuse_duration
	bomb_effect.visible = true
	velocity = Vector2.ZERO
	_transition_to(State.BOMBING)
	return true


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
			_reverse_direction()
			return


func _reverse_direction() -> void:
	direction *= -1
	velocity.x = walk_speed * float(direction)
	_apply_facing()


func _on_blocker_area_body_entered(body: Node2D) -> void:
	if current_state != State.BLOCKING:
		return
	var other := body as Creature
	if other == null or other == self:
		return
	if other.redirect_from_blocker(global_position.x):
		blocker_redirected.emit(self, other)


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
	mine_effect.visible = false
	build_effect.visible = false
	block_effect.visible = false
	bomb_effect.visible = false
	blocker_area.set_deferred("monitoring", false)
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
