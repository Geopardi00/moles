extends Node

## Owns versioned, local best-medal persistence across scene changes.

signal progress_changed(level_id: StringName, best_medal: int)

const CURRENT_SCHEMA_VERSION := 1
const DEFAULT_STORAGE_PATH := "user://progress.cfg"
const META_SECTION := "meta"
const MEDALS_SECTION := "medals"
const SCHEMA_VERSION_KEY := "schema_version"

var active_level_id: StringName = &""
var storage_path: String = DEFAULT_STORAGE_PATH
var _best_medals: Dictionary = {}
var _saving_blocked: bool = false


func _ready() -> void:
	load_progress(DEFAULT_STORAGE_PATH)


func load_progress(path: String = DEFAULT_STORAGE_PATH) -> Error:
	storage_path = path
	active_level_id = &""
	_best_medals.clear()
	_saving_blocked = false
	if not FileAccess.file_exists(storage_path):
		return OK

	var config := ConfigFile.new()
	var load_error := config.load(storage_path)
	if load_error != OK:
		push_warning(
			"ProgressStore could not read '%s'; starting with fresh progress: %s"
			% [storage_path, error_string(load_error)]
		)
		return load_error

	var raw_version: Variant = config.get_value(META_SECTION, SCHEMA_VERSION_KEY, 0)
	if typeof(raw_version) != TYPE_INT:
		push_warning("ProgressStore found a non-integer schema version; starting fresh.")
		return ERR_INVALID_DATA
	var schema_version := int(raw_version)
	if schema_version > CURRENT_SCHEMA_VERSION:
		_saving_blocked = true
		push_warning(
			"ProgressStore will not overwrite newer schema version %d (supported: %d)."
			% [schema_version, CURRENT_SCHEMA_VERSION]
		)
		return ERR_UNAVAILABLE
	if schema_version != CURRENT_SCHEMA_VERSION:
		push_warning(
			"ProgressStore found unsupported schema version %d; starting fresh."
			% schema_version
		)
		return ERR_INVALID_DATA

	if not config.has_section(MEDALS_SECTION):
		return OK
	for key in config.get_section_keys(MEDALS_SECTION):
		var raw_medal: Variant = config.get_value(MEDALS_SECTION, key)
		if typeof(raw_medal) != TYPE_INT or not _is_persistable_medal(int(raw_medal)):
			push_warning("ProgressStore ignored invalid medal data for level '%s'." % key)
			continue
		_best_medals[StringName(key)] = int(raw_medal)
	return OK


func begin_level(level_id: StringName) -> bool:
	if level_id.is_empty():
		push_warning("ProgressStore cannot begin a level with an empty ID.")
		return false
	active_level_id = level_id
	return true


func clear_active_level() -> void:
	active_level_id = &""


func get_best_medal(level_id: StringName) -> int:
	return int(_best_medals.get(level_id, LevelDefinition.MedalTier.NONE))


func record_active_medal(level_id: StringName, medal: int) -> bool:
	if active_level_id.is_empty() or active_level_id != level_id:
		return false
	if _saving_blocked or not _is_persistable_medal(medal):
		return false
	if medal <= get_best_medal(level_id):
		return false

	_best_medals[level_id] = medal
	var save_error := _save_progress()
	if save_error != OK:
		push_warning(
			"ProgressStore could not save '%s': %s"
			% [storage_path, error_string(save_error)]
		)
	progress_changed.emit(level_id, medal)
	return true


func is_saving_blocked() -> bool:
	return _saving_blocked


func _save_progress() -> Error:
	var base_directory := storage_path.get_base_dir()
	if not base_directory.is_empty():
		var directory_error := DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(base_directory)
		)
		if directory_error != OK:
			return directory_error
	var config := ConfigFile.new()
	config.set_value(META_SECTION, SCHEMA_VERSION_KEY, CURRENT_SCHEMA_VERSION)
	var level_ids: Array = _best_medals.keys()
	level_ids.sort()
	for level_id in level_ids:
		config.set_value(MEDALS_SECTION, String(level_id), int(_best_medals[level_id]))
	return config.save(storage_path)


func _is_persistable_medal(medal: int) -> bool:
	return (
		medal >= LevelDefinition.MedalTier.BRONZE
		and medal <= LevelDefinition.MedalTier.GOLD
	)
