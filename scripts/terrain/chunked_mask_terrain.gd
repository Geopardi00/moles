class_name ChunkedMaskTerrain
extends Node2D

## Fine multi-material field with independent chunk visuals and boundary collision.

signal terrain_region_changed(cell_bounds: Rect2i)

enum InitialShape {
	WAVY_GROUND,
	SOLID_RECTANGLE,
	EMPTY,
}

enum TerrainOperation {
	DIG,
	MINE,
	BOMB,
}

const TERRAIN_SHADER := preload("res://shaders/terrain_material.gdshader")
const DEFAULT_CONSTRUCTED_MATERIAL_ID := 4

@export_category("Terrain Source")
@export var grid_size: Vector2i = Vector2i(90, 48)
@export_range(2, 32, 1) var cell_size: int = 8
@export_range(4, 64, 1) var chunk_cells: int = 15
@export var initial_shape: InitialShape = InitialShape.WAVY_GROUND
@export var terrain_map: TerrainMapDefinition
@export var palette: TerrainMaterialPalette

@export_category("Material Defaults")
@export var terrain_color: Color = Color(0.4, 0.27, 0.15, 1.0)
@export_range(1, 255, 1) var material_id: int = 1
@export_range(1, 255, 1) var constructed_material_id: int = DEFAULT_CONSTRUCTED_MATERIAL_ID
@export var top_surface_collision_only: bool = false

@export_category("Visual Tuning")
@export_range(64.0, 2048.0, 1.0) var texture_world_size: float = 512.0
@export var exposed_rim_color: Color = Color(0.19, 0.12, 0.07, 1.0)
@export var exposed_rim_texture: Texture2D

@export_category("Debug")
@export var show_material_debug: bool = false
@export var show_chunk_debug: bool = false
@export var show_collision_debug: bool = false
@export var show_dirty_chunk_debug: bool = false

var last_removed_cells: int = 0
var last_added_cells: int = 0
var last_rebuild_usec: int = 0
var total_rebuild_usec: int = 0
var last_rebuilt_chunks: int = 0

var _materials := PackedByteArray()
var _initial_materials := PackedByteArray()
var _chunk_bodies: Dictionary = {}
var _chunk_visuals: Dictionary = {}
var _fallback_textures: Dictionary = {}
var _last_dirty_chunks: Dictionary = {}


func _ready() -> void:
	reset_terrain()


func reset_terrain() -> void:
	var started_usec := Time.get_ticks_usec()
	if terrain_map != null and terrain_map.palette != null:
		palette = terrain_map.palette
	if palette == null:
		palette = TerrainMaterialPalette.create_default(terrain_color)
	var palette_errors := palette.get_configuration_errors()
	if not palette_errors.is_empty():
		push_error("ChunkedMaskTerrain received an invalid palette: %s" % "; ".join(palette_errors))
		return
	palette.rebuild_lookup()

	if not _initial_materials.is_empty():
		_materials = _initial_materials.duplicate()
	elif terrain_map != null:
		var map_errors := terrain_map.get_configuration_errors()
		if not map_errors.is_empty():
			push_error("ChunkedMaskTerrain received an invalid terrain map: %s" % "; ".join(map_errors))
			return
		grid_size = terrain_map.get_grid_size()
		_materials = terrain_map.create_material_data()
	else:
		_build_procedural_material_data()
	if _initial_materials.is_empty():
		_initial_materials = _materials.duplicate()

	_clear_runtime_chunks()
	_rebuild_all_chunks()
	_last_dirty_chunks.clear()
	queue_redraw()
	last_removed_cells = 0
	last_added_cells = 0
	last_rebuilt_chunks = _chunk_bodies.size()
	last_rebuild_usec = Time.get_ticks_usec() - started_usec
	total_rebuild_usec = last_rebuild_usec


func excavate_circle(local_center: Vector2, radius: float) -> int:
	return excavate_circle_with_operation(local_center, radius, TerrainOperation.DIG)


func excavate_circle_with_operation(
	local_center: Vector2,
	radius: float,
	operation: TerrainOperation,
	strength: int = 1
) -> int:
	var started_usec := Time.get_ticks_usec()
	var minimum := Vector2i(
		floori((local_center.x - radius) / cell_size),
		floori((local_center.y - radius) / cell_size)
	)
	var maximum := Vector2i(
		floori((local_center.x + radius) / cell_size),
		floori((local_center.y + radius) / cell_size)
	)
	var radius_squared := radius * radius
	var affected_chunks: Dictionary = {}
	var dirty_min := grid_size
	var dirty_max := Vector2i(-1, -1)
	var removed := 0
	for x in range(maxi(minimum.x, 0), mini(maximum.x + 1, grid_size.x)):
		for y in range(maxi(minimum.y, 0), mini(maximum.y + 1, grid_size.y)):
			var cell := Vector2i(x, y)
			var cell_center := (Vector2(cell) + Vector2(0.5, 0.5)) * float(cell_size)
			if cell_center.distance_squared_to(local_center) > radius_squared:
				continue
			var current_material_id := get_material_cell(cell)
			var definition := palette.get_material(current_material_id)
			if definition == null or not definition.can_remove(operation, strength):
				continue
			_set_material_cell(cell, 0)
			affected_chunks[_cell_to_chunk(cell)] = true
			dirty_min = dirty_min.min(cell)
			dirty_max = dirty_max.max(cell)
			removed += 1
	_rebuild_affected_chunks(affected_chunks)
	if removed > 0:
		terrain_region_changed.emit(Rect2i(dirty_min, dirty_max - dirty_min + Vector2i.ONE))
	last_removed_cells = removed
	last_added_cells = 0
	last_rebuilt_chunks = affected_chunks.size()
	last_rebuild_usec = Time.get_ticks_usec() - started_usec
	total_rebuild_usec += last_rebuild_usec
	return removed


func fill_rectangle(local_rect: Rect2, fill_material_id: int = -1) -> int:
	var started_usec := Time.get_ticks_usec()
	var target_material_id := (
		constructed_material_id if fill_material_id < 0 else fill_material_id
	)
	if palette == null or palette.get_material(target_material_id) == null:
		push_warning("ChunkedMaskTerrain cannot fill with unknown material ID %d." % target_material_id)
		return 0
	var minimum := Vector2i(
		floori(local_rect.position.x / cell_size),
		floori(local_rect.position.y / cell_size)
	)
	var maximum := Vector2i(
		ceili(local_rect.end.x / cell_size),
		ceili(local_rect.end.y / cell_size)
	)
	var affected_chunks: Dictionary = {}
	var dirty_min := grid_size
	var dirty_max := Vector2i(-1, -1)
	var added := 0
	for x in range(maxi(minimum.x, 0), mini(maximum.x, grid_size.x)):
		for y in range(maxi(minimum.y, 0), mini(maximum.y, grid_size.y)):
			var cell := Vector2i(x, y)
			if get_material_cell(cell) != 0:
				continue
			_set_material_cell(cell, target_material_id)
			affected_chunks[_cell_to_chunk(cell)] = true
			dirty_min = dirty_min.min(cell)
			dirty_max = dirty_max.max(cell)
			added += 1
	_rebuild_affected_chunks(affected_chunks)
	if added > 0:
		terrain_region_changed.emit(Rect2i(dirty_min, dirty_max - dirty_min + Vector2i.ONE))
	last_added_cells = added
	last_removed_cells = 0
	last_rebuilt_chunks = affected_chunks.size()
	last_rebuild_usec = Time.get_ticks_usec() - started_usec
	total_rebuild_usec += last_rebuild_usec
	return added


func can_apply_operation_at(
	local_position: Vector2,
	operation: TerrainOperation,
	strength: int = 1
) -> bool:
	if palette == null:
		return false
	var definition := palette.get_material(get_material_at(local_position))
	return definition != null and definition.can_remove(operation, strength)


func get_material_at(local_position: Vector2) -> int:
	var cell := Vector2i(
		floori(local_position.x / cell_size),
		floori(local_position.y / cell_size)
	)
	return get_material_cell(cell)


func get_material_cell(cell: Vector2i) -> int:
	if not _is_in_bounds(cell) or _materials.is_empty():
		return 0
	return int(_materials[cell.y * grid_size.x + cell.x])


func get_material_data_copy() -> PackedByteArray:
	return _materials.duplicate()


func get_material_cell_count(target_material_id: int) -> int:
	var count := 0
	for current_material_id in _materials:
		if int(current_material_id) == target_material_id:
			count += 1
	return count


func get_solid_cell_count() -> int:
	var count := 0
	for current_material_id in _materials:
		if current_material_id != 0:
			count += 1
	return count


func get_collision_unit_count() -> int:
	var count := 0
	for body: StaticBody2D in _chunk_bodies.values():
		count += body.get_child_count()
	return count


func get_chunk_count() -> int:
	return _chunk_bodies.size()


func get_visual_chunk_count() -> int:
	return _chunk_visuals.size()


func get_terrain_size() -> Vector2:
	return Vector2(grid_size * cell_size)


func set_debug_display(
	material_debug: bool,
	chunk_debug: bool,
	collision_debug: bool,
	dirty_chunk_debug: bool
) -> void:
	show_material_debug = material_debug
	show_chunk_debug = chunk_debug
	show_collision_debug = collision_debug
	show_dirty_chunk_debug = dirty_chunk_debug
	queue_redraw()


func _build_procedural_material_data() -> void:
	_materials.resize(grid_size.x * grid_size.y)
	_materials.fill(0)
	var initial_id := material_id if palette.get_material(material_id) != null else 1
	for x in grid_size.x:
		var surface_y := (
			grid_size.y
			if initial_shape == InitialShape.EMPTY
			else 0 if initial_shape == InitialShape.SOLID_RECTANGLE else _get_surface_cell_y(x)
		)
		for y in range(surface_y, grid_size.y):
			_set_material_cell(Vector2i(x, y), initial_id)


func _get_surface_cell_y(x: int) -> int:
	var wave := sin(float(x) * 0.14) * 3.2 + sin(float(x) * 0.045) * 2.4
	return clampi(12 + roundi(wave), 6, grid_size.y - 4)


func _is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func _is_solid(cell: Vector2i) -> bool:
	return get_material_cell(cell) != 0


func _set_material_cell(cell: Vector2i, value: int) -> void:
	_materials[cell.y * grid_size.x + cell.x] = value


func _cell_to_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x / chunk_cells, cell.y / chunk_cells)


func _clear_runtime_chunks() -> void:
	for body: StaticBody2D in _chunk_bodies.values():
		body.free()
	for visual: Sprite2D in _chunk_visuals.values():
		visual.free()
	_chunk_bodies.clear()
	_chunk_visuals.clear()
	_fallback_textures.clear()


func _rebuild_all_chunks() -> void:
	var chunk_count := Vector2i(
		ceili(float(grid_size.x) / chunk_cells),
		ceili(float(grid_size.y) / chunk_cells)
	)
	for chunk_x in chunk_count.x:
		for chunk_y in chunk_count.y:
			_rebuild_chunk(Vector2i(chunk_x, chunk_y))


func _rebuild_affected_chunks(affected_chunks: Dictionary) -> void:
	var visual_chunks := affected_chunks.duplicate()
	var maximum_chunk := Vector2i(
		ceili(float(grid_size.x) / chunk_cells),
		ceili(float(grid_size.y) / chunk_cells)
	)
	for chunk: Vector2i in affected_chunks:
		for offset_y in range(-1, 2):
			for offset_x in range(-1, 2):
				var neighbor := chunk + Vector2i(offset_x, offset_y)
				if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < maximum_chunk.x and neighbor.y < maximum_chunk.y:
					visual_chunks[neighbor] = true
	_last_dirty_chunks = visual_chunks.duplicate()
	for chunk: Vector2i in affected_chunks:
		_rebuild_chunk(chunk)
	for chunk: Vector2i in visual_chunks:
		if affected_chunks.has(chunk):
			continue
		var start_x := chunk.x * chunk_cells
		var start_y := chunk.y * chunk_cells
		_update_visual_chunk(
			chunk,
			start_x,
			start_y,
			mini(start_x + chunk_cells, grid_size.x),
			mini(start_y + chunk_cells, grid_size.y)
		)
	if not affected_chunks.is_empty():
		queue_redraw()


func _rebuild_chunk(chunk: Vector2i) -> void:
	var body := _get_or_create_chunk_body(chunk)
	for child in body.get_children():
		child.free()

	var start_x := chunk.x * chunk_cells
	var start_y := chunk.y * chunk_cells
	var end_x := mini(start_x + chunk_cells, grid_size.x)
	var end_y := mini(start_y + chunk_cells, grid_size.y)
	var horizontal_edges: Dictionary = {}
	var vertical_edges: Dictionary = {}
	for y in range(start_y, end_y):
		for x in range(start_x, end_x):
			var cell := Vector2i(x, y)
			if not _is_solid(cell):
				continue
			if not _is_solid(cell + Vector2i.UP):
				_append_unit_edge(horizontal_edges, y, x)
			if not top_surface_collision_only and not _is_solid(cell + Vector2i.DOWN):
				_append_unit_edge(horizontal_edges, y + 1, x)
			if not top_surface_collision_only and not _is_solid(cell + Vector2i.LEFT):
				_append_unit_edge(vertical_edges, x, y)
			if not top_surface_collision_only and not _is_solid(cell + Vector2i.RIGHT):
				_append_unit_edge(vertical_edges, x + 1, y)
	_add_merged_contour_segments(body, horizontal_edges, true)
	_add_merged_contour_segments(body, vertical_edges, false)
	_update_visual_chunk(chunk, start_x, start_y, end_x, end_y)


func _get_or_create_chunk_body(chunk: Vector2i) -> StaticBody2D:
	if _chunk_bodies.has(chunk):
		return _chunk_bodies[chunk] as StaticBody2D
	var body := StaticBody2D.new()
	body.name = "ChunkCollision_%d_%d" % [chunk.x, chunk.y]
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	_chunk_bodies[chunk] = body
	return body


func _append_unit_edge(edges: Dictionary, line: int, start: int) -> void:
	if not edges.has(line):
		edges[line] = []
	var starts: Array = edges[line]
	starts.append(start)


func _add_merged_contour_segments(body: StaticBody2D, edges: Dictionary, horizontal: bool) -> void:
	for line: int in edges:
		var starts: Array = edges[line]
		starts.sort()
		if starts.is_empty():
			continue
		var run_start := int(starts[0])
		var previous := run_start
		for index in range(1, starts.size()):
			var current := int(starts[index])
			if current != previous + 1:
				_add_contour_segment(body, line, run_start, previous + 1, horizontal)
				run_start = current
			previous = current
		_add_contour_segment(body, line, run_start, previous + 1, horizontal)


func _add_contour_segment(
	body: StaticBody2D,
	line: int,
	start: int,
	end: int,
	horizontal: bool
) -> void:
	var shape := SegmentShape2D.new()
	if horizontal:
		shape.a = Vector2(start * cell_size, line * cell_size)
		shape.b = Vector2(end * cell_size, line * cell_size)
	else:
		shape.a = Vector2(line * cell_size, start * cell_size)
		shape.b = Vector2(line * cell_size, end * cell_size)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)


func _update_visual_chunk(
	chunk: Vector2i,
	start_x: int,
	start_y: int,
	end_x: int,
	end_y: int
) -> void:
	var width := end_x - start_x
	var height := end_y - start_y
	var padded_size := Vector2i(width + 2, height + 2)
	var image := Image.create(padded_size.x, padded_size.y, false, Image.FORMAT_RGBA8)
	for local_y in padded_size.y:
		for local_x in padded_size.x:
			var current_material_id := get_material_cell(
				Vector2i(start_x + local_x - 1, start_y + local_y - 1)
			)
			image.set_pixel(
				local_x,
				local_y,
				Color(float(current_material_id) / 255.0, 0.0, 0.0, 1.0 if current_material_id > 0 else 0.0)
			)
	var visual := _get_or_create_chunk_visual(chunk)
	var texture := visual.texture as ImageTexture
	if texture == null or texture.get_width() != padded_size.x or texture.get_height() != padded_size.y:
		texture = ImageTexture.create_from_image(image)
		visual.texture = texture
	else:
		texture.update(image)
	var visual_material := visual.material as ShaderMaterial
	visual_material.set_shader_parameter("material_map_texture", texture)
	visual.position = Vector2(start_x, start_y) * float(cell_size)
	visual.scale = Vector2.ONE * float(cell_size)
	visual.region_rect = Rect2(1.0, 1.0, width, height)
	visual_material.set_shader_parameter(
		"chunk_world_origin",
		Vector2(start_x, start_y) * float(cell_size)
	)
	visual_material.set_shader_parameter(
		"chunk_world_size",
		Vector2(width, height) * float(cell_size)
	)
	visual_material.set_shader_parameter(
		"material_uv_origin",
		Vector2.ONE / Vector2(padded_size)
	)
	visual_material.set_shader_parameter(
		"material_uv_size",
		Vector2(width, height) / Vector2(padded_size)
	)


func _get_or_create_chunk_visual(chunk: Vector2i) -> Sprite2D:
	if _chunk_visuals.has(chunk):
		return _chunk_visuals[chunk] as Sprite2D
	var visual := Sprite2D.new()
	visual.name = "ChunkVisual_%d_%d" % [chunk.x, chunk.y]
	visual.centered = false
	visual.region_enabled = true
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visual.z_index = -1
	var visual_material := ShaderMaterial.new()
	visual_material.shader = TERRAIN_SHADER
	_configure_visual_material(visual_material)
	visual.material = visual_material
	add_child(visual)
	_chunk_visuals[chunk] = visual
	return visual


func _configure_visual_material(visual_material: ShaderMaterial) -> void:
	visual_material.set_shader_parameter("dirt_texture", _get_fill_texture(1))
	visual_material.set_shader_parameter("rock_texture", _get_fill_texture(2))
	visual_material.set_shader_parameter("bedrock_texture", _get_fill_texture(3))
	visual_material.set_shader_parameter("constructed_texture", _get_fill_texture(4))
	visual_material.set_shader_parameter(
		"rim_texture",
		exposed_rim_texture if exposed_rim_texture != null else _get_fill_texture(1)
	)
	visual_material.set_shader_parameter("dirt_fallback", _get_debug_color(1))
	visual_material.set_shader_parameter("rock_fallback", _get_debug_color(2))
	visual_material.set_shader_parameter("bedrock_fallback", _get_debug_color(3))
	visual_material.set_shader_parameter("constructed_fallback", _get_debug_color(4))
	visual_material.set_shader_parameter("exposed_rim_color", exposed_rim_color)
	visual_material.set_shader_parameter("texture_world_size", texture_world_size)


func _get_fill_texture(target_material_id: int) -> Texture2D:
	var definition := palette.get_material(target_material_id)
	if definition != null and definition.fill_texture != null:
		return definition.fill_texture
	if _fallback_textures.has(target_material_id):
		return _fallback_textures[target_material_id] as Texture2D
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(_get_debug_color(target_material_id))
	var texture := ImageTexture.create_from_image(image)
	_fallback_textures[target_material_id] = texture
	return texture


func _get_debug_color(target_material_id: int) -> Color:
	var definition := palette.get_material(target_material_id)
	return definition.debug_color if definition != null else Color.MAGENTA


func _draw() -> void:
	if show_material_debug:
		for y in grid_size.y:
			for x in grid_size.x:
				var current_material_id := get_material_cell(Vector2i(x, y))
				if current_material_id == 0:
					continue
				var debug_color := _get_debug_color(current_material_id)
				debug_color.a = 0.48
				draw_rect(
					Rect2(Vector2(x, y) * float(cell_size), Vector2.ONE * float(cell_size)),
					debug_color
				)
	if show_chunk_debug or show_dirty_chunk_debug:
		for chunk: Vector2i in _chunk_bodies:
			var chunk_rect := Rect2(
				Vector2(chunk * chunk_cells * cell_size),
				Vector2.ONE * float(chunk_cells * cell_size)
			)
			if show_chunk_debug:
				draw_rect(chunk_rect, Color(0.25, 0.8, 1.0, 0.55), false, 2.0)
			if show_dirty_chunk_debug and _last_dirty_chunks.has(chunk):
				draw_rect(chunk_rect, Color(1.0, 0.35, 0.16, 0.16), true)
	if show_collision_debug:
		for body: StaticBody2D in _chunk_bodies.values():
			for child in body.get_children():
				var collision := child as CollisionShape2D
				var segment := collision.shape as SegmentShape2D if collision != null else null
				if segment != null:
					draw_line(segment.a, segment.b, Color(1.0, 0.85, 0.16, 0.9), 2.0)
