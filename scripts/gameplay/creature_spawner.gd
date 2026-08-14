class_name CreatureSpawner
extends Node2D

signal creature_spawned(creature: Creature, spawned_count: int)
signal spawning_finished(total_spawned: int)

@export var creature_scene: PackedScene
@export_range(1, 200, 1, "or_greater") var spawn_count: int = 30
@export_range(0.02, 10.0, 0.01, "or_greater") var spawn_interval: float = 0.2
@export_enum("Left:-1", "Right:1") var initial_direction: int = 1
@export var creature_container_path: NodePath

var spawned_count: int = 0
var _is_spawning: bool = false


func _ready() -> void:
	# Deferring gives the level coordinator time to connect to the first spawn event.
	call_deferred("start_spawning")


func start_spawning() -> void:
	if _is_spawning or spawned_count >= spawn_count:
		return
	if creature_scene == null:
		push_error("CreatureSpawner requires a creature_scene.")
		return

	_is_spawning = true
	while spawned_count < spawn_count and is_inside_tree():
		if not _spawn_one():
			break
		if spawned_count < spawn_count:
			# process_always=false makes spawning obey the world's pause state.
			await get_tree().create_timer(spawn_interval, false).timeout

	_is_spawning = false
	spawning_finished.emit(spawned_count)


func _spawn_one() -> bool:
	var creature := creature_scene.instantiate() as Creature
	if creature == null:
		push_error("The configured creature scene must instantiate a Creature.")
		return false

	var container := get_node_or_null(creature_container_path)
	if container == null:
		container = get_parent()

	container.add_child(creature)
	creature.global_position = global_position
	creature.configure(initial_direction)
	spawned_count += 1
	creature_spawned.emit(creature, spawned_count)
	return true
