extends Node

const AbilityAssignmentControllerScript = preload("res://scripts/gameplay/ability_assignment_controller.gd")
const COMPLETION_WAIT_SECONDS := 7.0


func _ready() -> void:
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.ignore_time_scale = true
	watchdog.one_shot = true
	watchdog.wait_time = 14.0
	watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(watchdog)
	watchdog.start()
	_run_test.call_deferred()


func _run_test() -> void:
	var failures: Array[String] = []
	var packed_scene := load("res://scenes/levels/dig_build_puzzle.tscn") as PackedScene
	if packed_scene == null:
		push_error("MILESTONE_7_SMOKE_TEST: Could not load the combined puzzle.")
		get_tree().quit(1)
		return

	var level := packed_scene.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var creatures := level.get_node("World/Creatures")
	var dig_terrain := level.get_node("World/Terrain/DiggableStartTerrain") as ChunkedMaskTerrain
	var build_terrain := level.get_node("World/Terrain/BuildTerrain") as ChunkedMaskTerrain
	var level_controller := level.get_node("LevelController") as LevelController
	var simulation_controller := level.get_node("SimulationController") as SimulationController
	var ability_controller := level.get_node("AbilityAssignmentController") as AbilityAssignmentControllerScript
	var hud := level.get_node("HUD") as SimulationHUD
	var creature := creatures.get_child(0) as Creature
	var initial_dig_cells := dig_terrain.get_solid_cell_count()

	for _frame in 60:
		if creature.current_state == Creature.State.WALKING:
			break
		await get_tree().physics_frame
	if creature.current_state != Creature.State.WALKING:
		failures.append("The first creature never became a walking DIG target.")
	if level_controller.definition.total_creatures != 5 or level_controller.get_required_rescue_count() != 5:
		failures.append("The combined puzzle should require all 5 creatures.")
	if ability_controller.dig_remaining != 1 or ability_controller.build_remaining != 1:
		failures.append("The combined puzzle should provide exactly 1 DIG and 1 BUILD.")
	if build_terrain.get_solid_cell_count() != 0:
		failures.append("The bridge terrain should begin empty.")

	simulation_controller.set_paused(true)
	ability_controller.select_dig()
	if not ability_controller.assign_selected_ability(creature):
		failures.append("The upper creature rejected the required DIG assignment.")
	if ability_controller.dig_remaining != 0 or ability_controller.build_remaining != 1:
		failures.append("DIG did not consume only the DIG inventory.")
	if hud.dig_inventory_label.text != "DIG remaining: 0" or hud.build_inventory_label.text != "BUILD remaining: 1":
		failures.append("The HUD did not show the independent post-DIG inventories.")
	if dig_terrain.get_solid_cell_count() >= initial_dig_cells:
		failures.append("The initial DIG assignment did not modify the upper terrain.")

	simulation_controller.set_speed(4.0)
	simulation_controller.set_paused(false)
	for _frame in 300:
		if (
			is_instance_valid(creature)
			and creature.current_state == Creature.State.WALKING
			and creature.global_position.y > 600.0
			and creature.global_position.x >= 790.0
		):
			break
		if level_controller.status != LevelController.Status.RUNNING:
			break
		await get_tree().physics_frame
	if not is_instance_valid(creature):
		failures.append(
			"The DIG creature was lost before BUILD (status %s, saved %d, lost %d)." % [
				LevelController.Status.keys()[level_controller.status],
				level_controller.saved_count,
				level_controller.lost_count,
			]
		)
	elif creature.current_state != Creature.State.WALKING:
		failures.append(
			"The DIG creature did not reach the lower route safely (position %s, direction %d, state %s)." % [
				creature.global_position,
				creature.direction,
				Creature.State.keys()[creature.current_state],
			]
		)
	elif creature.global_position.y <= 600.0 or creature.global_position.x < 790.0:
		failures.append(
			"The DIG creature did not reach the BUILD zone (position %s, direction %d, state %s)." % [
				creature.global_position,
				creature.direction,
				Creature.State.keys()[creature.current_state],
			]
		)
	if level_controller.saved_count != 0 or build_terrain.get_solid_cell_count() != 0:
		failures.append("DIG alone unexpectedly completed or altered the blocked lower route.")

	simulation_controller.set_paused(true)
	ability_controller.select_build()
	if not ability_controller.assign_selected_ability(creature):
		failures.append("The lower-route creature rejected the required BUILD assignment.")
	if ability_controller.dig_remaining != 0 or ability_controller.build_remaining != 0:
		failures.append("BUILD did not consume only the final BUILD inventory.")
	await get_tree().create_timer(0.25, true, false, true).timeout
	if build_terrain.get_solid_cell_count() != 0:
		failures.append("The combined puzzle's BUILD advanced while paused.")

	simulation_controller.set_paused(false)
	await get_tree().create_timer(COMPLETION_WAIT_SECONDS, true, false, true).timeout
	if dig_terrain.get_solid_cell_count() >= initial_dig_cells:
		failures.append("The DIG modification did not persist through completion.")
	if build_terrain.get_solid_cell_count() <= 0:
		failures.append("The BUILD modification did not persist through completion.")
	if level_controller.status != LevelController.Status.COMPLETED:
		failures.append("DIG followed by BUILD did not complete the combined puzzle.")
	if level_controller.saved_count != 5 or level_controller.lost_count != 0:
		failures.append("Expected all 5 creatures saved after both interventions.")
	if not get_tree().paused or not simulation_controller.pause_locked:
		failures.append("Combined-puzzle completion did not pause and lock the simulation.")

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
		failures.append("Restart did not replace the combined puzzle scene.")
	else:
		var restarted_dig := restarted_level.get_node("World/Terrain/DiggableStartTerrain") as ChunkedMaskTerrain
		var restarted_build := restarted_level.get_node("World/Terrain/BuildTerrain") as ChunkedMaskTerrain
		var restarted_controller := restarted_level.get_node("LevelController") as LevelController
		var restarted_abilities := restarted_level.get_node("AbilityAssignmentController") as AbilityAssignmentControllerScript
		var restarted_simulation := restarted_level.get_node("SimulationController") as SimulationController
		if restarted_dig.get_solid_cell_count() != initial_dig_cells:
			failures.append("Restart did not restore the excavated upper terrain.")
		if restarted_build.get_solid_cell_count() != 0:
			failures.append("Restart did not clear the constructed bridge.")
		if restarted_abilities.dig_remaining != 1 or restarted_abilities.build_remaining != 1:
			failures.append("Restart did not restore both limited inventories.")
		if restarted_controller.saved_count != 0 or restarted_controller.lost_count != 0:
			failures.append("Restart did not clear the combined-puzzle counters.")
		if get_tree().paused or not is_equal_approx(restarted_simulation.speed_multiplier, 1.0):
			failures.append("Restart did not restore an unpaused 1x simulation.")

	get_tree().current_scene = self
	if is_instance_valid(restarted_level):
		get_tree().root.remove_child(restarted_level)
		restarted_level.queue_free()
	await get_tree().process_frame

	if failures.is_empty():
		print("MILESTONE_7_SMOKE_TEST: PASS - DIG then BUILD completed the puzzle and restart restored both terrains.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("MILESTONE_7_SMOKE_TEST: %s" % failure)
	get_tree().quit(1)


func _on_watchdog_timeout() -> void:
	push_error("MILESTONE_7_SMOKE_TEST: Timed out before completing.")
	get_tree().quit(2)
