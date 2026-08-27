class_name LevelMenuEntry
extends Resource

@export_range(1, 99, 1, "or_greater") var number: int = 1
@export var title: String = "Untitled Level"
@export_multiline var description: String
@export var ability_summary: String
@export_file("*.tscn") var scene_path: String
