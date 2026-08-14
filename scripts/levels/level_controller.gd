class_name LevelController
extends Node

## Owns level progress and outcome rules. It knows nothing about UI or scene layout.

signal progress_changed(
	spawned: int,
	total: int,
	saved: int,
	required: int,
	lost: int
)
signal status_changed(status: Status)
signal level_completed(saved: int, total: int)
signal level_failed(saved: int, required: int)

enum Status {
	NOT_STARTED,
	RUNNING,
	COMPLETED,
	FAILED,
}

var definition: LevelDefinition
var status: Status = Status.NOT_STARTED
var spawned_count: int = 0
var saved_count: int = 0
var lost_count: int = 0
var spawning_finished: bool = false


func begin_level(level_definition: LevelDefinition) -> void:
	if level_definition == null:
		push_error("LevelController requires a LevelDefinition.")
		return

	definition = level_definition
	spawned_count = 0
	saved_count = 0
	lost_count = 0
	spawning_finished = false
	status = Status.RUNNING
	status_changed.emit(status)
	_emit_progress()


func register_spawn(new_spawned_count: int) -> void:
	if status != Status.RUNNING:
		return
	spawned_count = clampi(new_spawned_count, spawned_count, definition.total_creatures)
	_emit_progress()


func register_saved() -> void:
	if status != Status.RUNNING:
		return
	saved_count += 1
	_emit_progress()
	_evaluate_outcome()


func register_lost() -> void:
	if status != Status.RUNNING:
		return
	lost_count += 1
	_emit_progress()
	_evaluate_outcome()


func register_spawning_finished(total_spawned: int) -> void:
	if status != Status.RUNNING:
		return
	spawned_count = clampi(total_spawned, spawned_count, definition.total_creatures)
	spawning_finished = true
	_emit_progress()
	_evaluate_outcome()


func get_required_rescue_count() -> int:
	return definition.get_required_rescue_count() if definition != null else 0


func get_active_creature_count() -> int:
	return maxi(spawned_count - saved_count - lost_count, 0)


func _evaluate_outcome() -> void:
	var required := get_required_rescue_count()
	var maximum_possible_rescues := definition.total_creatures - lost_count
	if maximum_possible_rescues < required:
		_transition_to(Status.FAILED)
		return

	var every_creature_resolved := (
		spawning_finished
		and saved_count + lost_count >= definition.total_creatures
	)
	if every_creature_resolved:
		_transition_to(Status.COMPLETED if saved_count >= required else Status.FAILED)


func _transition_to(next_status: Status) -> void:
	if status == next_status:
		return
	status = next_status
	status_changed.emit(status)
	if status == Status.COMPLETED:
		level_completed.emit(saved_count, definition.total_creatures)
	elif status == Status.FAILED:
		level_failed.emit(saved_count, get_required_rescue_count())


func _emit_progress() -> void:
	if definition == null:
		return
	progress_changed.emit(
		spawned_count,
		definition.total_creatures,
		saved_count,
		get_required_rescue_count(),
		lost_count
	)
