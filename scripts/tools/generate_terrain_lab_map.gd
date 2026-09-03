extends SceneTree

## Rebuilds the exact-color source map used by the Milestone 14 terrain lab.

const OUTPUT_PATH := "res://art/Terrain/Maps/terrain_lab_material_map.png"
const MAP_SIZE := Vector2i(320, 110)
const EMPTY := Color8(0, 0, 0, 0)
const DIRT := Color8(113, 74, 43)
const ROCK := Color8(83, 96, 106)
const BEDROCK := Color8(37, 42, 49)
const CONSTRUCTED := Color8(190, 139, 74)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/Terrain/Maps"))
	var image := Image.create(MAP_SIZE.x, MAP_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(EMPTY)

	for x in MAP_SIZE.x:
		var surface := clampi(
			24 + roundi(sin(float(x) * 0.055) * 5.0 + sin(float(x) * 0.017) * 8.0),
			12,
			37
		)
		for y in range(surface, MAP_SIZE.y):
			image.set_pixel(x, y, DIRT)

	# Bedrock establishes indestructible map edges and a deep foundation.
	for y in MAP_SIZE.y:
		for x in MAP_SIZE.x:
			if y >= MAP_SIZE.y - 8 or x < 3 or x >= MAP_SIZE.x - 3:
				image.set_pixel(x, y, BEDROCK)

	# Resistant rock strata and pockets interrupt the softer dirt.
	_paint_ellipse(image, Vector2i(58, 54), Vector2i(31, 10), ROCK)
	_paint_ellipse(image, Vector2i(150, 71), Vector2i(42, 9), ROCK)
	_paint_ellipse(image, Vector2i(254, 48), Vector2i(28, 13), ROCK)
	_paint_ellipse(image, Vector2i(288, 83), Vector2i(19, 8), ROCK)

	# Empty forms are painted last so they create caves, overhangs, shafts, and islands.
	_paint_ellipse(image, Vector2i(88, 67), Vector2i(43, 17), EMPTY)
	_paint_ellipse(image, Vector2i(119, 58), Vector2i(25, 12), EMPTY)
	_paint_ellipse(image, Vector2i(206, 64), Vector2i(48, 18), EMPTY)
	_paint_ellipse(image, Vector2i(239, 58), Vector2i(26, 12), EMPTY)
	_paint_ellipse(image, Vector2i(281, 69), Vector2i(25, 16), EMPTY)
	_paint_rect(image, Rect2i(171, 25, 8, 45), EMPTY)

	# Restore a floating dirt island and an authored constructed ledge inside the caves.
	_paint_ellipse(image, Vector2i(205, 57), Vector2i(13, 5), DIRT)
	_paint_rect(image, Rect2i(105, 65, 24, 3), CONSTRUCTED)

	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("Could not save terrain lab map: %s" % error_string(error))
		quit(1)
		return
	print("Generated %s (%dx%d exact-color cells)." % [OUTPUT_PATH, MAP_SIZE.x, MAP_SIZE.y])
	quit(0)


func _paint_ellipse(image: Image, center: Vector2i, radius: Vector2i, color: Color) -> void:
	for y in range(maxi(center.y - radius.y, 0), mini(center.y + radius.y + 1, MAP_SIZE.y)):
		for x in range(maxi(center.x - radius.x, 0), mini(center.x + radius.x + 1, MAP_SIZE.x)):
			var offset := Vector2(x - center.x, y - center.y) / Vector2(radius)
			if offset.length_squared() <= 1.0:
				image.set_pixel(x, y, color)


func _paint_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(maxi(rect.position.y, 0), mini(rect.end.y, MAP_SIZE.y)):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, MAP_SIZE.x)):
			image.set_pixel(x, y, color)
