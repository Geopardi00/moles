class_name ChunkedMaskTerrain
extends Node2D

## Fine occupancy mask with visuals independent from chunk-local boundary collision.

enum InitialShape {
	WAVY_GROUND,
	SOLID_RECTANGLE,
}

@export var grid_size: Vector2i = Vector2i(90, 48)
@export_range(2, 32, 1) var cell_size: int = 8
@export_range(4, 64, 1) var chunk_cells: int = 15
@export var terrain_color: Color = Color(0.4, 0.27, 0.15, 1.0)
@export_range(1, 32, 1) var material_id: int = 1
@export var initial_shape: InitialShape = InitialShape.WAVY_GROUND

var last_removed_cells: int = 0
var last_rebuild_usec: int = 0
var total_rebuild_usec: int = 0
var last_rebuilt_chunks: int = 0

var _solid := PackedByteArray()
var _chunk_bodies: Dictionary = {}


func _ready() -> void:
	reset_terrain()


func reset_terrain() -> void:
	var started_usec := Time.get_ticks_usec()
	_solid.resize(grid_size.x * grid_size.y)
	_solid.fill(0)
	for x in grid_size.x:
		var surface_y := 0 if initial_shape == InitialShape.SOLID_RECTANGLE else _get_surface_cell_y(x)
		for y in range(surface_y, grid_size.y):
			_set_solid(Vector2i(x, y), true)
	_rebuild_all_chunks()
	queue_redraw()
	last_removed_cells = 0
	last_rebuilt_chunks = _chunk_bodies.size()
	last_rebuild_usec = Time.get_ticks_usec() - started_usec
	total_rebuild_usec = last_rebuild_usec


func excavate_circle(local_center: Vector2, radius: float) -> int:
	var started_usec := Time.get_ticks_usec()
	var minimum := Vector2i(floori((local_center.x - radius) / cell_size), floori((local_center.y - radius) / cell_size))
	var maximum := Vector2i(floori((local_center.x + radius) / cell_size), floori((local_center.y + radius) / cell_size))
	var radius_squared := radius * radius
	var affected_chunks: Dictionary = {}
	var removed := 0
	for x in range(maxi(minimum.x, 0), mini(maximum.x + 1, grid_size.x)):
		for y in range(maxi(minimum.y, 0), mini(maximum.y + 1, grid_size.y)):
			var cell := Vector2i(x, y)
			var cell_center := (Vector2(cell) + Vector2(0.5, 0.5)) * float(cell_size)
			if cell_center.distance_squared_to(local_center) <= radius_squared and _is_solid(cell):
				_set_solid(cell, false)
				affected_chunks[_cell_to_chunk(cell)] = true
				removed += 1
	for chunk: Vector2i in affected_chunks:
		_rebuild_chunk(chunk)
	if removed > 0:
		queue_redraw()
	last_removed_cells = removed
	last_rebuilt_chunks = affected_chunks.size()
	last_rebuild_usec = Time.get_ticks_usec() - started_usec
	total_rebuild_usec += last_rebuild_usec
	return removed


func get_solid_cell_count() -> int:
	var count := 0
	for value in _solid:
		count += int(value)
	return count


func get_collision_unit_count() -> int:
	var count := 0
	for body: StaticBody2D in _chunk_bodies.values():
		count += body.get_child_count()
	return count


func get_chunk_count() -> int:
	return _chunk_bodies.size()


func get_material_at(local_position: Vector2) -> int:
	var cell := Vector2i(floori(local_position.x / cell_size), floori(local_position.y / cell_size))
	return material_id if _is_solid(cell) else 0


func get_terrain_size() -> Vector2:
	return Vector2(grid_size * cell_size)


func _draw() -> void:
	for y in grid_size.y:
		var run_start := -1
		for x in range(grid_size.x + 1):
			var occupied := x < grid_size.x and _is_solid(Vector2i(x, y))
			if occupied and run_start < 0:
				run_start = x
			elif not occupied and run_start >= 0:
				draw_rect(Rect2(
					Vector2(run_start * cell_size, y * cell_size),
					Vector2((x - run_start) * cell_size, cell_size)
				), terrain_color)
				run_start = -1


func _get_surface_cell_y(x: int) -> int:
	var wave := sin(float(x) * 0.14) * 3.2 + sin(float(x) * 0.045) * 2.4
	return clampi(12 + roundi(wave), 6, grid_size.y - 4)


func _is_solid(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= grid_size.x or cell.y >= grid_size.y:
		return false
	return _solid[cell.y * grid_size.x + cell.x] != 0


func _set_solid(cell: Vector2i, value: bool) -> void:
	_solid[cell.y * grid_size.x + cell.x] = 1 if value else 0


func _cell_to_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x / chunk_cells, cell.y / chunk_cells)


func _rebuild_all_chunks() -> void:
	var chunk_count := Vector2i(
		ceili(float(grid_size.x) / chunk_cells),
		ceili(float(grid_size.y) / chunk_cells)
	)
	for chunk_x in chunk_count.x:
		for chunk_y in chunk_count.y:
			_rebuild_chunk(Vector2i(chunk_x, chunk_y))


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
			if not _is_solid(cell + Vector2i.DOWN):
				_append_unit_edge(horizontal_edges, y + 1, x)
			if not _is_solid(cell + Vector2i.LEFT):
				_append_unit_edge(vertical_edges, x, y)
			if not _is_solid(cell + Vector2i.RIGHT):
				_append_unit_edge(vertical_edges, x + 1, y)
	_add_merged_contour_segments(body, horizontal_edges, true)
	_add_merged_contour_segments(body, vertical_edges, false)


func _get_or_create_chunk_body(chunk: Vector2i) -> StaticBody2D:
	if _chunk_bodies.has(chunk):
		return _chunk_bodies[chunk] as StaticBody2D
	var body := StaticBody2D.new()
	body.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
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
