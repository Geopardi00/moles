extends Node

const ProgressStoreScript = preload("res://scripts/core/progress_store.gd")
const TEST_DIRECTORY := "user://tests"
const TEST_PROGRESS_PATH := TEST_DIRECTORY + "/milestone_13_progress.cfg"
const CORRUPT_PROGRESS_PATH := TEST_DIRECTORY + "/milestone_13_corrupt.cfg"
const INVALID_MEDAL_PATH := TEST_DIRECTORY + "/milestone_13_invalid_medal.cfg"
const NEWER_PROGRESS_PATH := TEST_DIRECTORY + "/milestone_13_newer.cfg"
const TEST_TIMEOUT_SECONDS := 12.0


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--visual-progress-menu"):
		_show_visual_progress_menu.call_deferred()
		return
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.ignore_time_scale = true
	watchdog.one_shot = true
	watchdog.wait_time = TEST_TIMEOUT_SECONDS
	watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(watchdog)
	watchdog.start()
	_run_test.call_deferred()


func _show_visual_progress_menu() -> void:
	_remove_test_files()
	var progress_store := get_node("/root/ProgressStore")
	progress_store.load_progress(TEST_PROGRESS_PATH)
	var catalog := load("res://resources/levels/level_catalog.tres") as LevelCatalog
	for completed_index in 2:
		var entry := catalog.entries[completed_index] as LevelMenuEntry
		progress_store.begin_level(entry.level_definition.level_id)
		progress_store.record_active_medal(
			entry.level_definition.level_id,
			LevelDefinition.MedalTier.GOLD
			if completed_index == 0
			else LevelDefinition.MedalTier.BRONZE
		)
	progress_store.clear_active_level()
	get_tree().change_scene_to_file("res://scenes/ui/level_select.tscn")


func _run_test() -> void:
	var failures: Array[String] = []
	_remove_test_files()
	var progress_store := get_node("/root/ProgressStore")
	progress_store.load_progress(TEST_PROGRESS_PATH)

	var catalog := load("res://resources/levels/level_catalog.tres") as LevelCatalog
	if catalog == null:
		failures.append("The level catalog could not be loaded.")
		_finish_test(failures, progress_store)
		return
	var catalog_errors := catalog.get_configuration_errors()
	if not catalog_errors.is_empty():
		failures.append("The migrated catalog is invalid: %s" % "; ".join(catalog_errors))
	if catalog.entries.size() != 6:
		failures.append("The migrated catalog should contain six levels.")

	var menu_scene := load("res://scenes/ui/level_select.tscn") as PackedScene
	var menu := menu_scene.instantiate() as LevelSelect
	add_child(menu)
	await get_tree().process_frame
	if menu.level_buttons.size() != 6:
		failures.append("The progression menu did not build all six buttons.")
	else:
		if menu.level_buttons[0].disabled:
			failures.append("A fresh profile did not unlock Level 1.")
		for index in range(1, menu.level_buttons.size()):
			if not menu.level_buttons[index].disabled:
				failures.append("A fresh profile unlocked Level %d early." % (index + 1))
		if "Best: —" not in menu.level_buttons[0].text:
			failures.append("The fresh Level 1 button did not show an empty best medal.")

	var first_entry := catalog.entries[0] as LevelMenuEntry
	var second_entry := catalog.entries[1] as LevelMenuEntry
	await _emit_completed_level(first_entry.scene_path, LevelDefinition.MedalTier.BRONZE)
	if progress_store.get_best_medal(first_entry.level_definition.level_id) != LevelDefinition.MedalTier.NONE:
		failures.append("A direct scene completion wrote progress without an active catalog level.")

	progress_store.begin_level(first_entry.level_definition.level_id)
	await _emit_completed_level(first_entry.scene_path, LevelDefinition.MedalTier.BRONZE)
	if progress_store.get_best_medal(first_entry.level_definition.level_id) != LevelDefinition.MedalTier.BRONZE:
		failures.append("A matching gameplay completion did not store Bronze.")
	if menu.level_buttons.size() == 6:
		if menu.level_buttons[1].disabled:
			failures.append("Bronze on Level 1 did not unlock Level 2.")
		if not menu.level_buttons[2].disabled:
			failures.append("Bronze on Level 1 unlocked more than the next level.")
		if "Best: Bronze" not in menu.level_buttons[0].text:
			failures.append("The menu did not refresh the stored Bronze medal.")

	var reloaded_store := ProgressStoreScript.new()
	if reloaded_store.load_progress(TEST_PROGRESS_PATH) != OK:
		failures.append("The saved progress file could not be reloaded.")
	if reloaded_store.get_best_medal(first_entry.level_definition.level_id) != LevelDefinition.MedalTier.BRONZE:
		failures.append("Bronze did not survive a progress-store reload.")
	reloaded_store.free()

	progress_store.begin_level(first_entry.level_definition.level_id)
	if not progress_store.record_active_medal(
		first_entry.level_definition.level_id,
		LevelDefinition.MedalTier.GOLD
	):
		failures.append("A Gold improvement was not recorded.")
	if progress_store.record_active_medal(
		first_entry.level_definition.level_id,
		LevelDefinition.MedalTier.SILVER
	):
		failures.append("A lower replay result incorrectly replaced Gold.")
	if progress_store.get_best_medal(first_entry.level_definition.level_id) != LevelDefinition.MedalTier.GOLD:
		failures.append("The lower replay result downgraded the saved medal.")

	progress_store.begin_level(second_entry.level_definition.level_id)
	await _emit_failed_level(second_entry.scene_path)
	if progress_store.get_best_medal(second_entry.level_definition.level_id) != LevelDefinition.MedalTier.NONE:
		failures.append("A failed run wrote a best medal.")
	progress_store.begin_level(first_entry.level_definition.level_id)
	await _emit_completed_level(second_entry.scene_path, LevelDefinition.MedalTier.GOLD)
	if progress_store.get_best_medal(second_entry.level_definition.level_id) != LevelDefinition.MedalTier.NONE:
		failures.append("A mismatched active level wrote progress.")

	_test_invalid_files(failures, first_entry.level_definition.level_id)
	_finish_test(failures, progress_store)


func _emit_completed_level(scene_path: String, medal: int) -> void:
	var packed_scene := load(scene_path) as PackedScene
	var level := packed_scene.instantiate() as GameplayLevel
	add_child(level)
	await get_tree().process_frame
	level.level_controller.earned_medal = medal
	level.level_controller.level_completed.emit(
		level.level_definition.get_required_rescue_count(),
		level.level_definition.total_creatures
	)
	get_tree().paused = false
	remove_child(level)
	level.queue_free()
	await get_tree().process_frame


func _emit_failed_level(scene_path: String) -> void:
	var packed_scene := load(scene_path) as PackedScene
	var level := packed_scene.instantiate() as GameplayLevel
	add_child(level)
	await get_tree().process_frame
	level.level_controller.level_failed.emit(0, level.level_definition.get_required_rescue_count())
	get_tree().paused = false
	remove_child(level)
	level.queue_free()
	await get_tree().process_frame


func _test_invalid_files(failures: Array[String], level_id: StringName) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))
	var corrupt_file := FileAccess.open(CORRUPT_PROGRESS_PATH, FileAccess.WRITE)
	corrupt_file.store_string("this is not a ConfigFile")
	corrupt_file.close()
	var corrupt_store := ProgressStoreScript.new()
	if corrupt_store.load_progress(CORRUPT_PROGRESS_PATH) == OK:
		failures.append("Malformed progress data was accepted as valid.")
	if corrupt_store.get_best_medal(level_id) != LevelDefinition.MedalTier.NONE:
		failures.append("Malformed progress data did not produce a fresh profile.")
	corrupt_store.free()

	var invalid_medal_config := ConfigFile.new()
	invalid_medal_config.set_value("meta", "schema_version", 1)
	invalid_medal_config.set_value("medals", String(level_id), 99)
	invalid_medal_config.save(INVALID_MEDAL_PATH)
	var invalid_medal_store := ProgressStoreScript.new()
	if invalid_medal_store.load_progress(INVALID_MEDAL_PATH) != OK:
		failures.append("A valid save containing one invalid medal could not be loaded.")
	if invalid_medal_store.get_best_medal(level_id) != LevelDefinition.MedalTier.NONE:
		failures.append("An out-of-range saved medal was not ignored.")
	invalid_medal_store.free()

	var newer_config := ConfigFile.new()
	newer_config.set_value("meta", "schema_version", 2)
	newer_config.set_value("medals", String(level_id), LevelDefinition.MedalTier.GOLD)
	newer_config.save(NEWER_PROGRESS_PATH)
	var newer_store := ProgressStoreScript.new()
	if newer_store.load_progress(NEWER_PROGRESS_PATH) != ERR_UNAVAILABLE:
		failures.append("A newer save schema was not rejected.")
	if not newer_store.is_saving_blocked():
		failures.append("A newer save schema did not block overwrites.")
	newer_store.begin_level(level_id)
	if newer_store.record_active_medal(level_id, LevelDefinition.MedalTier.BRONZE):
		failures.append("A newer save schema was overwritten by a medal update.")
	var unchanged_config := ConfigFile.new()
	unchanged_config.load(NEWER_PROGRESS_PATH)
	if int(unchanged_config.get_value("meta", "schema_version", 0)) != 2:
		failures.append("The newer save schema changed on disk.")
	newer_store.free()


func _finish_test(failures: Array[String], progress_store: Node) -> void:
	progress_store.load_progress(progress_store.DEFAULT_STORAGE_PATH)
	_remove_test_files()
	if failures.is_empty():
		print(
			"MILESTONE_13_SMOKE_TEST: PASS - persistence, upgrades, active-level isolation, unlocking, and invalid saves verified."
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("MILESTONE_13_SMOKE_TEST: %s" % failure)
	get_tree().quit(1)


func _remove_test_files() -> void:
	for path in [
		TEST_PROGRESS_PATH,
		CORRUPT_PROGRESS_PATH,
		INVALID_MEDAL_PATH,
		NEWER_PROGRESS_PATH,
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _on_watchdog_timeout() -> void:
	push_error("MILESTONE_13_SMOKE_TEST: Timed out before completing.")
	get_tree().quit(2)
