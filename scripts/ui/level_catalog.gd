class_name LevelCatalog
extends Resource

@export var entries: Array[Resource] = []


func get_configuration_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var known_ids: Dictionary = {}
	for index in entries.size():
		var entry := entries[index] as LevelMenuEntry
		if entry == null:
			errors.append("Catalog entry %d is missing or has the wrong type." % index)
			continue
		if entry.level_definition == null:
			errors.append("Catalog entry %d has no level definition." % index)
			continue
		var level_id := entry.level_definition.level_id
		if level_id.is_empty():
			errors.append("Catalog entry %d has an empty level ID." % index)
		elif known_ids.has(level_id):
			errors.append("Catalog level ID '%s' is duplicated." % level_id)
		else:
			known_ids[level_id] = true
	return errors
