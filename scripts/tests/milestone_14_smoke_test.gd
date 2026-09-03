extends Node

const TERRAIN_MAP := preload("res://resources/terrain/terrain_lab_map.tres")
const PRODUCTION_PALETTE := preload("res://resources/terrain/production_terrain_palette.tres")
const DECAL_PATHS := [
	"res://art/Terrain/Runtime/Decals/root_branching.png",
	"res://art/Terrain/Runtime/Decals/root_curled.png",
	"res://art/Terrain/Runtime/Decals/stones_cluster.png",
	"res://art/Terrain/Runtime/Decals/stone_cracked.png",
	"res://art/Terrain/Runtime/Decals/cave_moss.png",
	"res://art/Terrain/Runtime/Decals/mineral_flecks.png",
	"res://art/Terrain/Runtime/Decals/soil_crumbs.png",
	"res://art/Terrain/Runtime/Decals/root_hanging.png",
]


func _ready() -> void:
	_run_test.call_deferred()


func _run_test() -> void:
	var failures: Array[String] = []
	_test_palette_contract(failures)
	_test_invalid_map_diagnostics(failures)
	_test_runtime_art_kit(failures)

	var terrain := ChunkedMaskTerrain.new()
	terrain.terrain_map = TERRAIN_MAP
	terrain.chunk_cells = 20
	add_child(terrain)
	await get_tree().process_frame
	var initial_data := terrain.get_material_data_copy()

	if terrain.grid_size != Vector2i(320, 110):
		failures.append("The authored map did not establish its 320x110-cell grid.")
	if terrain.get_visual_chunk_count() != terrain.get_chunk_count():
		failures.append("Every collision chunk must have one independent visual chunk.")
	for material_id in range(1, 5):
		if terrain.get_material_cell_count(material_id) <= 0:
			failures.append("The authored map is missing material ID %d." % material_id)
	if terrain.get_collision_unit_count() <= 0:
		failures.append("The imported caves, islands, and map edges produced no collision contours.")

	_test_operation_matrix(terrain, failures)
	terrain.reset_terrain()
	if terrain.get_material_data_copy() != initial_data:
		failures.append("Reset did not restore the cached authored material bytes exactly.")

	_test_dirty_chunks_and_signal(failures)
	terrain.queue_free()
	await get_tree().process_frame

	if failures.is_empty():
		print("MILESTONE_14_SMOKE_TEST: PASS — authored materials, rules, reset, signals, visuals, and chunk-local edits are valid.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("MILESTONE_14_SMOKE_TEST: %s" % failure)
	get_tree().quit(1)


func _test_palette_contract(failures: Array[String]) -> void:
	var errors := PRODUCTION_PALETTE.get_configuration_errors()
	if not errors.is_empty():
		failures.append("Production palette is invalid: %s" % "; ".join(errors))
	var seen_ids: Dictionary = {}
	for definition in PRODUCTION_PALETTE.materials:
		if definition.material_id == 0 or seen_ids.has(definition.material_id):
			failures.append("Production material IDs must be unique and nonzero.")
		seen_ids[definition.material_id] = true
		if definition.fill_texture == null:
			failures.append("Material %s has no runtime fill texture." % definition.display_name)
	if seen_ids.keys().size() != 4:
		failures.append("Production palette must define Dirt, Rock, Bedrock, and Constructed.")

	var duplicate_palette := TerrainMaterialPalette.new()
	var first := TerrainMaterialDefinition.new()
	first.material_id = 1
	first.source_color = Color8(1, 2, 3)
	var duplicate := TerrainMaterialDefinition.new()
	duplicate.material_id = 1
	duplicate.source_color = Color8(4, 5, 6)
	duplicate_palette.materials = [first, duplicate]
	if duplicate_palette.get_configuration_errors().is_empty():
		failures.append("Palette validation accepted a duplicated material ID.")


func _test_invalid_map_diagnostics(failures: Array[String]) -> void:
	var image := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color8(113, 74, 43))
	image.set_pixel(1, 0, Color.MAGENTA)
	var invalid_map := TerrainMapDefinition.new()
	invalid_map.palette = PRODUCTION_PALETTE
	invalid_map.material_map = ImageTexture.create_from_image(image)
	if invalid_map.get_configuration_errors().is_empty():
		failures.append("An authored map with an unknown source color passed validation.")


func _test_runtime_art_kit(failures: Array[String]) -> void:
	var rim := load("res://art/Terrain/Runtime/terrain_exposed_rim.png") as Texture2D
	if rim == null:
		failures.append("The runtime terrain kit is missing its exposed-earth rim texture.")
	if DECAL_PATHS.size() != 8:
		failures.append("The runtime terrain kit must provide exactly eight initial detail decals.")
	for path in DECAL_PATHS:
		var decal := load(path) as Texture2D
		if decal == null:
			failures.append("Could not load terrain detail decal %s." % path)
			continue
		var image := decal.get_image()
		if image == null or image.is_empty() or image.get_pixel(0, 0).a > 0.05:
			failures.append("Terrain detail decal %s does not preserve transparent padding." % path)


func _test_operation_matrix(terrain: ChunkedMaskTerrain, failures: Array[String]) -> void:
	var dirt_cell := _find_material_cell(terrain, 1)
	var rock_cell := _find_material_cell(terrain, 2)
	var bedrock_cell := _find_material_cell(terrain, 3)
	var constructed_cell := _find_material_cell(terrain, 4)

	if terrain.excavate_circle_with_operation(_cell_center(terrain, dirt_cell), 3.0, ChunkedMaskTerrain.TerrainOperation.DIG) != 1:
		failures.append("DIG did not remove one Dirt cell.")
	terrain.reset_terrain()
	if terrain.excavate_circle_with_operation(_cell_center(terrain, rock_cell), 3.0, ChunkedMaskTerrain.TerrainOperation.DIG) != 0:
		failures.append("DIG incorrectly removed Rock.")
	if terrain.excavate_circle_with_operation(_cell_center(terrain, rock_cell), 3.0, ChunkedMaskTerrain.TerrainOperation.BOMB, 1) != 0:
		failures.append("A weak BOMB incorrectly removed resistant Rock.")
	if terrain.excavate_circle_with_operation(_cell_center(terrain, rock_cell), 3.0, ChunkedMaskTerrain.TerrainOperation.MINE) != 1:
		failures.append("MINE did not remove Rock.")
	terrain.reset_terrain()
	if terrain.excavate_circle_with_operation(_cell_center(terrain, rock_cell), 3.0, ChunkedMaskTerrain.TerrainOperation.BOMB, 2) != 1:
		failures.append("A strength-2 BOMB did not remove Rock.")
	for operation in [ChunkedMaskTerrain.TerrainOperation.DIG, ChunkedMaskTerrain.TerrainOperation.MINE, ChunkedMaskTerrain.TerrainOperation.BOMB]:
		if terrain.excavate_circle_with_operation(_cell_center(terrain, bedrock_cell), 3.0, operation, 255) != 0:
			failures.append("Bedrock was removed by operation %s." % ChunkedMaskTerrain.TerrainOperation.keys()[operation])
	terrain.reset_terrain()
	if terrain.excavate_circle_with_operation(_cell_center(terrain, constructed_cell), 3.0, ChunkedMaskTerrain.TerrainOperation.DIG) != 1:
		failures.append("DIG did not remove Constructed terrain.")

	var empty_cell := _find_material_cell(terrain, 0)
	var rect := Rect2(Vector2(empty_cell * terrain.cell_size), Vector2.ONE * terrain.cell_size)
	if terrain.fill_rectangle(rect) != 1 or terrain.get_material_cell(empty_cell) != 4:
		failures.append("BUILD did not write Constructed material into an Empty cell.")
	if terrain.fill_rectangle(rect) != 0:
		failures.append("BUILD overwrote a non-empty terrain cell.")


func _test_dirty_chunks_and_signal(failures: Array[String]) -> void:
	var terrain := ChunkedMaskTerrain.new()
	terrain.grid_size = Vector2i(40, 20)
	terrain.chunk_cells = 20
	terrain.initial_shape = ChunkedMaskTerrain.InitialShape.SOLID_RECTANGLE
	add_child(terrain)
	var changed_bounds: Array[Rect2i] = []
	terrain.terrain_region_changed.connect(func(bounds: Rect2i) -> void: changed_bounds.append(bounds))
	var removed := terrain.excavate_circle(Vector2(20.0 * terrain.cell_size, 10.5 * terrain.cell_size), 9.0)
	if removed <= 0:
		failures.append("The cross-boundary edit removed no terrain.")
	if terrain.last_rebuilt_chunks != 2:
		failures.append("A cross-boundary edit should rebuild exactly two collision chunks, got %d." % terrain.last_rebuilt_chunks)
	if changed_bounds.size() != 1 or changed_bounds[0].size.x < 2:
		failures.append("A successful edit did not emit one accurate dirty-cell region.")
	if terrain.get_visual_chunk_count() != terrain.get_chunk_count():
		failures.append("Seam refresh changed the one-visual-per-chunk invariant.")
	terrain.queue_free()


func _find_material_cell(terrain: ChunkedMaskTerrain, material_id: int) -> Vector2i:
	for y in terrain.grid_size.y:
		for x in terrain.grid_size.x:
			if terrain.get_material_cell(Vector2i(x, y)) == material_id:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _cell_center(terrain: ChunkedMaskTerrain, cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * float(terrain.cell_size)
