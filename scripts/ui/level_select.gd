class_name LevelSelect
extends Control

@export var catalog: Resource

@onready var level_list: VBoxContainer = %LevelList

var level_buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Engine.time_scale = 1.0
	_build_level_buttons()


func open_level(index: int) -> Error:
	if catalog == null or index < 0 or index >= catalog.entries.size():
		push_error("LevelSelect received an invalid level index: %d" % index)
		return ERR_INVALID_PARAMETER
	var entry = catalog.entries[index]
	if entry == null or entry.scene_path.is_empty():
		push_error("LevelSelect entry %d has no scene path." % index)
		return ERR_FILE_NOT_FOUND
	var change_error := get_tree().change_scene_to_file(entry.scene_path)
	if change_error != OK:
		push_error("Could not open level '%s': %s" % [entry.title, error_string(change_error)])
	return change_error


func _build_level_buttons() -> void:
	level_buttons.clear()
	for child in level_list.get_children():
		child.queue_free()
	if catalog == null:
		push_error("LevelSelect requires a LevelCatalog resource.")
		return
	for index in catalog.entries.size():
		var entry = catalog.entries[index]
		if entry == null:
			continue
		var button := Button.new()
		button.name = "Level%dButton" % entry.number
		button.custom_minimum_size = Vector2(0.0, 104.0)
		button.text = "%02d  %s\n%s\n%s" % [
			entry.number,
			entry.title,
			entry.description,
			entry.ability_summary,
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(open_level.bind(index))
		level_list.add_child(button)
		level_buttons.append(button)
