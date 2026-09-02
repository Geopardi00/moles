extends Node

const TEST_TIMEOUT_SECONDS := 8.0
const LEVEL_CASES := [
	{
		"path": "res://resources/levels/movement_test_level.tres",
		"thresholds": Vector3i(24, 27, 30),
	},
	{
		"path": "res://resources/levels/dig_puzzle_level.tres",
		"thresholds": Vector3i(8, 9, 10),
	},
	{
		"path": "res://resources/levels/build_puzzle_level.tres",
		"thresholds": Vector3i(5, 5, 5),
	},
	{
		"path": "res://resources/levels/dig_build_puzzle_level.tres",
		"thresholds": Vector3i(5, 5, 5),
	},
	{
		"path": "res://resources/levels/block_puzzle_level.tres",
		"thresholds": Vector3i(4, 4, 4),
	},
	{
		"path": "res://resources/levels/bomb_puzzle_level.tres",
		"thresholds": Vector3i(4, 4, 4),
	},
	{
		"path": "res://resources/levels/mine_puzzle_level.tres",
		"thresholds": Vector3i(6, 6, 6),
	},
]


func _ready() -> void:
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.ignore_time_scale = true
	watchdog.one_shot = true
	watchdog.wait_time = TEST_TIMEOUT_SECONDS
	watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(watchdog)
	watchdog.start()
	_run_test.call_deferred()


func _run_test() -> void:
	var failures: Array[String] = []
	_test_definition_rules(failures)
	_test_migrated_resources(failures)
	_test_controller_outcomes(failures)
	await _test_hud_presentation(failures)

	if failures.is_empty():
		print(
			"MILESTONE_12_SMOKE_TEST: PASS - medal thresholds, outcomes, HUD, migration, and reset verified."
		)
		get_tree().quit(0)
		return

	for failure in failures:
		push_error("MILESTONE_12_SMOKE_TEST: %s" % failure)
	get_tree().quit(1)


func _test_definition_rules(failures: Array[String]) -> void:
	var definition := _make_definition(5, 3, 4, 5)
	if not definition.has_valid_medal_thresholds():
		failures.append("A correctly ordered medal configuration was rejected.")
	if definition.get_required_rescue_count() != 3:
		failures.append("Bronze should be the authoritative success requirement.")
	if definition.get_medal_for_saved_count(2) != LevelDefinition.MedalTier.NONE:
		failures.append("A result below Bronze should earn no medal.")
	if definition.get_medal_for_saved_count(3) != LevelDefinition.MedalTier.BRONZE:
		failures.append("The Bronze threshold did not award Bronze.")
	if definition.get_medal_for_saved_count(4) != LevelDefinition.MedalTier.SILVER:
		failures.append("The Silver threshold did not award Silver.")
	if definition.get_medal_for_saved_count(5) != LevelDefinition.MedalTier.GOLD:
		failures.append("The Gold threshold did not award Gold.")

	var invalid_order := _make_definition(5, 4, 3, 5)
	if invalid_order.has_valid_medal_thresholds():
		failures.append("A Silver threshold below Bronze passed validation.")
	var invalid_total := _make_definition(5, 3, 4, 6)
	if invalid_total.has_valid_medal_thresholds():
		failures.append("A Gold threshold above the population passed validation.")


func _test_migrated_resources(failures: Array[String]) -> void:
	for level_case in LEVEL_CASES:
		var path: String = level_case["path"]
		var expected: Vector3i = level_case["thresholds"]
		var definition := load(path) as LevelDefinition
		if definition == null:
			failures.append("Could not load migrated level definition: %s" % path)
			continue
		var actual := Vector3i(
			definition.bronze_rescue_count,
			definition.silver_rescue_count,
			definition.gold_rescue_count
		)
		if actual != expected:
			failures.append(
				"Unexpected medal thresholds for %s: expected %s, got %s."
				% [path, expected, actual]
			)
		if not definition.has_valid_medal_thresholds():
			failures.append("Migrated level has invalid medal thresholds: %s" % path)


func _test_controller_outcomes(failures: Array[String]) -> void:
	var definition := _make_definition(5, 3, 4, 5)
	var controller := LevelController.new()
	add_child(controller)
	controller.begin_level(definition)
	controller.register_spawning_finished(5)
	for _saved in 3:
		controller.register_saved()
	controller.register_lost()
	if controller.status != LevelController.Status.RUNNING:
		failures.append("The controller completed before every creature resolved.")
	controller.register_lost()
	if controller.status != LevelController.Status.COMPLETED:
		failures.append("Reaching Bronze after every creature resolved did not complete the level.")
	if controller.earned_medal != LevelDefinition.MedalTier.BRONZE:
		failures.append("The controller did not retain the final Bronze result.")
	controller.register_saved()
	if controller.saved_count != 3:
		failures.append("A completed outcome accepted additional progress.")

	controller.begin_level(definition)
	if (
		controller.status != LevelController.Status.RUNNING
		or controller.earned_medal != LevelDefinition.MedalTier.NONE
	):
		failures.append("Beginning a fresh run did not reset the outcome and medal.")
	for _loss in 3:
		controller.register_lost()
	if controller.status != LevelController.Status.FAILED:
		failures.append("The Bronze requirement did not drive early failure.")
	if controller.earned_medal != LevelDefinition.MedalTier.NONE:
		failures.append("An early failure retained a medal.")

	var sacrifice_definition := _make_definition(5, 4, 4, 4)
	controller.begin_level(sacrifice_definition)
	controller.register_spawning_finished(5)
	for _saved in 4:
		controller.register_saved()
	controller.register_lost()
	if controller.earned_medal != LevelDefinition.MedalTier.GOLD:
		failures.append("A valid Gold threshold below the total did not award Gold.")
	controller.queue_free()


func _test_hud_presentation(failures: Array[String]) -> void:
	var harness := Node.new()
	harness.name = "HudHarness"
	add_child(harness)

	var simulation_controller := SimulationController.new()
	simulation_controller.name = "SimulationController"
	harness.add_child(simulation_controller)

	var hud_scene := load("res://scenes/ui/simulation_hud.tscn") as PackedScene
	if hud_scene == null:
		failures.append("Could not load the gameplay HUD scene.")
		harness.queue_free()
		return
	var hud := hud_scene.instantiate() as SimulationHUD
	hud.simulation_controller_path = NodePath("../SimulationController")
	harness.add_child(hud)

	var controller := LevelController.new()
	controller.name = "LevelController"
	harness.add_child(controller)
	var definition := _make_definition(5, 3, 4, 5)
	definition.display_name = "Medal Test"
	controller.begin_level(definition)
	hud.bind_level(controller)
	await get_tree().process_frame

	if hud.goal_label.text != "Medals: Bronze 3 | Silver 4 | Gold 5":
		failures.append("The HUD did not present all three authored thresholds.")
	controller.register_spawning_finished(5)
	for _saved in 5:
		controller.register_saved()
	if not hud.result_overlay.visible:
		failures.append("The medal result overlay did not become visible.")
	if hud.result_medal.text != "GOLD MEDAL":
		failures.append("The completed HUD did not present the earned Gold medal.")

	controller.begin_level(definition)
	for _loss in 3:
		controller.register_lost()
	if hud.result_medal.text != "NO MEDAL":
		failures.append("The failed HUD did not present a no-medal result.")
	if "Bronze requires 3" not in hud.result_details.text:
		failures.append("The failed HUD did not explain the Bronze requirement.")

	harness.queue_free()
	await get_tree().process_frame


func _make_definition(
	total: int,
	bronze: int,
	silver: int,
	gold: int
) -> LevelDefinition:
	var definition := LevelDefinition.new()
	definition.total_creatures = total
	definition.bronze_rescue_count = bronze
	definition.silver_rescue_count = silver
	definition.gold_rescue_count = gold
	return definition


func _on_watchdog_timeout() -> void:
	push_error("MILESTONE_12_SMOKE_TEST: Timed out before completing.")
	get_tree().quit(2)
