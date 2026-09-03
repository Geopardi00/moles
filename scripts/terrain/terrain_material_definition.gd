class_name TerrainMaterialDefinition
extends Resource

## Data-driven rules and presentation inputs for one terrain material.

@export_range(1, 255, 1) var material_id: int = 1
@export var display_name: String = "Dirt"
@export var source_color: Color = Color8(113, 74, 43)
@export var debug_color: Color = Color8(113, 74, 43)
@export var fill_texture: Texture2D
@export var diggable: bool = true
@export var mineable: bool = true
@export_range(0, 255, 1) var blast_resistance: int = 1
@export var indestructible: bool = false


func can_remove(operation: int, strength: int = 1) -> bool:
	if indestructible:
		return false
	match operation:
		ChunkedMaskTerrain.TerrainOperation.DIG:
			return diggable
		ChunkedMaskTerrain.TerrainOperation.MINE:
			return mineable
		ChunkedMaskTerrain.TerrainOperation.BOMB:
			return strength >= blast_resistance
	return false
