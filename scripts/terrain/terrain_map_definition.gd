class_name TerrainMapDefinition
extends Resource

## Lossless palette image used to initialize authored terrain material cells.

@export var material_map: Texture2D
@export var palette: TerrainMaterialPalette


func get_grid_size() -> Vector2i:
	if material_map == null:
		return Vector2i.ZERO
	return material_map.get_size()


func get_configuration_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if material_map == null:
		errors.append("Terrain map requires a material-map texture.")
	if palette == null:
		errors.append("Terrain map requires a material palette.")
		return errors
	errors.append_array(palette.get_configuration_errors())
	if material_map == null or not errors.is_empty():
		return errors

	var image := material_map.get_image()
	if image == null or image.is_empty():
		errors.append("Terrain material-map texture has no readable image data.")
		return errors
	palette.rebuild_lookup()
	var unknown_colors: Dictionary = {}
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if palette.get_material_id_for_source_color(color) < 0:
				unknown_colors[color.to_html(true)] = true
	if not unknown_colors.is_empty():
		errors.append(
			"Terrain material map contains unknown colors: %s."
			% ", ".join(unknown_colors.keys())
		)
	return errors


func create_material_data() -> PackedByteArray:
	var errors := get_configuration_errors()
	if not errors.is_empty():
		push_error("Cannot import terrain material map: %s" % "; ".join(errors))
		return PackedByteArray()
	var image := material_map.get_image()
	var data := PackedByteArray()
	data.resize(image.get_width() * image.get_height())
	for y in image.get_height():
		for x in image.get_width():
			data[y * image.get_width() + x] = palette.get_material_id_for_source_color(
				image.get_pixel(x, y)
			)
	return data
