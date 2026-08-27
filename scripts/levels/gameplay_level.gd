class_name GameplayLevel
extends Node2D

const AbilityAssignmentControllerScript = preload("res://scripts/gameplay/ability_assignment_controller.gd")
const ChunkedMaskTerrainScript = preload("res://scripts/terrain/chunked_mask_terrain.gd")
const DIG_PROBE_OFFSET := Vector2(0.0, 24.0)
const DIG_CENTER_OFFSET := Vector2(0.0, 30.0)
const DIG_RADIUS := 34.0
const BUILD_FEET_OFFSET := Vector2(0.0, 20.0)
const BUILD_START_OFFSET := 12.0
const BUILD_STEP_ADVANCE := 28.0
const BUILD_STEP_SIZE := Vector2(32.0, 16.0)

@export var level_definition: LevelDefinition
@export var diggable_terrain_path: NodePath = ^"World/Terrain/DiggableStartTerrain"
@export var buildable_terrain_path: NodePath
@export_file("*.tscn") var level_select_scene_path: String = "res://scenes/ui/level_select.tscn"

@onready var spawner: CreatureSpawner = $World/CreatureSpawner
@onready var exit_zone: ExitZone = $World/ExitZone
@onready var kill_zone: KillZone = $World/KillZone
@onready var diggable_terrain: ChunkedMaskTerrainScript = get_node(diggable_terrain_path) as ChunkedMaskTerrainScript
@onready var buildable_terrain: ChunkedMaskTerrainScript = get_node_or_null(buildable_terrain_path) as ChunkedMaskTerrainScript
@onready var level_controller: LevelController = $LevelController
@onready var simulation_controller: SimulationController = $SimulationController
@onready var ability_controller: AbilityAssignmentControllerScript = $AbilityAssignmentController
@onready var hud: SimulationHUD = $HUD


func _ready() -> void:
	if level_definition == null:
		push_error("GameplayLevel requires a LevelDefinition resource.")
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
	ability_controller.ability_assigned.connect(_on_ability_assigned)
	hud.restart_requested.connect(_restart_level)
	hud.level_select_requested.connect(_open_level_select)

	level_controller.begin_level(level_definition)
	ability_controller.set_dig_target_validator(_can_creature_dig)
	ability_controller.set_build_target_validator(_can_creature_build)
	ability_controller.begin_level(level_definition)
	hud.bind_level(level_controller)
	hud.bind_abilities(ability_controller)


func _on_creature_spawned(creature: Creature, spawned_count: int) -> void:
	creature.dig_step_requested.connect(_on_creature_dig_step)
	creature.build_step_requested.connect(_on_creature_build_step)
	level_controller.register_spawn(spawned_count)


func _on_spawning_finished(total_spawned: int) -> void:
	level_controller.register_spawning_finished(total_spawned)


func _on_creature_saved(_creature: Creature) -> void:
	level_controller.register_saved()


func _on_creature_killed(_creature: Creature) -> void:
	level_controller.register_lost()


func _on_ability_assigned(
	creature: Creature,
	ability: AbilityAssignmentControllerScript.Ability
) -> void:
	if ability != AbilityAssignmentControllerScript.Ability.DIG:
		return
	if _excavate_for_creature(creature) <= 0:
		creature.finish_dig()


func _on_creature_dig_step(creature: Creature) -> void:
	if _excavate_for_creature(creature) <= 0:
		creature.finish_dig()


func _on_creature_build_step(creature: Creature, step_index: int) -> void:
	if buildable_terrain == null or _build_for_creature(creature, step_index) <= 0:
		creature.finish_build()


func _excavate_for_creature(creature: Creature) -> int:
	return diggable_terrain.excavate_circle(
		diggable_terrain.to_local(creature.global_position + DIG_CENTER_OFFSET),
		DIG_RADIUS
	)


func _can_creature_dig(creature: Creature) -> bool:
	var probe_position := diggable_terrain.to_local(creature.global_position + DIG_PROBE_OFFSET)
	return diggable_terrain.get_material_at(probe_position) != 0


func _can_creature_build(creature: Creature) -> bool:
	if buildable_terrain == null:
		return false
	var first_step := _get_build_rect(creature, 0)
	var terrain_rect := Rect2(Vector2.ZERO, buildable_terrain.get_terrain_size())
	return terrain_rect.encloses(first_step) and buildable_terrain.get_material_at(first_step.get_center()) == 0


func _build_for_creature(creature: Creature, step_index: int) -> int:
	return buildable_terrain.fill_rectangle(_get_build_rect(creature, step_index))


func _get_build_rect(creature: Creature, step_index: int) -> Rect2:
	var feet_world := creature.global_position + BUILD_FEET_OFFSET
	var distance := BUILD_START_OFFSET + float(step_index) * BUILD_STEP_ADVANCE
	var start_x := (
		feet_world.x + distance
		if creature.direction > 0
		else feet_world.x - distance - BUILD_STEP_SIZE.x
	)
	var world_position := Vector2(start_x, feet_world.y)
	return Rect2(buildable_terrain.to_local(world_position), BUILD_STEP_SIZE)


func _on_level_completed(_saved: int, _total: int) -> void:
	_lock_finished_level()


func _on_level_failed(_saved: int, _required: int) -> void:
	_lock_finished_level()


func _lock_finished_level() -> void:
	ability_controller.set_assignment_enabled(false)
	simulation_controller.set_pause_locked(true)


func _restart_level() -> void:
	_restore_default_simulation()
	var reload_error := get_tree().reload_current_scene()
	if reload_error != OK:
		push_error("Could not restart the current level: %s" % error_string(reload_error))


func _open_level_select() -> void:
	_restore_default_simulation()
	var change_error := get_tree().change_scene_to_file(level_select_scene_path)
	if change_error != OK:
		push_error("Could not open the level selection screen: %s" % error_string(change_error))


func _restore_default_simulation() -> void:
	simulation_controller.set_pause_locked(false)
	simulation_controller.set_paused(false)
	simulation_controller.set_speed(1.0)
