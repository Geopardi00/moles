extends Node

const AbilityAssignmentControllerScript = preload("res://scripts/gameplay/ability_assignment_controller.gd")
const COMPLETION_WAIT_SECONDS := 7.0


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
	var packed_scene := load("res://scenes/levels/dig_puzzle.tscn") as PackedScene
	if packed_scene == null:
		push_error("MILESTONE_5_SMOKE_TEST: Could not load the DIG puzzle.")
		get_tree().quit(1)
		return

	var level := packed_scene.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var creatures := level.get_node("World/Creatures")
	var terrain := level.get_node("World/Terrain/DiggableStartTerrain")
	var level_controller := level.get_node("LevelController") as LevelController
	var simulation_controller := level.get_node("SimulationController") as SimulationController
	var ability_controller := level.get_node("AbilityAssignmentController") as AbilityAssignmentControllerScript
	var hud := level.get_node("HUD") as SimulationHUD
	var creature := creatures.get_child(0) as Creature
	var initial_terrain_cells: int = terrain.get_solid_cell_count()

	for _frame in 60:
		if creature.current_state == Creature.State.WALKING:
			break
		await get_tree().physics_frame
	if creature.current_state != Creature.State.WALKING:
		failures.append("The first puzzle creature never became a walking DIG target.")
	if level_controller.definition.total_creatures != 10:
		failures.append("The DIG puzzle should configure 10 creatures.")
	if level_controller.get_required_rescue_count() != 8:
		failures.append("The DIG puzzle should require 8 of 10 rescues.")
	if ability_controller.dig_remaining != 3:
		failures.append("The DIG puzzle should provide 3 DIG assignments.")
	if level_controller.saved_count != 0:
		failures.append("Creatures reached the exit before the required DIG intervention.")

	simulation_controller.set_paused(true)
	ability_controller.select_dig()
	if not ability_controller.assign_selected_ability(creature):
		failures.append("The upper-route creature rejected the puzzle's DIG assignment.")
	if ability_controller.dig_remaining != 2:
		failures.append("The puzzle solution should consume exactly one DIG.")
	simulation_controller.set_speed(4.0)
	simulation_controller.set_paused(false)
	await get_tree().create_timer(COMPLETION_WAIT_SECONDS, true, false, true).timeout
	if terrain.get_solid_cell_count() >= initial_terrain_cells:
		failures.append("The puzzle DIG did not persistently modify terrain.")
	if level_controller.status != LevelController.Status.COMPLETED:
		failures.append("One DIG did not open a complete rescue route.")
	if level_controller.saved_count != 10 or level_controller.lost_count != 0:
		failures.append("Expected all 10 creatures saved through the opened route.")
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
		failures.append("Restart did not replace the completed puzzle scene.")
	else:
		var restarted_terrain := restarted_level.get_node("World/Terrain/DiggableStartTerrain")
		var restarted_controller := restarted_level.get_node("LevelController") as LevelController
		var restarted_abilities := restarted_level.get_node("AbilityAssignmentController") as AbilityAssignmentControllerScript
		var restarted_simulation := restarted_level.get_node("SimulationController") as SimulationController
		if restarted_terrain.get_solid_cell_count() != initial_terrain_cells:
			failures.append("Restart did not restore the puzzle terrain.")
		if restarted_abilities.dig_remaining != 3:
			failures.append("Restart did not restore DIG inventory.")
		if restarted_controller.saved_count != 0 or restarted_controller.lost_count != 0:
			failures.append("Restart did not clear puzzle outcome counters.")
		if get_tree().paused or not is_equal_approx(restarted_simulation.speed_multiplier, 1.0):
			failures.append("Restart did not restore an unpaused 1× simulation.")

	get_tree().current_scene = self
	if is_instance_valid(restarted_level):
		get_tree().root.remove_child(restarted_level)
		restarted_level.queue_free()
	await get_tree().process_frame

	if failures.is_empty():
		print("MILESTONE_5_SMOKE_TEST: PASS — one DIG opened the rescue route; completion and full restart verified.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("MILESTONE_5_SMOKE_TEST: %s" % failure)
	get_tree().quit(1)


func _on_watchdog_timeout() -> void:
	push_error("MILESTONE_5_SMOKE_TEST: Timed out before completing.")
	get_tree().quit(2)
