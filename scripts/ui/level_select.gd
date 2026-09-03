class_name LevelSelect
extends Control

@export var catalog: Resource

@onready var level_list: VBoxContainer = %LevelList
@onready var progress_store: Node = get_node_or_null("/root/ProgressStore")

var level_buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Engine.time_scale = 1.0
	if progress_store == null:
		push_error("LevelSelect requires the ProgressStore autoload.")
	else:
		progress_store.clear_active_level()
		progress_store.progress_changed.connect(_on_progress_changed)
	_build_level_buttons()


func open_level(index: int) -> Error:
	if catalog == null or index < 0 or index >= catalog.entries.size():
		push_error("LevelSelect received an invalid level index: %d" % index)
		return ERR_INVALID_PARAMETER
	if not is_level_unlocked(index):
		push_warning("LevelSelect rejected locked level index %d." % index)
		return ERR_UNAUTHORIZED
	var entry := catalog.entries[index] as LevelMenuEntry
	if entry == null or entry.scene_path.is_empty():
		push_error("LevelSelect entry %d has no scene path." % index)
		return ERR_FILE_NOT_FOUND
	if entry.level_definition == null or progress_store == null:
		push_error("LevelSelect entry %d has no usable progression identity." % index)
		return ERR_INVALID_DATA
	if not progress_store.begin_level(entry.level_definition.level_id):
		return ERR_INVALID_DATA
	var change_error := get_tree().change_scene_to_file(entry.scene_path)
	if change_error != OK:
		progress_store.clear_active_level()
		push_error(
			"Could not open level '%s': %s"
			% [entry.level_definition.display_name, error_string(change_error)]
		)
	return change_error


func is_level_unlocked(index: int) -> bool:
	if catalog == null or progress_store == null or index < 0 or index >= catalog.entries.size():
		return false
	if index == 0:
		return true
	var previous_entry := catalog.entries[index - 1] as LevelMenuEntry
	if previous_entry == null or previous_entry.level_definition == null:
		return false
	return (
		progress_store.get_best_medal(previous_entry.level_definition.level_id)
		>= LevelDefinition.MedalTier.BRONZE
	)


func _build_level_buttons() -> void:
	level_buttons.clear()
	for child in level_list.get_children():
		level_list.remove_child(child)
		child.queue_free()
	if catalog == null:
		push_error("LevelSelect requires a LevelCatalog resource.")
		return
	var configuration_errors: PackedStringArray = catalog.get_configuration_errors()
	if not configuration_errors.is_empty():
		push_error("LevelSelect received an invalid catalog: %s" % "; ".join(configuration_errors))
		return
	for index in catalog.entries.size():
		var entry := catalog.entries[index] as LevelMenuEntry
		if entry == null:
			continue
		var definition := entry.level_definition
		var unlocked := is_level_unlocked(index)
		var status_text := _get_progress_status(index, unlocked)
		var button := Button.new()
		button.name = "Level%dButton" % entry.number
		button.custom_minimum_size = Vector2(0.0, 90.0)
		button.text = "%02d  %s\n%s\n%s  •  %s" % [
			entry.number,
			definition.display_name,
			entry.description,
			entry.ability_summary,
			status_text,
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 20)
		button.disabled = not unlocked
		button.pressed.connect(open_level.bind(index))
		level_list.add_child(button)
		level_buttons.append(button)


func _get_progress_status(index: int, unlocked: bool) -> String:
	if not unlocked:
		var previous_entry := catalog.entries[index - 1] as LevelMenuEntry
		return "LOCKED — Earn Bronze on Level %02d" % previous_entry.number
	var entry := catalog.entries[index] as LevelMenuEntry
	var best_medal: int = progress_store.get_best_medal(entry.level_definition.level_id)
	if best_medal == LevelDefinition.MedalTier.NONE:
		return "Best: —"
	return "Best: %s" % LevelDefinition.get_medal_display_name(best_medal).capitalize()


func _on_progress_changed(_level_id: StringName, _best_medal: int) -> void:
	_build_level_buttons()
