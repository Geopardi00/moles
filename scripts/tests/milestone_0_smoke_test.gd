extends Node

const REAL_TEST_DURATION_SECONDS := 7.0


func _ready() -> void:
	_run_test.call_deferred()


func _run_test() -> void:
	# Load after SceneTree initialization. This keeps the command-line harness
	# independent from the editor's global-class cache.
	var packed_scene := load("res://scenes/levels/movement_test.tscn") as PackedScene
	if packed_scene == null:
		push_error("MILESTONE_0_SMOKE_TEST: Could not load the movement test scene.")
		get_tree().quit(1)
		return
	var level := packed_scene.instantiate()
	add_child(level)
	await get_tree().process_frame

	var controller := level.get_node("SimulationController")
	var spawner := level.get_node("World/CreatureSpawner")
	var creature_container := level.get_node("World/Creatures")
	var failures: Array[String] = []

	# Confirm pause freezes pausable world nodes without stopping always-processing controls.
	await get_tree().physics_frame
	var first_creature := creature_container.get_child(0) as CharacterBody2D
	var position_before_pause := first_creature.global_position
	var spawns_before_pause: int = spawner.spawned_count
	controller.set_paused(true)
	await get_tree().create_timer(0.4, true, false, true).timeout
	if not first_creature.global_position.is_equal_approx(position_before_pause):
		failures.append("Creature movement continued while paused.")
	if spawner.spawned_count != spawns_before_pause:
		failures.append("Spawner continued while paused.")
	if level.get_node("CameraRig").process_mode != Node.PROCESS_MODE_ALWAYS:
		failures.append("CameraRig must process while paused.")
	if level.get_node("HUD").process_mode != Node.PROCESS_MODE_ALWAYS:
		failures.append("HUD must process while paused.")
	controller.set_paused(false)

	# Four-times speed keeps the smoke test short while exercising the supported maximum.
	controller.set_speed(4.0)
	await get_tree().create_timer(REAL_TEST_DURATION_SECONDS, true, false, true).timeout

	if spawner.spawned_count != spawner.spawn_count:
		failures.append("Expected %d spawns, got %d." % [spawner.spawn_count, spawner.spawned_count])
	if level.saved_count != spawner.spawn_count:
		failures.append("Expected %d rescues, got %d." % [spawner.spawn_count, level.saved_count])
	if level.lost_count != 0:
		failures.append("Expected no losses, got %d." % level.lost_count)
	if creature_container.get_child_count() != 0:
		failures.append("Expected no remaining creatures, got %d." % creature_container.get_child_count())

	controller.set_paused(false)
	controller.set_speed(1.0)
	if failures.is_empty():
		print("MILESTONE_0_SMOKE_TEST: PASS — pause held; 30 creatures spawned, navigated, and exited.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error("MILESTONE_0_SMOKE_TEST: %s" % failure)
	get_tree().quit(1)
