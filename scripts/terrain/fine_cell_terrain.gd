class_name FineCellTerrain
extends TileMapLayer

## Fine-cell baseline backed directly by TileMapLayer cells and per-tile collision.

@export var grid_size: Vector2i = Vector2i(45, 24)
@export_range(4, 64, 1) var cell_size: int = 16
@export var terrain_color: Color = Color(0.42, 0.29, 0.17, 1.0)
@export_range(1, 32, 1) var material_id: int = 1

var last_removed_cells: int = 0
var last_rebuild_usec: int = 0
var total_rebuild_usec: int = 0


func _ready() -> void:
	_build_tile_set()
	reset_terrain()


func reset_terrain() -> void:
	var started_usec := Time.get_ticks_usec()
	clear()
	for x in grid_size.x:
		var surface_y := _get_surface_cell_y(x)
		for y in range(surface_y, grid_size.y):
			set_cell(Vector2i(x, y), 0, Vector2i.ZERO, 0)
	update_internals()
	last_removed_cells = 0
	last_rebuild_usec = Time.get_ticks_usec() - started_usec
	total_rebuild_usec = last_rebuild_usec


func excavate_circle(local_center: Vector2, radius: float) -> int:
	var started_usec := Time.get_ticks_usec()
	var minimum := Vector2i(floori((local_center.x - radius) / cell_size), floori((local_center.y - radius) / cell_size))
	var maximum := Vector2i(floori((local_center.x + radius) / cell_size), floori((local_center.y + radius) / cell_size))
	var radius_squared := radius * radius
	var removed := 0
	for x in range(maxi(minimum.x, 0), mini(maximum.x + 1, grid_size.x)):
		for y in range(maxi(minimum.y, 0), mini(maximum.y + 1, grid_size.y)):
			var cell := Vector2i(x, y)
			var cell_center := (Vector2(cell) + Vector2(0.5, 0.5)) * float(cell_size)
			if cell_center.distance_squared_to(local_center) <= radius_squared and get_cell_source_id(cell) != -1:
				erase_cell(cell)
				removed += 1
	if removed > 0:
		update_internals()
	last_removed_cells = removed
	last_rebuild_usec = Time.get_ticks_usec() - started_usec
	total_rebuild_usec += last_rebuild_usec
	return removed


func get_solid_cell_count() -> int:
	return get_used_cells().size()


func get_collision_unit_count() -> int:
	return get_solid_cell_count()


func get_material_at(local_position: Vector2) -> int:
	var cell := Vector2i(floori(local_position.x / cell_size), floori(local_position.y / cell_size))
	return material_id if get_cell_source_id(cell) != -1 else 0


func get_terrain_size() -> Vector2:
	return Vector2(grid_size * cell_size)


func _get_surface_cell_y(x: int) -> int:
	var wave := sin(float(x) * 0.28) * 1.6 + sin(float(x) * 0.09) * 1.2
	return clampi(6 + roundi(wave), 3, grid_size.y - 2)


func _build_tile_set() -> void:
	var generated_tile_set := TileSet.new()
	generated_tile_set.tile_size = Vector2i(cell_size, cell_size)
	generated_tile_set.add_physics_layer(0)
	generated_tile_set.set_physics_layer_collision_layer(0, 1)
	generated_tile_set.set_physics_layer_collision_mask(0, 0)

	var image := Image.create(cell_size, cell_size, false, Image.FORMAT_RGBA8)
	image.fill(terrain_color)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(cell_size, cell_size)
	generated_tile_set.add_source(atlas, 0)
	atlas.create_tile(Vector2i.ZERO)
	var tile_data := atlas.get_tile_data(Vector2i.ZERO, 0)
	tile_data.add_collision_polygon(0)
	var half_size := float(cell_size) * 0.5
	tile_data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-half_size, -half_size),
		Vector2(half_size, -half_size),
		Vector2(half_size, half_size),
		Vector2(-half_size, half_size),
	]))
	tile_set = generated_tile_set
