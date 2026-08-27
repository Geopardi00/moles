extends Node

const LevelSelectScript = preload("res://scripts/ui/level_select.gd")


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
	var packed_scene := load("res://scenes/ui/level_select.tscn") as PackedScene
	if packed_scene == null:
		push_error("MILESTONE_8_SMOKE_TEST: Could not load the level-selection scene.")
		get_tree().quit(1)
		return

	get_tree().paused = true
	Engine.time_scale = 4.0
	var menu := packed_scene.instantiate() as LevelSelectScript
	add_child(menu)
	await get_tree().process_frame
	if get_tree().paused or not is_equal_approx(Engine.time_scale, 1.0):
		failures.append("Opening level selection did not normalize pause and speed state.")
	if menu.catalog == null or menu.catalog.entries.size() != 5:
		failures.append("The level catalog should expose all 5 authored puzzles.")
	if menu.level_buttons.size() != 5:
		failures.append("The level-selection screen should create 5 launch buttons.")
	else:
		if "First Dig" not in menu.level_buttons[0].text:
			failures.append("The first catalog entry was not rendered in order.")
		if "Bridge the Gap" not in menu.level_buttons[1].text:
			failures.append("The second catalog entry was not rendered in order.")
		if "Down and Across" not in menu.level_buttons[2].text:
			failures.append("The third catalog entry was not rendered in order.")
		if "Hold the Line" not in menu.level_buttons[3].text:
			failures.append("The fourth catalog entry was not rendered in order.")
		if "Breaching Charge" not in menu.level_buttons[4].text:
			failures.append("The fifth catalog entry was not rendered in order.")
	for entry in menu.catalog.entries:
		if entry == null or not ResourceLoader.exists(entry.scene_path, "PackedScene"):
			failures.append("Catalog entry '%s' does not point to a loadable level scene." % entry.title)

	remove_child(menu)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	if menu.level_buttons.size() == 5:
		menu.level_buttons[2].pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var loaded_level := get_tree().current_scene
	if loaded_level == null or loaded_level.name != "DigBuildPuzzle":
		failures.append("The combined-puzzle menu button did not launch its configured scene.")
	else:
		var simulation_controller := loaded_level.get_node("SimulationController") as SimulationController
		var hud := loaded_level.get_node("HUD") as SimulationHUD
		simulation_controller.set_speed(4.0)
		simulation_controller.set_paused(true)
		simulation_controller.set_pause_locked(true)
		if hud.level_select_button.disabled or hud.result_level_select_button.disabled:
			failures.append("Level-selection navigation was disabled by paused/outcome state.")
		hud.result_level_select_button.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var returned_menu := get_tree().current_scene as LevelSelectScript
		if returned_menu == null:
			failures.append("The in-level navigation control did not return to level selection.")
		else:
			if get_tree().paused or not is_equal_approx(Engine.time_scale, 1.0):
				failures.append("Returning from a locked level leaked pause or speed state.")
			if returned_menu.level_buttons.size() != 5:
				failures.append("The returned level-selection screen did not rebuild its catalog.")

	var final_scene := get_tree().current_scene
	get_tree().current_scene = self
	if final_scene != null and final_scene != self:
		get_tree().root.remove_child(final_scene)
		final_scene.queue_free()
	await get_tree().process_frame

	if failures.is_empty():
		print("MILESTONE_8_SMOKE_TEST: PASS - catalog launch and paused/outcome return navigation verified.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("MILESTONE_8_SMOKE_TEST: %s" % failure)
	get_tree().quit(1)


func _on_watchdog_timeout() -> void:
	push_error("MILESTONE_8_SMOKE_TEST: Timed out before completing.")
	get_tree().quit(2)
