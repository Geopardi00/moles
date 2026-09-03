extends Node

const ChunkedMaskTerrainScript = preload("res://scripts/terrain/chunked_mask_terrain.gd")
const CREATURE_SCENE := preload("res://scenes/creatures/creature.tscn")
const CREATURE_COUNT := 30
const EDIT_COUNT := 50


func _ready() -> void:
	var watchdog := Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.ignore_time_scale = true
	watchdog.one_shot = true
	watchdog.wait_time = 15.0
	watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(watchdog)
	watchdog.start()
	_run_test.call_deferred()


func _run_test() -> void:
	var failures: Array[String] = []
	var terrain := ChunkedMaskTerrainScript.new() as ChunkedMaskTerrainScript
	terrain.position = Vector2(100.0, 220.0)
	terrain.terrain_map = _create_stress_map()
	add_child(terrain)
	_add_boundary_wall(Vector2(
		terrain.global_position.x - 12.0,
		terrain.global_position.y + terrain.get_terrain_size().y * 0.5
	), terrain.get_terrain_size().y + 240.0)
	_add_boundary_wall(Vector2(
		terrain.global_position.x + terrain.get_terrain_size().x + 12.0,
		terrain.global_position.y + terrain.get_terrain_size().y * 0.5
	), terrain.get_terrain_size().y + 240.0)

	var creature_container := Node2D.new()
	creature_container.name = "Creatures"
	add_child(creature_container)
	for index in CREATURE_COUNT:
		var creature := CREATURE_SCENE.instantiate() as Creature
		creature.walk_speed = 120.0
		creature_container.add_child(creature)
		creature.global_position = Vector2(140.0 + float(index % 15) * 44.0, 250.0 - float(index / 15) * 8.0)
		creature.configure(1 if index % 2 == 0 else -1)

	for _frame in 45:
		await get_tree().physics_frame

	var removed_total := 0
	var added_total := 0
	var maximum_rebuild_usec := 0
	var total_edit_usec := 0
	var maximum_dirty_chunks := 0
	for edit_index in EDIT_COUNT:
		var edit_position := Vector2(
			56.0 + float((edit_index * 83) % 608),
			104.0 + float((edit_index % 3) * 14)
		)
		match edit_index % 4:
			0:
				removed_total += terrain.excavate_circle_with_operation(
					edit_position, 22.0, ChunkedMaskTerrainScript.TerrainOperation.DIG
				)
			1:
				removed_total += terrain.excavate_circle_with_operation(
					edit_position, 22.0, ChunkedMaskTerrainScript.TerrainOperation.MINE
				)
			2:
				removed_total += terrain.excavate_circle_with_operation(
					edit_position, 26.0, ChunkedMaskTerrainScript.TerrainOperation.BOMB, 2
				)
			3:
				added_total += terrain.fill_rectangle(
					Rect2(edit_position - Vector2(20.0, 8.0), Vector2(40.0, 16.0))
				)
		maximum_rebuild_usec = maxi(maximum_rebuild_usec, terrain.last_rebuild_usec)
		total_edit_usec += terrain.last_rebuild_usec
		maximum_dirty_chunks = maxi(maximum_dirty_chunks, terrain.last_rebuilt_chunks)
		await get_tree().physics_frame
		await get_tree().physics_frame

	for _frame in 120:
		await get_tree().physics_frame

	var walking_count := 0
	for child in creature_container.get_children():
		var creature := child as Creature
		if creature == null:
			failures.append("The creature container gained a non-creature child.")
			continue
		var position := creature.global_position
		if is_nan(position.x) or is_nan(position.y) or is_inf(position.x) or is_inf(position.y):
			failures.append("A creature acquired a non-finite position.")
		if position.y > terrain.global_position.y + terrain.get_terrain_size().y + 100.0:
			failures.append(
				"A creature escaped the terrain collision at %s in state %s."
				% [position, Creature.State.keys()[creature.current_state]]
			)
		if creature.current_state == Creature.State.WALKING:
			walking_count += 1

	if creature_container.get_child_count() != CREATURE_COUNT:
		failures.append("Expected %d live creatures after stress, got %d." % [
			CREATURE_COUNT,
			creature_container.get_child_count(),
		])
	if walking_count < 20:
		failures.append("Expected most creatures to recover to WALKING; only %d did." % walking_count)
	if removed_total <= 0:
		failures.append("The mixed stress pass did not excavate terrain.")
	if added_total <= 0:
		failures.append("The mixed stress pass did not create Constructed terrain.")
	if terrain.get_material_cell_count(2) <= 0:
		failures.append("The mixed stress pass unexpectedly removed every Rock cell.")
	if terrain.get_material_cell_count(3) != 180:
		failures.append("Bedrock changed during the mixed edit stress pass.")
	if terrain.get_collision_unit_count() <= 0:
		failures.append("Contour rebuilding removed every collision segment.")

	print(
		"TERRAIN_CREATURE_STRESS: %d creatures, %d mixed edits, %d removed/%d built, %d walking, avg %d us, max %d us/%d chunks."
		% [
			CREATURE_COUNT,
			EDIT_COUNT,
			removed_total,
			added_total,
			walking_count,
			total_edit_usec / EDIT_COUNT,
			maximum_rebuild_usec,
			maximum_dirty_chunks,
		]
	)
	terrain.queue_free()
	creature_container.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("TERRAIN_CREATURE_STRESS: PASS — moving creatures remained stable across multi-material contour rebuilds.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error("TERRAIN_CREATURE_STRESS: %s" % failure)
	get_tree().quit(1)


func _on_watchdog_timeout() -> void:
	push_error("TERRAIN_CREATURE_STRESS: Timed out before completing.")
	get_tree().quit(2)


func _add_boundary_wall(wall_position: Vector2, wall_height: float) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = wall_position
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24.0, wall_height)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _create_stress_map() -> TerrainMapDefinition:
	var size := Vector2i(90, 48)
	var palette := TerrainMaterialPalette.create_default()
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for x in size.x:
		var surface := clampi(12 + roundi(sin(float(x) * 0.14) * 3.0), 8, 16)
		for y in range(surface, size.y):
			image.set_pixel(x, y, Color8(113, 74, 43))
	for x in range(26, 39):
		for y in range(12, 20):
			image.set_pixel(x, y, Color8(83, 96, 106))
	for x in range(54, 67):
		for y in range(11, 19):
			image.set_pixel(x, y, Color8(83, 96, 106))
	for x in size.x:
		for y in range(size.y - 2, size.y):
			image.set_pixel(x, y, Color8(37, 42, 49))
	var map := TerrainMapDefinition.new()
	map.palette = palette
	map.material_map = ImageTexture.create_from_image(image)
	return map
