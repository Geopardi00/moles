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
	var packed_scene := load("res://scenes/levels/block_puzzle.tscn") as PackedScene
	if packed_scene == null:
		push_error("MILESTONE_9_SMOKE_TEST: Could not load the BLOCK puzzle.")
		get_tree().quit(1)
		return

	var level := packed_scene.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var creatures := level.get_node("World/Creatures")
	var level_controller := level.get_node("LevelController") as LevelController
	var simulation_controller := level.get_node("SimulationController") as SimulationController
	var ability_controller := level.get_node("AbilityAssignmentController") as AbilityAssignmentControllerScript
	var hud := level.get_node("HUD") as SimulationHUD
	var blocker := creatures.get_child(0) as Creature

	for _frame in 180:
		if blocker.current_state == Creature.State.WALKING and blocker.global_position.x >= 730.0:
			break
		await get_tree().physics_frame
	if blocker.current_state != Creature.State.WALKING or blocker.global_position.x < 730.0:
		failures.append("The leader did not reach the marked BLOCK zone as a walking target.")
	if level_controller.definition.total_creatures != 5 or level_controller.get_required_rescue_count() != 4:
		failures.append("The BLOCK puzzle should require 4 of 5 rescues.")
	if (
		ability_controller.dig_remaining != 0
		or ability_controller.build_remaining != 0
		or ability_controller.block_remaining != 1
	):
		failures.append("The BLOCK puzzle should begin with only 1 BLOCK assignment.")
	if level_controller.saved_count != 0 or level_controller.lost_count != 0:
		failures.append("The BLOCK puzzle resolved creatures before intervention.")

	var blocker_position := blocker.global_position
	var redirected_ids: Dictionary = {}
	blocker.blocker_redirected.connect(func(_source: Creature, redirected: Creature) -> void:
		redirected_ids[redirected.get_instance_id()] = true
	)
	simulation_controller.set_paused(true)
	ability_controller.select_block()
	if not ability_controller.assign_selected_ability(blocker):
		failures.append("The leader rejected a valid paused BLOCK assignment.")
	if blocker.current_state != Creature.State.BLOCKING:
		failures.append("A valid BLOCK assignment did not enter BLOCKING immediately.")
	if ability_controller.block_remaining != 0:
		failures.append("BLOCK did not consume exactly one BLOCK item.")
	if hud.block_inventory_label.text != "BLOCK remaining: 0":
		failures.append("The HUD did not refresh the BLOCK inventory.")
	await get_tree().create_timer(0.25, true, false, true).timeout
	if blocker.current_state != Creature.State.BLOCKING or not blocker.global_position.is_equal_approx(blocker_position):
		failures.append("BLOCK advanced or moved while the simulation was paused.")

	simulation_controller.set_speed(4.0)
	simulation_controller.set_paused(false)
	await get_tree().create_timer(COMPLETION_WAIT_SECONDS, true, false, true).timeout
	if redirected_ids.size() != 4:
		failures.append("Expected the blocker to redirect 4 followers; redirected %d." % redirected_ids.size())
	if level_controller.status != LevelController.Status.COMPLETED:
		failures.append("The BLOCK intervention did not complete the rescue route.")
	if level_controller.saved_count != 4 or level_controller.lost_count != 1:
		failures.append("Expected 4 followers saved and the released blocker lost.")
	if not get_tree().paused or not simulation_controller.pause_locked:
		failures.append("BLOCK puzzle completion did not pause and lock the simulation.")

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
		failures.append("Restart did not replace the completed BLOCK puzzle scene.")
	else:
		var restarted_controller := restarted_level.get_node("LevelController") as LevelController
		var restarted_abilities := restarted_level.get_node("AbilityAssignmentController") as AbilityAssignmentControllerScript
		var restarted_simulation := restarted_level.get_node("SimulationController") as SimulationController
		if (
			restarted_abilities.dig_remaining != 0
			or restarted_abilities.build_remaining != 0
			or restarted_abilities.block_remaining != 1
		):
			failures.append("Restart did not restore the BLOCK-only inventory.")
		if restarted_controller.saved_count != 0 or restarted_controller.lost_count != 0:
			failures.append("Restart did not clear BLOCK puzzle counters.")
		if get_tree().paused or not is_equal_approx(restarted_simulation.speed_multiplier, 1.0):
			failures.append("Restart did not restore an unpaused 1x simulation.")

	get_tree().current_scene = self
	if is_instance_valid(restarted_level):
		get_tree().root.remove_child(restarted_level)
		restarted_level.queue_free()
	await get_tree().process_frame

	if failures.is_empty():
		print("MILESTONE_9_SMOKE_TEST: PASS - BLOCK redirected 4 followers; outcome and restart verified.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("MILESTONE_9_SMOKE_TEST: %s" % failure)
	get_tree().quit(1)


func _on_watchdog_timeout() -> void:
	push_error("MILESTONE_9_SMOKE_TEST: Timed out before completing.")
	get_tree().quit(2)
