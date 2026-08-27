extends Node

const AbilityAssignmentControllerScript = preload("res://scripts/gameplay/ability_assignment_controller.gd")
const WALKING_WAIT_FRAMES := 60


func _ready() -> void:
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.ignore_time_scale = true
	watchdog.one_shot = true
	watchdog.wait_time = 8.0
	watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(watchdog)
	watchdog.start()
	_run_test.call_deferred()


func _run_test() -> void:
	var failures: Array[String] = []
	var packed_scene := load("res://scenes/levels/movement_test.tscn") as PackedScene
	if packed_scene == null:
		push_error("MILESTONE_2_SMOKE_TEST: Could not load the movement test scene.")
		get_tree().quit(1)
		return

	var level := packed_scene.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var creatures := level.get_node("World/Creatures")
	var diggable_terrain := level.get_node("World/Terrain/DiggableStartTerrain")
	var ability_controller := level.get_node("AbilityAssignmentController") as AbilityAssignmentControllerScript
	var simulation_controller := level.get_node("SimulationController") as SimulationController
	var hud := level.get_node("HUD") as SimulationHUD
	var creature := creatures.get_child(0) as Creature

	for _frame in WALKING_WAIT_FRAMES:
		if creature.current_state == Creature.State.WALKING:
			break
		await get_tree().physics_frame
	if creature.current_state != Creature.State.WALKING:
		failures.append("The first creature never became a valid walking DIG target.")

	if ability_controller.dig_remaining != 10:
		failures.append("The level definition should provide 10 DIG assignments.")
	var terrain_cells_before: int = diggable_terrain.get_solid_cell_count()
	var dig_world_position := creature.global_position + Vector2(0.0, 30.0)
	var collision_surface_before := _get_first_terrain_collision_y(
		Vector2(creature.global_position.x, 350.0),
		Vector2(creature.global_position.x, 650.0)
	)
	if is_inf(collision_surface_before):
		failures.append("The starting platform had no collision before DIG.")
	ability_controller.select_dig()
	simulation_controller.set_paused(true)

	var screen_position := get_viewport().get_canvas_transform() * creature.global_position
	ability_controller.update_hover_at_screen_position(screen_position)
	if ability_controller.hovered_creature != creature or not creature.selection_highlight.visible:
		failures.append("Hover targeting did not highlight the walking creature.")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = screen_position
	click.pressed = true
	ability_controller._unhandled_input(click)
	if creature.current_state != Creature.State.DIGGING:
		failures.append("Click assignment did not begin DIGGING immediately while paused.")
	if ability_controller.dig_remaining != 9:
		failures.append("A successful DIG assignment should consume exactly one resource.")
	if diggable_terrain.get_solid_cell_count() >= terrain_cells_before:
		failures.append("A successful DIG assignment did not remove terrain cells.")
	if diggable_terrain.get_material_at(diggable_terrain.to_local(dig_world_position)) != 0:
		failures.append("The center of the DIG should report empty terrain material.")
	if hud.dig_inventory_label.text != "DIG remaining: 9":
		failures.append("The HUD did not display the decremented DIG inventory.")

	await get_tree().create_timer(0.2, true, false, true).timeout
	if creature.current_state != Creature.State.DIGGING:
		failures.append("DIGGING advanced while the simulation was paused.")
	if ability_controller.assign_selected_ability(creature):
		failures.append("A creature already DIGGING should reject another assignment.")
	if ability_controller.dig_remaining != 9:
		failures.append("A rejected assignment consumed DIG inventory.")
	var static_terrain_target := load("res://scenes/creatures/creature.tscn").instantiate() as Creature
	creatures.add_child(static_terrain_target)
	static_terrain_target.global_position = Vector2(600.0, 846.0)
	static_terrain_target.current_state = Creature.State.WALKING
	if ability_controller.assign_selected_ability(static_terrain_target):
		failures.append("DIG should reject a walking creature without destructible material below it.")
	if ability_controller.dig_remaining != 9:
		failures.append("A non-diggable terrain target consumed DIG inventory.")
	static_terrain_target.queue_free()

	simulation_controller.set_paused(false)
	var dig_frames := 0
	while creature.current_state == Creature.State.DIGGING and dig_frames < 240:
		await get_tree().physics_frame
		dig_frames += 1
	if creature.current_state == Creature.State.DIGGING:
		failures.append("DIG did not finish after tunneling through the platform.")
	if creature.current_state != Creature.State.WALKING and creature.current_state != Creature.State.FALLING:
		failures.append("The creature did not resume autonomous movement after DIGGING.")
	var bottom_material_position := Vector2(
		dig_world_position.x,
		diggable_terrain.global_position.y + diggable_terrain.get_terrain_size().y - 4.0
	)
	if diggable_terrain.get_material_at(diggable_terrain.to_local(bottom_material_position)) != 0:
		failures.append("One DIG assignment did not remove the final platform layer.")
	var collision_surface_after := _get_first_terrain_collision_y(
		Vector2(dig_world_position.x, 350.0),
		Vector2(dig_world_position.x, 650.0)
	)
	if not is_inf(collision_surface_after):
		failures.append("One DIG assignment did not open collision through the platform.")

	level.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("MILESTONE_2_SMOKE_TEST: PASS — targeting, inventory, continuous excavation, breakthrough collision, and resumed movement verified.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error("MILESTONE_2_SMOKE_TEST: %s" % failure)
	get_tree().quit(1)


func _on_watchdog_timeout() -> void:
	push_error("MILESTONE_2_SMOKE_TEST: Timed out before completing.")
	get_tree().quit(2)


func _get_first_terrain_collision_y(from: Vector2, to: Vector2) -> float:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := get_viewport().world_2d.direct_space_state.intersect_ray(query)
	return float(result["position"].y) if not result.is_empty() else INF
