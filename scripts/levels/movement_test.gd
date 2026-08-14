class_name MovementTest
extends Node2D

@export var level_definition: LevelDefinition

@onready var spawner: CreatureSpawner = $World/CreatureSpawner
@onready var exit_zone: ExitZone = $World/ExitZone
@onready var kill_zone: KillZone = $World/KillZone
@onready var level_controller: LevelController = $LevelController
@onready var simulation_controller: SimulationController = $SimulationController
@onready var hud: SimulationHUD = $HUD


func _ready() -> void:
	if level_definition == null:
		push_error("MovementTest requires a LevelDefinition resource.")
		return

	spawner.spawn_count = level_definition.total_creatures
	spawner.spawn_interval = level_definition.spawn_interval
	spawner.initial_direction = level_definition.initial_direction

	spawner.creature_spawned.connect(_on_creature_spawned)
	spawner.spawning_finished.connect(_on_spawning_finished)
	exit_zone.creature_saved.connect(_on_creature_saved)
	kill_zone.creature_killed.connect(_on_creature_killed)
	level_controller.level_completed.connect(_on_level_completed)
	level_controller.level_failed.connect(_on_level_failed)
	hud.restart_requested.connect(_restart_level)

	level_controller.begin_level(level_definition)
	hud.bind_level(level_controller)


func _on_creature_spawned(_creature: Creature, spawned_count: int) -> void:
	level_controller.register_spawn(spawned_count)


func _on_spawning_finished(total_spawned: int) -> void:
	level_controller.register_spawning_finished(total_spawned)


func _on_creature_saved(_creature: Creature) -> void:
	level_controller.register_saved()


func _on_creature_killed(_creature: Creature) -> void:
	level_controller.register_lost()


func _on_level_completed(_saved: int, _total: int) -> void:
	_lock_finished_level()


func _on_level_failed(_saved: int, _required: int) -> void:
	_lock_finished_level()


func _lock_finished_level() -> void:
	simulation_controller.set_pause_locked(true)


func _restart_level() -> void:
	simulation_controller.set_pause_locked(false)
	simulation_controller.set_paused(false)
	simulation_controller.set_speed(1.0)
	var reload_error := get_tree().reload_current_scene()
	if reload_error != OK:
		push_error("Could not restart the current level: %s" % error_string(reload_error))
