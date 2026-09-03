class_name ProductionTerrainLab
extends Node2D

enum ToolMode {
	DIG,
	MINE,
	BOMB,
	BUILD,
}

@onready var terrain: ChunkedMaskTerrain = %Terrain
@onready var tool_status: Label = %ToolStatus
@onready var metrics: Label = %Metrics
@onready var debug_status: Label = %DebugStatus

var _tool_mode := ToolMode.DIG
var _debug_mode := 0
var _last_edit_position := Vector2(-1000.0, -1000.0)


func _ready() -> void:
	_update_tool_status()
	_update_debug_status()


func _process(_delta: float) -> void:
	metrics.text = (
		"Cells: %d solid  |  Chunks: %d visual / %d collision  |  Last edit: %d cells, %d chunks, %.2f ms  |  Total rebuild: %.2f ms"
		% [
			terrain.get_solid_cell_count(),
			terrain.get_visual_chunk_count(),
			terrain.get_chunk_count(),
			maxi(terrain.last_removed_cells, terrain.last_added_cells),
			terrain.last_rebuilt_chunks,
			float(terrain.last_rebuild_usec) / 1000.0,
			float(terrain.total_rebuild_usec) / 1000.0,
		]
	)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_apply_tool(get_global_mouse_position())
	else:
		_last_edit_position = Vector2(-1000.0, -1000.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_tool_mode = ToolMode.DIG
			KEY_2:
				_tool_mode = ToolMode.MINE
			KEY_3:
				_tool_mode = ToolMode.BOMB
			KEY_4:
				_tool_mode = ToolMode.BUILD
			KEY_R:
				terrain.reset_terrain()
			KEY_F3:
				_cycle_debug_display()
		_update_tool_status()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_apply_tool(get_global_mouse_position(), true)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			terrain.reset_terrain()


func _apply_tool(world_position: Vector2, force: bool = false) -> void:
	var local_position := terrain.to_local(world_position)
	if not force and local_position.distance_to(_last_edit_position) < 22.0:
		return
	_last_edit_position = local_position
	match _tool_mode:
		ToolMode.DIG:
			terrain.excavate_circle_with_operation(
				local_position, 42.0, ChunkedMaskTerrain.TerrainOperation.DIG
			)
		ToolMode.MINE:
			terrain.excavate_circle_with_operation(
				local_position, 42.0, ChunkedMaskTerrain.TerrainOperation.MINE
			)
		ToolMode.BOMB:
			terrain.excavate_circle_with_operation(
				local_position, 64.0, ChunkedMaskTerrain.TerrainOperation.BOMB, 2
			)
		ToolMode.BUILD:
			terrain.fill_rectangle(Rect2(local_position - Vector2(52.0, 12.0), Vector2(104.0, 24.0)))


func _cycle_debug_display() -> void:
	_debug_mode = (_debug_mode + 1) % 5
	terrain.set_debug_display(
		_debug_mode == 1,
		_debug_mode == 2,
		_debug_mode == 3,
		_debug_mode == 4
	)
	_update_debug_status()


func _update_tool_status() -> void:
	tool_status.text = "ACTIVE TOOL: %s" % ToolMode.keys()[_tool_mode]


func _update_debug_status() -> void:
	var names := ["Off", "Materials", "Chunk boundaries", "Collision contours", "Dirty chunks"]
	debug_status.text = "DEBUG: %s" % names[_debug_mode]
