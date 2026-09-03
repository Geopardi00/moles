extends SceneTree

## Converts the generated 4x2 reference sheet into eight transparent runtime decals.

const SOURCE_PATH := "res://art/Terrain/Source/terrain_detail_decal_sheet_source.png"
const OUTPUT_DIRECTORY := "res://art/Terrain/Runtime/Decals"
const OUTPUT_NAMES := [
	"root_branching.png",
	"root_curled.png",
	"stones_cluster.png",
	"stone_cracked.png",
	"cave_moss.png",
	"mineral_flecks.png",
	"soil_crumbs.png",
	"root_hanging.png",
]


func _initialize() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE_PATH))
	if source == null or source.is_empty():
		push_error("Could not load decal source sheet: %s" % SOURCE_PATH)
		quit(1)
		return
	source.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIRECTORY))
	var cell_size := Vector2i(source.get_width() / 4, source.get_height() / 2)
	for index in OUTPUT_NAMES.size():
		var cell := Vector2i(index % 4, index / 4)
		var decal := source.get_region(Rect2i(cell * cell_size, cell_size))
		_remove_generated_checkerboard(decal)
		var path: String = "%s/%s" % [OUTPUT_DIRECTORY, OUTPUT_NAMES[index]]
		var error := decal.save_png(path)
		if error != OK:
			push_error("Could not save decal %s: %s" % [path, error_string(error)])
			quit(1)
			return
	print("Generated eight transparent runtime decals in %s." % OUTPUT_DIRECTORY)
	quit(0)


func _remove_generated_checkerboard(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			var maximum := maxf(color.r, maxf(color.g, color.b))
			var minimum := minf(color.r, minf(color.g, color.b))
			var chroma := maximum - minimum
			if chroma < 0.09 and minimum > 0.84:
				color.a = clampf((0.94 - maximum) / 0.10, 0.0, 1.0)
				image.set_pixel(x, y, color)
