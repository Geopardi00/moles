extends Node

const AbilityAssignmentControllerScript = preload("res://scripts/gameplay/ability_assignment_controller.gd")
const COMPLETION_WAIT_SECONDS := 6.0


func _ready() -> void:
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.ignore_time_scale = true
	watchdog.one_shot = true
	watchdog.wait_time = 12.0
	watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(watchdog)
	watchdog.start()
	_run_test.call_deferred()


func _run_test() -> void:
	var failures: Array[String] = []
	var packed_scene := load("res://scenes/levels/build_puzzle.tscn") as PackedScene
	if packed_scene == null:
		push_error("MILESTONE_6_SMOKE_TEST: Could not load the BUILD puzzle.")
		get_tree().quit(1)
		return

	var level := packed_scene.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var creatures := level.get_node("World/Creatures")
	var terrain := level.get_node("World/Terrain/DiggableStartTerrain") as ChunkedMaskTerrain
	var level_controller := level.get_node("LevelController") as LevelController
	var simulation_controller := level.get_node("SimulationController") as SimulationController
	var ability_controller := level.get_node("AbilityAssignmentController") as AbilityAssignmentControllerScript
	var hud := level.get_node("HUD") as SimulationHUD
	var kill_zone := level.get_node("World/KillZone") as KillZone
	var loss_positions: Array[Vector2] = []
	kill_zone.creature_killed.connect(func(lost_creature: Creature) -> void:
		loss_positions.append(lost_creature.global_position)
	)
	var creature := creatures.get_child(0) as Creature
	var initial_terrain_cells := terrain.get_solid_cell_count()

	for _frame in 180:
		if creature.current_state == Creature.State.WALKING and creature.global_position.x >= 600.0:
			break
		await get_tree().physics_frame
	if creature.current_state != Creature.State.WALKING or creature.global_position.x < 600.0:
		failures.append("The first creature did not reach the marked BUILD zone as a walking target.")
	if level_controller.definition.total_creatures != 5 or level_controller.get_required_rescue_count() != 5:
		failures.append("The BUILD puzzle should require all 5 creatures to be rescued.")
	if ability_controller.dig_remaining != 0 or ability_controller.build_remaining != 2:
		failures.append("The BUILD puzzle should begin with 0 DIG and 2 BUILD assignments.")
	if initial_terrain_cells != 0:
		failures.append("The bridge terrain should begin empty.")

	var builder_x := creature.global_position.x
	simulation_controller.set_paused(true)
	ability_controller.select_build()
	if not ability_controller.assign_selected_ability(creature):
		failures.append("The creature rejected a valid paused BUILD assignment.")
	if creature.current_state != Creature.State.BUILDING:
		failures.append("A valid BUILD assignment did not enter BUILDING immediately.")
	if ability_controller.build_remaining != 1 or ability_controller.dig_remaining != 0:
		failures.append("BUILD did not consume exactly one BUILD item while leaving DIG unchanged.")
	if hud.build_inventory_label.text != "BUILD remaining: 1":
		failures.append("The HUD did not refresh the BUILD inventory.")
	await get_tree().create_timer(0.25, true, false, true).timeout
	if terrain.get_solid_cell_count() != initial_terrain_cells:
		failures.append("BUILD advanced while paused (%d cells were added)." % terrain.get_solid_cell_count())

	simulation_controller.set_speed(4.0)
	simulation_controller.set_paused(false)
	await get_tree().create_timer(COMPLETION_WAIT_SECONDS, true, false, true).timeout
	if terrain.get_solid_cell_count() <= initial_terrain_cells:
		failures.append("BUILD did not add persistent terrain.")
	var ahead_sample := terrain.to_local(Vector2(builder_x + 80.0, 408.0))
	var behind_sample := terrain.to_local(Vector2(builder_x - 24.0, 408.0))
	if terrain.get_material_at(ahead_sample) == 0:
		failures.append("BUILD did not place terrain ahead of the creature's facing direction.")
	if terrain.get_material_at(behind_sample) != 0:
		failures.append("BUILD unexpectedly placed terrain behind the creature.")
	if level_controller.status != LevelController.Status.COMPLETED:
		var live_creature_summary: Array[String] = []
		for live_creature: Creature in creatures.get_children():
			live_creature_summary.append("%s@%s" % [
				Creature.State.keys()[live_creature.current_state],
				live_creature.global_position,
			])
		failures.append(
			"One BUILD did not complete the route (status %s, saved %d, lost %d, cells %d, losses %s, live %s)." % [
				LevelController.Status.keys()[level_controller.status],
				level_controller.saved_count,
				level_controller.lost_count,
				terrain.get_solid_cell_count(),
				loss_positions,
				live_creature_summary,
			]
		)
	if level_controller.saved_count != 5 or level_controller.lost_count != 0:
		failures.append(
			"Expected all 5 creatures saved across the bridge; got %d saved and %d lost." % [
				level_controller.saved_count,
				level_controller.lost_count,
			]
		)
	if not get_tree().paused or not simulation_controller.pause_locked:
		failures.append("Puzzle completion did not pause and lock the simulation.")

	remove_child(level)
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	var restart_event := InputEventAction.new()
	restart_event.action = "level_restart"
	restart_event.pressed = true
	hud._unhandled_input(restart_event)
	await get_tree().process_frame
	await get_tree().process_frame
	var restarted_level := get_tree().current_scene
	if restarted_level == null or restarted_level == level:
		failures.append("Restart did not replace the completed BUILD puzzle scene.")
	else:
		var restarted_terrain := restarted_level.get_node("World/Terrain/DiggableStartTerrain") as ChunkedMaskTerrain
		var restarted_controller := restarted_level.get_node("LevelController") as LevelController
		var restarted_abilities := restarted_level.get_node("AbilityAssignmentController") as AbilityAssignmentControllerScript
		var restarted_simulation := restarted_level.get_node("SimulationController") as SimulationController
		if restarted_terrain.get_solid_cell_count() != initial_terrain_cells:
			failures.append("Restart did not clear the constructed bridge terrain.")
		if restarted_abilities.dig_remaining != 0 or restarted_abilities.build_remaining != 2:
			failures.append("Restart did not restore both ability inventories.")
		if restarted_controller.saved_count != 0 or restarted_controller.lost_count != 0:
			failures.append("Restart did not clear BUILD puzzle outcome counters.")
		if get_tree().paused or not is_equal_approx(restarted_simulation.speed_multiplier, 1.0):
			failures.append("Restart did not restore an unpaused 1x simulation.")

	get_tree().current_scene = self
	if is_instance_valid(restarted_level):
		get_tree().root.remove_child(restarted_level)
		restarted_level.queue_free()
	await get_tree().process_frame

	if failures.is_empty():
		print("MILESTONE_6_SMOKE_TEST: PASS - one BUILD bridged the gap; completion and full restart verified.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("MILESTONE_6_SMOKE_TEST: %s" % failure)
	get_tree().quit(1)


func _on_watchdog_timeout() -> void:
	push_error("MILESTONE_6_SMOKE_TEST: Timed out before completing.")
	get_tree().quit(2)
