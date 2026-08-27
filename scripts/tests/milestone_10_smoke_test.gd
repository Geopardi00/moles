extends Node

const AbilityAssignmentControllerScript = preload("res://scripts/gameplay/ability_assignment_controller.gd")
const COMPLETION_WAIT_SECONDS := 5.0


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
	var packed_scene := load("res://scenes/levels/bomb_puzzle.tscn") as PackedScene
	if packed_scene == null:
		push_error("MILESTONE_10_SMOKE_TEST: Could not load the BOMB puzzle.")
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
	var bomber := creatures.get_child(0) as Creature
	var initial_terrain_cells := terrain.get_solid_cell_count()

	for _frame in 180:
		if bomber.current_state == Creature.State.WALKING and bomber.global_position.x >= 710.0:
			break
		await get_tree().physics_frame
	if bomber.current_state != Creature.State.WALKING or bomber.global_position.x < 710.0:
		failures.append("The leader did not reach the marked BOMB zone as a walking target.")
	if level_controller.definition.total_creatures != 5 or level_controller.get_required_rescue_count() != 4:
		failures.append("The BOMB puzzle should require 4 of 5 rescues.")
	if (
		ability_controller.dig_remaining != 0
		or ability_controller.build_remaining != 0
		or ability_controller.block_remaining != 0
		or ability_controller.bomb_remaining != 1
	):
		failures.append("The BOMB puzzle should begin with only 1 BOMB assignment.")
	if initial_terrain_cells <= 0:
		failures.append("The destructible barrier should begin intact.")

	var bomber_position := bomber.global_position
	simulation_controller.set_paused(true)
	ability_controller.select_bomb()
	if not ability_controller.assign_selected_ability(bomber):
		failures.append("The leader rejected a valid paused BOMB assignment near the barrier.")
	if bomber.current_state != Creature.State.BOMBING:
		failures.append("A valid BOMB assignment did not enter BOMBING immediately.")
	if ability_controller.bomb_remaining != 0:
		failures.append("BOMB did not consume exactly one BOMB item.")
	if hud.bomb_inventory_label.text != "BOMB remaining: 0":
		failures.append("The HUD did not refresh the BOMB inventory.")
	await get_tree().create_timer(0.25, true, false, true).timeout
	if not is_instance_valid(bomber) or bomber.current_state != Creature.State.BOMBING:
		failures.append("The BOMB fuse advanced while the simulation was paused.")
	elif not bomber.global_position.is_equal_approx(bomber_position):
		failures.append("The bomber moved while its paused fuse was active.")
	if terrain.get_solid_cell_count() != initial_terrain_cells:
		failures.append("The barrier changed before the paused fuse resumed.")

	simulation_controller.set_speed(4.0)
	simulation_controller.set_paused(false)
	for _frame in 120:
		if level_controller.lost_count == 1:
			break
		await get_tree().physics_frame
	if level_controller.lost_count != 1:
		failures.append("The fuse did not resolve the assigned bomber as one loss.")
	if terrain.get_solid_cell_count() >= initial_terrain_cells:
		failures.append("The detonation did not persistently excavate the barrier.")
	if level_controller.saved_count != 0:
		failures.append("Followers reached the exit before the breach was created.")

	await get_tree().create_timer(COMPLETION_WAIT_SECONDS, true, false, true).timeout
	if level_controller.status != LevelController.Status.COMPLETED:
		var live_summary: Array[String] = []
		for live_creature: Creature in creatures.get_children():
			live_summary.append("%s@%s dir=%d" % [
				Creature.State.keys()[live_creature.current_state],
				live_creature.global_position,
				live_creature.direction,
			])
		failures.append(
			"The BOMB breach did not complete (status %s, saved %d, lost %d, live %s)." % [
				LevelController.Status.keys()[level_controller.status],
				level_controller.saved_count,
				level_controller.lost_count,
				live_summary,
			]
		)
	if level_controller.saved_count != 4 or level_controller.lost_count != 1:
		failures.append("Expected the bomber lost and all 4 followers rescued.")
	if not get_tree().paused or not simulation_controller.pause_locked:
		failures.append("BOMB puzzle completion did not pause and lock the simulation.")

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
		failures.append("Restart did not replace the completed BOMB puzzle scene.")
	else:
		var restarted_terrain := restarted_level.get_node("World/Terrain/DiggableStartTerrain") as ChunkedMaskTerrain
		var restarted_controller := restarted_level.get_node("LevelController") as LevelController
		var restarted_abilities := restarted_level.get_node("AbilityAssignmentController") as AbilityAssignmentControllerScript
		var restarted_simulation := restarted_level.get_node("SimulationController") as SimulationController
		if restarted_terrain.get_solid_cell_count() != initial_terrain_cells:
			failures.append("Restart did not restore the breached barrier.")
		if (
			restarted_abilities.dig_remaining != 0
			or restarted_abilities.build_remaining != 0
			or restarted_abilities.block_remaining != 0
			or restarted_abilities.bomb_remaining != 1
		):
			failures.append("Restart did not restore the BOMB-only inventory.")
		if restarted_controller.saved_count != 0 or restarted_controller.lost_count != 0:
			failures.append("Restart did not clear BOMB puzzle counters.")
		if get_tree().paused or not is_equal_approx(restarted_simulation.speed_multiplier, 1.0):
			failures.append("Restart did not restore an unpaused 1x simulation.")

	get_tree().current_scene = self
	if is_instance_valid(restarted_level):
		get_tree().root.remove_child(restarted_level)
		restarted_level.queue_free()
	await get_tree().process_frame

	if failures.is_empty():
		print("MILESTONE_10_SMOKE_TEST: PASS - paused fuse, barrier breach, 4/5 outcome, and restart verified.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("MILESTONE_10_SMOKE_TEST: %s" % failure)
	get_tree().quit(1)


func _on_watchdog_timeout() -> void:
	push_error("MILESTONE_10_SMOKE_TEST: Timed out before completing.")
	get_tree().quit(2)
