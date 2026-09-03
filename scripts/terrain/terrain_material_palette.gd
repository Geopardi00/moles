class_name TerrainMaterialPalette
extends Resource

## Validated lookup table for byte-sized terrain material IDs and source colors.

@export var materials: Array[TerrainMaterialDefinition] = []

var _materials_by_id: Dictionary = {}
var _ids_by_source_color: Dictionary = {}


func rebuild_lookup() -> void:
	_materials_by_id.clear()
	_ids_by_source_color.clear()
	for definition in materials:
		if definition == null:
			continue
		_materials_by_id[definition.material_id] = definition
		_ids_by_source_color[definition.source_color.to_rgba32()] = definition.material_id


func get_material(material_id: int) -> TerrainMaterialDefinition:
	if _materials_by_id.is_empty() and not materials.is_empty():
		rebuild_lookup()
	return _materials_by_id.get(material_id) as TerrainMaterialDefinition


func get_material_id_for_source_color(color: Color) -> int:
	if color.a < 0.5:
		return 0
	if _ids_by_source_color.is_empty() and not materials.is_empty():
		rebuild_lookup()
	return int(_ids_by_source_color.get(color.to_rgba32(), -1))


func get_configuration_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var known_ids: Dictionary = {}
	var known_colors: Dictionary = {}
	for index in materials.size():
		var definition := materials[index]
		if definition == null:
			errors.append("Material entry %d is missing." % index)
			continue
		if definition.material_id <= 0 or definition.material_id > 255:
			errors.append("Material '%s' must use an ID from 1 through 255." % definition.display_name)
		elif known_ids.has(definition.material_id):
			errors.append("Material ID %d is duplicated." % definition.material_id)
		else:
			known_ids[definition.material_id] = true
		var color_key := definition.source_color.to_rgba32()
		if definition.source_color.a < 0.5:
			errors.append("Material '%s' cannot use a transparent source color." % definition.display_name)
		elif known_colors.has(color_key):
			errors.append("Material source color for '%s' is duplicated." % definition.display_name)
		else:
			known_colors[color_key] = true
	return errors


static func create_default(legacy_dirt_color: Color = Color8(102, 69, 38)) -> TerrainMaterialPalette:
	var palette := TerrainMaterialPalette.new()
	palette.materials = [
		_create_material(1, "Dirt", Color8(113, 74, 43), legacy_dirt_color, true, true, 1, false),
		_create_material(2, "Rock", Color8(83, 96, 106), Color8(83, 96, 106), false, true, 2, false),
		_create_material(3, "Bedrock", Color8(37, 42, 49), Color8(37, 42, 49), false, false, 255, true),
		_create_material(4, "Constructed", Color8(190, 139, 74), Color8(190, 139, 74), true, true, 1, false),
	]
	palette.rebuild_lookup()
	return palette


static func _create_material(
	material_id: int,
	display_name: String,
	source_color: Color,
	debug_color: Color,
	diggable: bool,
	mineable: bool,
	blast_resistance: int,
	indestructible: bool
) -> TerrainMaterialDefinition:
	var definition := TerrainMaterialDefinition.new()
	definition.material_id = material_id
	definition.display_name = display_name
	definition.source_color = source_color
	definition.debug_color = debug_color
	definition.diggable = diggable
	definition.mineable = mineable
	definition.blast_resistance = blast_resistance
	definition.indestructible = indestructible
	return definition
