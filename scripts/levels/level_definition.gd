class_name LevelDefinition
extends Resource

## Inspector-friendly, reusable configuration for one level's population and goal.

enum RescueRequirementMode {
	COUNT,
	PERCENTAGE,
}

@export_category("Identity")
@export var display_name: String = "Untitled Level"

@export_category("Population")
@export_range(1, 200, 1, "or_greater") var total_creatures: int = 20
@export_range(0.02, 10.0, 0.01, "or_greater") var spawn_interval: float = 0.25
@export_enum("Left:-1", "Right:1") var initial_direction: int = 1

@export_category("Rescue Requirement")
@export var rescue_requirement_mode: RescueRequirementMode = RescueRequirementMode.PERCENTAGE
@export_range(0, 200, 1, "or_greater") var required_rescue_count: int = 1
@export_range(0.0, 100.0, 0.1) var required_rescue_percentage: float = 70.0


func get_required_rescue_count() -> int:
	var requirement: int
	if rescue_requirement_mode == RescueRequirementMode.COUNT:
		requirement = required_rescue_count
	else:
		requirement = ceili(float(total_creatures) * required_rescue_percentage / 100.0)
	return clampi(requirement, 0, total_creatures)


func get_effective_rescue_percentage() -> float:
	if total_creatures <= 0:
		return 0.0
	return 100.0 * float(get_required_rescue_count()) / float(total_creatures)
