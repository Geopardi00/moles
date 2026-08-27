class_name AbilityAssignmentController
extends Node

## Owns player ability selection, targeting, and limited-use inventory.

signal selected_ability_changed(ability: Ability)
signal inventory_changed(
	dig_remaining: int,
	build_remaining: int,
	block_remaining: int,
	bomb_remaining: int
)
signal ability_assigned(creature: Creature, ability: Ability)

enum Ability {
	NONE,
	DIG,
	BUILD,
	BLOCK,
	BOMB,
}

const SELECTION_COLLISION_MASK := 1 << 4

var selected_ability: Ability = Ability.NONE
var dig_remaining: int = 0
var build_remaining: int = 0
var block_remaining: int = 0
var bomb_remaining: int = 0
var assignment_enabled: bool = true
var hovered_creature: Creature
var dig_target_validator: Callable
var build_target_validator: Callable
var bomb_target_validator: Callable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if selected_ability == Ability.NONE or not assignment_enabled:
		_set_hovered_creature(null)
		return
	update_hover_at_screen_position(get_viewport().get_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if (
		mouse_event == null
		or mouse_event.button_index != MOUSE_BUTTON_LEFT
		or not mouse_event.pressed
		or selected_ability == Ability.NONE
		or not assignment_enabled
	):
		return

	var target := find_target_at_screen_position(mouse_event.position)
	if target != null and assign_selected_ability(target):
		get_viewport().set_input_as_handled()


func begin_level(level_definition: LevelDefinition) -> void:
	dig_remaining = maxi(level_definition.dig_ability_count, 0)
	build_remaining = maxi(level_definition.build_ability_count, 0)
	block_remaining = maxi(level_definition.block_ability_count, 0)
	bomb_remaining = maxi(level_definition.bomb_ability_count, 0)
	assignment_enabled = true
	set_selected_ability(Ability.NONE)
	inventory_changed.emit(dig_remaining, build_remaining, block_remaining, bomb_remaining)


func set_dig_target_validator(validator: Callable) -> void:
	dig_target_validator = validator


func set_build_target_validator(validator: Callable) -> void:
	build_target_validator = validator


func set_bomb_target_validator(validator: Callable) -> void:
	bomb_target_validator = validator


func toggle_dig_selection() -> void:
	set_selected_ability(Ability.NONE if selected_ability == Ability.DIG else Ability.DIG)


func select_dig() -> void:
	set_selected_ability(Ability.DIG)


func is_dig_selected() -> bool:
	return selected_ability == Ability.DIG


func toggle_build_selection() -> void:
	set_selected_ability(Ability.NONE if selected_ability == Ability.BUILD else Ability.BUILD)


func select_build() -> void:
	set_selected_ability(Ability.BUILD)


func is_build_selected() -> bool:
	return selected_ability == Ability.BUILD


func toggle_block_selection() -> void:
	set_selected_ability(Ability.NONE if selected_ability == Ability.BLOCK else Ability.BLOCK)


func select_block() -> void:
	set_selected_ability(Ability.BLOCK)


func is_block_selected() -> bool:
	return selected_ability == Ability.BLOCK


func toggle_bomb_selection() -> void:
	set_selected_ability(Ability.NONE if selected_ability == Ability.BOMB else Ability.BOMB)


func select_bomb() -> void:
	set_selected_ability(Ability.BOMB)


func is_bomb_selected() -> bool:
	return selected_ability == Ability.BOMB


func set_selected_ability(ability: Ability) -> void:
	if ability == Ability.DIG and (dig_remaining <= 0 or not assignment_enabled):
		ability = Ability.NONE
	elif ability == Ability.BUILD and (build_remaining <= 0 or not assignment_enabled):
		ability = Ability.NONE
	elif ability == Ability.BLOCK and (block_remaining <= 0 or not assignment_enabled):
		ability = Ability.NONE
	elif ability == Ability.BOMB and (bomb_remaining <= 0 or not assignment_enabled):
		ability = Ability.NONE
	if selected_ability == ability:
		return
	selected_ability = ability
	if selected_ability == Ability.NONE:
		_set_hovered_creature(null)
	selected_ability_changed.emit(selected_ability)


func set_assignment_enabled(enabled: bool) -> void:
	assignment_enabled = enabled
	if not assignment_enabled:
		set_selected_ability(Ability.NONE)


func update_hover_at_screen_position(screen_position: Vector2) -> void:
	_set_hovered_creature(find_target_at_screen_position(screen_position))


func find_target_at_screen_position(screen_position: Vector2) -> Creature:
	if selected_ability == Ability.NONE or not assignment_enabled:
		return null

	var world_position := get_viewport().get_canvas_transform().affine_inverse() * screen_position
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_position
	query.collision_mask = SELECTION_COLLISION_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var best_target: Creature
	var best_distance_squared := INF
	for result in get_viewport().world_2d.direct_space_state.intersect_point(query, 32):
		var area := result.get("collider") as Area2D
		var creature := area.get_parent() as Creature if area != null else null
		if not _is_valid_target(creature):
			continue
		var distance_squared := creature.global_position.distance_squared_to(world_position)
		if distance_squared < best_distance_squared:
			best_target = creature
			best_distance_squared = distance_squared
	return best_target


func assign_selected_ability(creature: Creature) -> bool:
	if not assignment_enabled or not _is_valid_target(creature):
		return false
	match selected_ability:
		Ability.DIG:
			if dig_remaining <= 0 or not creature.begin_dig():
				return false
			dig_remaining -= 1
			inventory_changed.emit(dig_remaining, build_remaining, block_remaining, bomb_remaining)
			ability_assigned.emit(creature, Ability.DIG)
			if dig_remaining == 0:
				set_selected_ability(Ability.NONE)
			return true
		Ability.BUILD:
			if build_remaining <= 0 or not creature.begin_build():
				return false
			build_remaining -= 1
			inventory_changed.emit(dig_remaining, build_remaining, block_remaining, bomb_remaining)
			ability_assigned.emit(creature, Ability.BUILD)
			if build_remaining == 0:
				set_selected_ability(Ability.NONE)
			return true
		Ability.BLOCK:
			if block_remaining <= 0 or not creature.begin_block():
				return false
			block_remaining -= 1
			inventory_changed.emit(dig_remaining, build_remaining, block_remaining, bomb_remaining)
			ability_assigned.emit(creature, Ability.BLOCK)
			if block_remaining == 0:
				set_selected_ability(Ability.NONE)
			return true
		Ability.BOMB:
			if bomb_remaining <= 0 or not creature.begin_bomb():
				return false
			bomb_remaining -= 1
			inventory_changed.emit(dig_remaining, build_remaining, block_remaining, bomb_remaining)
			ability_assigned.emit(creature, Ability.BOMB)
			if bomb_remaining == 0:
				set_selected_ability(Ability.NONE)
			return true
	return false


func _is_valid_target(creature: Creature) -> bool:
	if not is_instance_valid(creature) or creature.current_state != Creature.State.WALKING:
		return false
	match selected_ability:
		Ability.DIG:
			return dig_target_validator.is_null() or bool(dig_target_validator.call(creature))
		Ability.BUILD:
			return build_target_validator.is_null() or bool(build_target_validator.call(creature))
		Ability.BLOCK:
			return true
		Ability.BOMB:
			return bomb_target_validator.is_null() or bool(bomb_target_validator.call(creature))
	return false


func _set_hovered_creature(creature: Creature) -> void:
	if hovered_creature == creature:
		return
	if is_instance_valid(hovered_creature):
		hovered_creature.set_target_highlighted(false)
	hovered_creature = creature
	if is_instance_valid(hovered_creature):
		hovered_creature.set_target_highlighted(true)
