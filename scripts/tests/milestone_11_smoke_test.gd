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
	var packed_scene := load("res://scenes/levels/mine_puzzle.tscn") as PackedScene
	if packed_scene == null:
		push_error("MILESTONE_11_SMOKE_TEST: Could not load the MINE puzzle.")
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
	var miner := creatures.get_child(0) as Creature
	var initial_terrain_cells := terrain.get_solid_cell_count()

	for _frame in 60:
		if miner.current_state == Creature.State.WALKING:
			break
		await get_tree().physics_frame
	if miner.current_state != Creature.State.WALKING:
		failures.append("The first creature never became a walking MINE target.")
	if level_controller.definition.total_creatures != 6 or level_controller.get_required_rescue_count() != 6:
		failures.append("The MINE puzzle should require all 6 creatures.")
	if (
		ability_controller.dig_remaining != 0
		or ability_controller.mine_remaining != 1
		or ability_controller.build_remaining != 0
		or ability_controller.block_remaining != 0
		or ability_controller.bomb_remaining != 0
	):
		failures.append("The MINE puzzle should begin with only 1 MINE assignment.")

	var miner_position := miner.global_position
	simulation_controller.set_paused(true)
	ability_controller.select_mine()
	if not ability_controller.assign_selected_ability(miner):
		failures.append("The upper-route creature rejected a valid paused MINE assignment.")
	if miner.current_state != Creature.State.MINING:
		failures.append("A valid MINE assignment did not enter MINING immediately.")
	if ability_controller.mine_remaining != 0:
		failures.append("MINE did not consume exactly one MINE item.")
	if hud.mine_inventory_label.text != "MINE remaining: 0":
		failures.append("The HUD did not refresh the MINE inventory.")
	var assigned_terrain_cells := terrain.get_solid_cell_count()
	if assigned_terrain_cells >= initial_terrain_cells:
		failures.append("The initial MINE pulse did not modify terrain.")
	await get_tree().create_timer(0.25, true, false, true).timeout
	if miner.current_state != Creature.State.MINING or not miner.global_position.is_equal_approx(miner_position):
		failures.append("MINE moved or changed state while paused.")
	if terrain.get_solid_cell_count() != assigned_terrain_cells:
		failures.append("MINE emitted additional excavation steps while paused.")

	simulation_controller.set_speed(4.0)
	simulation_controller.set_paused(false)
	await get_tree().create_timer(COMPLETION_WAIT_SECONDS, true, false, true).timeout
	if terrain.get_solid_cell_count() >= assigned_terrain_cells:
		failures.append("MINE did not continue persistent excavation after resume.")
	if terrain.get_material_at(terrain.to_local(Vector2(620.0, 380.0))) != 0:
		failures.append("MINE did not open the expected forward/downward tunnel path.")
	if terrain.get_material_at(terrain.to_local(Vector2(430.0, 380.0))) == 0:
		failures.append("MINE unexpectedly excavated behind the creature's facing direction.")
	if level_controller.status != LevelController.Status.COMPLETED:
		var live_summary: Array[String] = []
		for live_creature: Creature in creatures.get_children():
			live_summary.append("%s@%s dir=%d" % [
				Creature.State.keys()[live_creature.current_state],
				live_creature.global_position,
				live_creature.direction,
			])
		failures.append(
			"The diagonal tunnel did not complete the route (saved %d, lost %d, live %s)." % [
				level_controller.saved_count,
				level_controller.lost_count,
				live_summary,
			]
		)
	if level_controller.saved_count != 6 or level_controller.lost_count != 0:
		failures.append("Expected all 6 creatures rescued through the mined tunnel.")
	if not get_tree().paused or not simulation_controller.pause_locked:
		failures.append("MINE puzzle completion did not pause and lock the simulation.")

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
		failures.append("Restart did not replace the completed MINE puzzle scene.")
	else:
		var restarted_terrain := restarted_level.get_node("World/Terrain/DiggableStartTerrain") as ChunkedMaskTerrain
		var restarted_controller := restarted_level.get_node("LevelController") as LevelController
		var restarted_abilities := restarted_level.get_node("AbilityAssignmentController") as AbilityAssignmentControllerScript
		var restarted_simulation := restarted_level.get_node("SimulationController") as SimulationController
		if restarted_terrain.get_solid_cell_count() != initial_terrain_cells:
			failures.append("Restart did not restore the mined shelf.")
		if (
			restarted_abilities.dig_remaining != 0
			or restarted_abilities.mine_remaining != 1
			or restarted_abilities.build_remaining != 0
			or restarted_abilities.block_remaining != 0
			or restarted_abilities.bomb_remaining != 0
		):
			failures.append("Restart did not restore the MINE-only inventory.")
		if restarted_controller.saved_count != 0 or restarted_controller.lost_count != 0:
			failures.append("Restart did not clear MINE puzzle counters.")
		if get_tree().paused or not is_equal_approx(restarted_simulation.speed_multiplier, 1.0):
			failures.append("Restart did not restore an unpaused 1x simulation.")

	get_tree().current_scene = self
	if is_instance_valid(restarted_level):
		get_tree().root.remove_child(restarted_level)
		restarted_level.queue_free()
	await get_tree().process_frame

	if failures.is_empty():
		print("MILESTONE_11_SMOKE_TEST: PASS - directional tunnel, 6-creature route, and restart verified.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("MILESTONE_11_SMOKE_TEST: %s" % failure)
	get_tree().quit(1)


func _on_watchdog_timeout() -> void:
	push_error("MILESTONE_11_SMOKE_TEST: Timed out before completing.")
	get_tree().quit(2)
