extends Node

const FineCellTerrainScript = preload("res://scripts/terrain/fine_cell_terrain.gd")
const ChunkedMaskTerrainScript = preload("res://scripts/terrain/chunked_mask_terrain.gd")
const TerrainPrototypeScript = preload("res://scripts/terrain/terrain_prototype.gd")


func _ready() -> void:
	_run_test.call_deferred()


func _run_test() -> void:
	var failures: Array[String] = []
	var packed_scene := load("res://scenes/tests/terrain_prototype.tscn") as PackedScene
	if packed_scene == null:
		push_error("MILESTONE_3_SMOKE_TEST: Could not load the terrain prototype.")
		get_tree().quit(1)
		return

	var lab := packed_scene.instantiate() as TerrainPrototypeScript
	add_child(lab)
	await get_tree().process_frame
	await get_tree().physics_frame

	var fine := lab.fine_cell_terrain as FineCellTerrainScript
	var mask := lab.chunked_mask_terrain as ChunkedMaskTerrainScript
	var fine_initial := fine.get_solid_cell_count()
	var mask_initial := mask.get_solid_cell_count()
	var fine_initial_collision := fine.get_collision_unit_count()
	var mask_initial_collision := mask.get_collision_unit_count()
	var fine_center := Vector2(fine.get_terrain_size().x * 0.5, 130.0)
	var mask_center := Vector2(mask.get_terrain_size().x * 0.5, 130.0)
	var fine_surface_before := _get_first_collision_y(
		fine.to_global(Vector2(fine_center.x, 0.0)),
		fine.to_global(Vector2(fine_center.x, 300.0))
	)
	var mask_surface_before := _get_first_collision_y(
		mask.to_global(Vector2(mask_center.x, 0.0)),
		mask.to_global(Vector2(mask_center.x, 300.0))
	)

	if fine.get_material_at(fine_center) != 1 or mask.get_material_at(mask_center) != 1:
		failures.append("Both samples should report dirt at the excavation centers before digging.")
	var fine_removed := lab.dig_at_world_position(fine.to_global(fine_center))
	var mask_removed := lab.dig_at_world_position(mask.to_global(mask_center))
	await get_tree().physics_frame
	await get_tree().physics_frame

	if fine_removed <= 0 or mask_removed <= 0:
		failures.append("Both terrain backends must remove occupied cells.")
	if fine.get_solid_cell_count() != fine_initial - fine_removed:
		failures.append("TileMapLayer solid-cell accounting did not match excavation.")
	if mask.get_solid_cell_count() != mask_initial - mask_removed:
		failures.append("Mask solid-cell accounting did not match excavation.")
	if fine.get_material_at(fine_center) != 0 or mask.get_material_at(mask_center) != 0:
		failures.append("Excavated centers should report empty material.")
	if mask.last_rebuilt_chunks <= 0 or mask.last_rebuilt_chunks >= mask.get_chunk_count():
		failures.append("Mask excavation should rebuild only a subset of chunks.")
	if mask_initial_collision >= fine_initial_collision:
		failures.append("Merged mask collision should use fewer units than per-cell TileMap collision.")
	var fine_surface_after := _get_first_collision_y(
		fine.to_global(Vector2(fine_center.x, 0.0)),
		fine.to_global(Vector2(fine_center.x, 300.0))
	)
	var mask_surface_after := _get_first_collision_y(
		mask.to_global(Vector2(mask_center.x, 0.0)),
		mask.to_global(Vector2(mask_center.x, 300.0))
	)
	if fine_surface_after <= fine_surface_before + fine.cell_size:
		failures.append("TileMapLayer excavation did not lower the collision surface.")
	if mask_surface_after <= mask_surface_before + mask.cell_size:
		failures.append("Chunked-mask excavation did not lower the contour surface.")
	if is_inf(_get_first_collision_y(
		fine.to_global(Vector2(fine_center.x + 180.0, 0.0)),
		fine.to_global(Vector2(fine_center.x + 180.0, 300.0))
	)):
		failures.append("TileMapLayer collision disappeared outside the dig.")
	if is_inf(_get_first_collision_y(
		mask.to_global(Vector2(mask_center.x + 180.0, 0.0)),
		mask.to_global(Vector2(mask_center.x + 180.0, 300.0))
	)):
		failures.append("Chunked-mask contour disappeared outside the dig.")

	lab.reset_samples()
	if fine.get_solid_cell_count() != fine_initial or mask.get_solid_cell_count() != mask_initial:
		failures.append("Reset did not restore both samples.")
	_run_benchmark(fine, mask)

	lab.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("MILESTONE_3_SMOKE_TEST: PASS — both backends excavated, updated material data/collision, and reset.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error("MILESTONE_3_SMOKE_TEST: %s" % failure)
	get_tree().quit(1)


func _get_first_collision_y(from: Vector2, to: Vector2) -> float:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := get_viewport().world_2d.direct_space_state.intersect_ray(query)
	return float(result["position"].y) if not result.is_empty() else INF


func _run_benchmark(fine: FineCellTerrainScript, mask: ChunkedMaskTerrainScript) -> void:
	var centers: Array[Vector2] = []
	for row in 2:
		for column in 8:
			centers.append(Vector2(80.0 + column * 80.0, 170.0 + row * 90.0))

	var fine_total_usec := 0
	var fine_removed := 0
	for center in centers:
		fine_removed += fine.excavate_circle(center, 42.0)
		fine_total_usec += fine.last_rebuild_usec
	fine.reset_terrain()

	var mask_total_usec := 0
	var mask_removed := 0
	var mask_rebuilt_chunks := 0
	for center in centers:
		mask_removed += mask.excavate_circle(center, 42.0)
		mask_total_usec += mask.last_rebuild_usec
		mask_rebuilt_chunks += mask.last_rebuilt_chunks
	mask.reset_terrain()

	print(
		"MILESTONE_3_BENCHMARK: 16 digs — TileMap %d µs/%d cells; mask %d µs/%d cells/%d chunk rebuilds."
		% [fine_total_usec, fine_removed, mask_total_usec, mask_removed, mask_rebuilt_chunks]
	)
