class_name LevelDefinition
extends Resource

## Inspector-friendly, reusable configuration for one level's population and goals.

enum MedalTier {
	NONE,
	BRONZE,
	SILVER,
	GOLD,
}

@export_category("Identity")
@export var level_id: StringName
@export var display_name: String = "Untitled Level"

@export_category("Population")
@export_range(1, 200, 1, "or_greater") var total_creatures: int = 20
@export_range(0.02, 10.0, 0.01, "or_greater") var spawn_interval: float = 0.25
@export_enum("Left:-1", "Right:1") var initial_direction: int = 1

@export_category("Rescue Medals")
@export_range(0, 200, 1, "or_greater") var bronze_rescue_count: int = 14
@export_range(0, 200, 1, "or_greater") var silver_rescue_count: int = 17
@export_range(0, 200, 1, "or_greater") var gold_rescue_count: int = 20

@export_category("Ability Inventory")
@export_range(0, 99, 1, "or_greater") var dig_ability_count: int = 0
@export_range(0, 99, 1, "or_greater") var mine_ability_count: int = 0
@export_range(0, 99, 1, "or_greater") var build_ability_count: int = 0
@export_range(0, 99, 1, "or_greater") var block_ability_count: int = 0
@export_range(0, 99, 1, "or_greater") var bomb_ability_count: int = 0


func get_required_rescue_count() -> int:
	return bronze_rescue_count


func get_medal_for_saved_count(saved_count: int) -> MedalTier:
	if saved_count >= gold_rescue_count:
		return MedalTier.GOLD
	if saved_count >= silver_rescue_count:
		return MedalTier.SILVER
	if saved_count >= bronze_rescue_count:
		return MedalTier.BRONZE
	return MedalTier.NONE


func has_valid_medal_thresholds() -> bool:
	return get_medal_configuration_errors().is_empty()


func get_medal_configuration_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if bronze_rescue_count < 0:
		errors.append("Bronze rescue count cannot be negative.")
	if bronze_rescue_count > silver_rescue_count:
		errors.append("Bronze rescue count cannot exceed Silver.")
	if silver_rescue_count > gold_rescue_count:
		errors.append("Silver rescue count cannot exceed Gold.")
	if gold_rescue_count > total_creatures:
		errors.append("Gold rescue count cannot exceed the total creature count.")
	return errors


static func get_medal_display_name(medal: MedalTier) -> String:
	match medal:
		MedalTier.BRONZE:
			return "BRONZE"
		MedalTier.SILVER:
			return "SILVER"
		MedalTier.GOLD:
			return "GOLD"
		_:
			return "NO MEDAL"
