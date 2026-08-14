extends Node

const REAL_TEST_DURATION_SECONDS := 7.0


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
	var packed_scene := load("res://scenes/levels/movement_test.tscn") as PackedScene
	if packed_scene == null:
		push_error("MILESTONE_1_SMOKE_TEST: Could not load the movement test scene.")
		get_tree().quit(1)
		return

	var level := packed_scene.instantiate()
	add_child(level)
	await get_tree().process_frame

	var level_controller := level.get_node("LevelController")
	var simulation_controller := level.get_node("SimulationController")
	var hud := level.get_node("HUD")
	if level_controller.definition.total_creatures != 30:
		failures.append("LevelDefinition should configure 30 creatures.")
	if level_controller.get_required_rescue_count() != 24:
		failures.append("The 80%% requirement should resolve to 24 of 30 creatures.")

	simulation_controller.set_speed(4.0)
	await get_tree().create_timer(REAL_TEST_DURATION_SECONDS, true, false, true).timeout

	if level_controller.status != LevelController.Status.COMPLETED:
		failures.append("The successful route did not complete the level.")
	if level_controller.saved_count != 30 or level_controller.lost_count != 0:
		failures.append("Expected 30 saved and 0 lost at completion.")
	if not get_tree().paused or not simulation_controller.pause_locked:
		failures.append("A finished level must remain paused and locked.")
	if not hud.get_node("ResultOverlay").visible:
		failures.append("The completion overlay should be visible.")

	# Exercise the real restart path and confirm a fresh level becomes current.
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
	if restarted_level == level or restarted_level == null:
		failures.append("Restart did not replace the completed level scene.")
	else:
		var restarted_controller := restarted_level.get_node("LevelController")
		var restarted_simulation := restarted_level.get_node("SimulationController")
		var restarted_spawner := restarted_level.get_node("World/CreatureSpawner")
		if restarted_controller.status != LevelController.Status.RUNNING:
			failures.append("Restarted level should return to RUNNING.")
		if restarted_controller.saved_count != 0 or restarted_controller.lost_count != 0:
			failures.append("Restarted level counters were not reset.")
		if get_tree().paused or not is_equal_approx(restarted_simulation.speed_multiplier, 1.0):
			failures.append("Restart should restore unpaused 1× simulation.")
		# Finish the spawner coroutine quickly before removing this temporary scene.
		restarted_spawner.spawn_interval = 0.01
		await get_tree().create_timer(0.7, true, false, true).timeout

	get_tree().current_scene = self
	if is_instance_valid(restarted_level):
		get_tree().root.remove_child(restarted_level)
		restarted_level.queue_free()
	await get_tree().process_frame

	# Test the controller's early-failure rule without needing a second terrain scene.
	var failed_definition := load("res://resources/levels/movement_test_level.tres").duplicate()
	failed_definition.total_creatures = 10
	failed_definition.rescue_requirement_mode = 0
	failed_definition.required_rescue_count = 8
	var failure_controller := LevelController.new()
	add_child(failure_controller)
	failure_controller.begin_level(failed_definition)
	for spawn_number in range(1, 11):
		failure_controller.register_spawn(spawn_number)
	for _loss in 3:
		failure_controller.register_lost()
	if failure_controller.status != LevelController.Status.FAILED:
		failures.append("Losing 3 of 10 should fail an 8-rescue requirement immediately.")

	if failures.is_empty():
		print("MILESTONE_1_SMOKE_TEST: PASS — data, completion, failure, and outcome pause verified.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error("MILESTONE_1_SMOKE_TEST: %s" % failure)
	get_tree().quit(1)


func _on_watchdog_timeout() -> void:
	push_error("MILESTONE_1_SMOKE_TEST: Timed out before completing.")
	get_tree().quit(2)
