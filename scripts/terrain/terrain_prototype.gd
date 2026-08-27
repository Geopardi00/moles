class_name TerrainPrototype
extends Node2D

const FineCellTerrainScript = preload("res://scripts/terrain/fine_cell_terrain.gd")
const ChunkedMaskTerrainScript = preload("res://scripts/terrain/chunked_mask_terrain.gd")

@export_range(8.0, 160.0, 1.0) var dig_radius: float = 52.0

@onready var fine_cell_terrain: FineCellTerrainScript = $FineCellTerrain
@onready var chunked_mask_terrain: ChunkedMaskTerrainScript = $ChunkedMaskTerrain
@onready var fine_metrics: Label = %FineMetrics
@onready var mask_metrics: Label = %MaskMetrics
@onready var interaction_status: Label = %InteractionStatus

var _last_dig_world_position := Vector2.ZERO
var _has_last_dig := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_metrics("Ready — left-click or drag inside either terrain sample.")
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null and mouse_button.pressed:
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			dig_at_screen_position(mouse_button.position)
			get_viewport().set_input_as_handled()
		elif mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			reset_samples()
			get_viewport().set_input_as_handled()
		return

	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion != null and mouse_motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		dig_at_screen_position(mouse_motion.position)
		get_viewport().set_input_as_handled()


func dig_at_screen_position(screen_position: Vector2) -> int:
	var world_position := get_viewport().get_canvas_transform().affine_inverse() * screen_position
	return dig_at_world_position(world_position)


func dig_at_world_position(world_position: Vector2) -> int:
	var removed := 0
	var backend_name := "outside both samples"
	if _get_terrain_rect(fine_cell_terrain).has_point(world_position):
		removed = fine_cell_terrain.excavate_circle(fine_cell_terrain.to_local(world_position), dig_radius)
		backend_name = "TileMapLayer"
	elif _get_terrain_rect(chunked_mask_terrain).has_point(world_position):
		removed = chunked_mask_terrain.excavate_circle(chunked_mask_terrain.to_local(world_position), dig_radius)
		backend_name = "chunked mask"

	_last_dig_world_position = world_position
	_has_last_dig = removed > 0
	queue_redraw()
	_refresh_metrics("%s removed %d cells." % [backend_name, removed])
	return removed


func reset_samples() -> void:
	fine_cell_terrain.reset_terrain()
	chunked_mask_terrain.reset_terrain()
	_has_last_dig = false
	queue_redraw()
	_refresh_metrics("Both samples reset.")


func _draw() -> void:
	draw_rect(_get_terrain_rect(fine_cell_terrain), Color(0.75, 0.8, 0.82, 0.55), false, 2.0)
	draw_rect(_get_terrain_rect(chunked_mask_terrain), Color(0.75, 0.8, 0.82, 0.55), false, 2.0)
	if _has_last_dig:
		draw_arc(_last_dig_world_position, dig_radius, 0.0, TAU, 48, Color(0.95, 0.82, 0.28, 0.85), 2.0)


func _get_terrain_rect(terrain: Node2D) -> Rect2:
	return Rect2(terrain.global_position, terrain.get_terrain_size())


func _refresh_metrics(status_text: String) -> void:
	fine_metrics.text = (
		"16 px cells  |  solid: %d  |  collision units: %d\n"
		+ "last removed: %d  |  update: %d µs  |  cumulative: %d µs"
	) % [
		fine_cell_terrain.get_solid_cell_count(),
		fine_cell_terrain.get_collision_unit_count(),
		fine_cell_terrain.last_removed_cells,
		fine_cell_terrain.last_rebuild_usec,
		fine_cell_terrain.total_rebuild_usec,
	]
	mask_metrics.text = (
		"8 px mask  |  solid: %d  |  contour segments: %d\n"
		+ "last removed: %d  |  rebuilt chunks: %d  |  update: %d µs"
	) % [
		chunked_mask_terrain.get_solid_cell_count(),
		chunked_mask_terrain.get_collision_unit_count(),
		chunked_mask_terrain.last_removed_cells,
		chunked_mask_terrain.last_rebuilt_chunks,
		chunked_mask_terrain.last_rebuild_usec,
	]
	interaction_status.text = status_text
