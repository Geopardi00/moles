class_name SimulationHUD
extends CanvasLayer

const AbilityAssignmentControllerScript = preload("res://scripts/gameplay/ability_assignment_controller.gd")

signal restart_requested
signal level_select_requested

@export var simulation_controller_path: NodePath

@onready var level_name_label: Label = %LevelNameLabel
@onready var goal_label: Label = %GoalLabel
@onready var total_label: Label = %TotalLabel
@onready var saved_label: Label = %SavedLabel
@onready var lost_label: Label = %LostLabel
@onready var simulation_label: Label = %SimulationLabel
@onready var pause_button: Button = %PauseButton
@onready var speed_1_button: Button = %Speed1Button
@onready var speed_2_button: Button = %Speed2Button
@onready var speed_4_button: Button = %Speed4Button
@onready var restart_button: Button = %RestartButton
@onready var level_select_button: Button = %LevelSelectButton
@onready var dig_button: Button = %DigButton
@onready var dig_inventory_label: Label = %DigInventoryLabel
@onready var mine_button: Button = %MineButton
@onready var mine_inventory_label: Label = %MineInventoryLabel
@onready var build_button: Button = %BuildButton
@onready var build_inventory_label: Label = %BuildInventoryLabel
@onready var block_button: Button = %BlockButton
@onready var block_inventory_label: Label = %BlockInventoryLabel
@onready var bomb_button: Button = %BombButton
@onready var bomb_inventory_label: Label = %BombInventoryLabel
@onready var result_overlay: Control = %ResultOverlay
@onready var result_title: Label = %ResultTitle
@onready var result_medal: Label = %ResultMedal
@onready var result_details: Label = %ResultDetails
@onready var result_restart_button: Button = %ResultRestartButton
@onready var result_level_select_button: Button = %ResultLevelSelectButton

var _controller: SimulationController
var _level_controller: LevelController
var _ability_controller: AbilityAssignmentControllerScript
var _paused: bool = false
var _speed: float = 1.0
var _level_finished: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_controller = get_node_or_null(simulation_controller_path) as SimulationController
	if _controller == null:
		push_error("SimulationHUD requires a SimulationController path.")
		return

	_controller.pause_changed.connect(_on_pause_changed)
	_controller.speed_changed.connect(_on_speed_changed)
	pause_button.pressed.connect(_controller.toggle_pause)
	speed_1_button.pressed.connect(_controller.set_speed.bind(1.0))
	speed_2_button.pressed.connect(_controller.set_speed.bind(2.0))
	speed_4_button.pressed.connect(_controller.set_speed.bind(4.0))
	restart_button.pressed.connect(_request_restart)
	result_restart_button.pressed.connect(_request_restart)
	level_select_button.pressed.connect(_request_level_select)
	result_level_select_button.pressed.connect(_request_level_select)

	_paused = get_tree().paused
	_speed = _controller.speed_multiplier
	result_overlay.visible = false
	_refresh_simulation_display()
	_refresh_ability_display()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("level_select"):
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		_request_level_select()
	elif event.is_action_pressed("level_restart"):
		# Restart reloads the scene synchronously, so consume this event while the
		# current HUD still has a valid viewport.
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		_request_restart()


func bind_level(controller: LevelController) -> void:
	_level_controller = controller
	_level_controller.progress_changed.connect(_on_progress_changed)
	_level_controller.status_changed.connect(_on_level_status_changed)

	var definition := _level_controller.definition
	level_name_label.text = definition.display_name
	goal_label.text = "Medals: Bronze %d | Silver %d | Gold %d" % [
		definition.bronze_rescue_count,
		definition.silver_rescue_count,
		definition.gold_rescue_count,
	]
	_on_progress_changed(
		_level_controller.spawned_count,
		definition.total_creatures,
		_level_controller.saved_count,
		definition.get_required_rescue_count(),
		_level_controller.lost_count
	)
	_on_level_status_changed(_level_controller.status)


func bind_abilities(controller: AbilityAssignmentControllerScript) -> void:
	_ability_controller = controller
	_ability_controller.selected_ability_changed.connect(_on_selected_ability_changed)
	_ability_controller.inventory_changed.connect(_on_ability_inventory_changed)
	dig_button.pressed.connect(_ability_controller.toggle_dig_selection)
	mine_button.pressed.connect(_ability_controller.toggle_mine_selection)
	build_button.pressed.connect(_ability_controller.toggle_build_selection)
	block_button.pressed.connect(_ability_controller.toggle_block_selection)
	bomb_button.pressed.connect(_ability_controller.toggle_bomb_selection)
	_refresh_ability_display()


func _on_progress_changed(
	spawned: int,
	total: int,
	saved: int,
	required: int,
	lost: int
) -> void:
	total_label.text = "Spawned: %d / %d" % [spawned, total]
	saved_label.text = "Saved: %d / %d" % [saved, required]
	lost_label.text = "Lost: %d" % lost


func _on_level_status_changed(status: LevelController.Status) -> void:
	var is_finished := status == LevelController.Status.COMPLETED or status == LevelController.Status.FAILED
	_level_finished = is_finished
	pause_button.disabled = is_finished
	speed_1_button.disabled = is_finished
	speed_2_button.disabled = is_finished
	speed_4_button.disabled = is_finished
	result_overlay.visible = is_finished
	_refresh_ability_display()

	if status == LevelController.Status.COMPLETED:
		result_title.text = "LEVEL COMPLETE"
		result_medal.text = "%s MEDAL" % LevelDefinition.get_medal_display_name(
			_level_controller.earned_medal
		)
		result_medal.modulate = _get_medal_color(_level_controller.earned_medal)
		result_details.text = "Saved %d of %d creatures." % [
			_level_controller.saved_count,
			_level_controller.definition.total_creatures,
		]
	elif status == LevelController.Status.FAILED:
		result_title.text = "LEVEL FAILED"
		result_medal.text = LevelDefinition.get_medal_display_name(
			LevelDefinition.MedalTier.NONE
		)
		result_medal.modulate = Color(0.68, 0.7, 0.72)
		result_details.text = "Saved %d. Bronze requires %d." % [
			_level_controller.saved_count,
			_level_controller.get_required_rescue_count(),
		]


func _get_medal_color(medal: LevelDefinition.MedalTier) -> Color:
	match medal:
		LevelDefinition.MedalTier.BRONZE:
			return Color(0.8, 0.5, 0.28)
		LevelDefinition.MedalTier.SILVER:
			return Color(0.78, 0.82, 0.88)
		LevelDefinition.MedalTier.GOLD:
			return Color(0.95, 0.78, 0.22)
		_:
			return Color.WHITE


func _on_pause_changed(is_paused: bool) -> void:
	_paused = is_paused
	_refresh_simulation_display()


func _on_speed_changed(multiplier: float) -> void:
	_speed = multiplier
	_refresh_simulation_display()


func _on_selected_ability_changed(_ability: int) -> void:
	_refresh_ability_display()


func _on_ability_inventory_changed(
	_dig_remaining: int,
	_mine_remaining: int,
	_build_remaining: int,
	_block_remaining: int,
	_bomb_remaining: int
) -> void:
	_refresh_ability_display()


func _refresh_ability_display() -> void:
	var dig_remaining: int = int(_ability_controller.dig_remaining) if _ability_controller != null else 0
	var mine_remaining: int = int(_ability_controller.mine_remaining) if _ability_controller != null else 0
	var build_remaining: int = int(_ability_controller.build_remaining) if _ability_controller != null else 0
	var block_remaining: int = int(_ability_controller.block_remaining) if _ability_controller != null else 0
	var bomb_remaining: int = int(_ability_controller.bomb_remaining) if _ability_controller != null else 0
	var dig_selected: bool = (
		_ability_controller != null
		and _ability_controller.is_dig_selected()
	)
	var mine_selected: bool = (
		_ability_controller != null
		and _ability_controller.is_mine_selected()
	)
	var build_selected: bool = (
		_ability_controller != null
		and _ability_controller.is_build_selected()
	)
	var block_selected: bool = (
		_ability_controller != null
		and _ability_controller.is_block_selected()
	)
	var bomb_selected: bool = (
		_ability_controller != null
		and _ability_controller.is_bomb_selected()
	)
	dig_inventory_label.text = "DIG remaining: %d" % dig_remaining
	dig_button.button_pressed = dig_selected
	dig_button.disabled = _level_finished or dig_remaining <= 0
	mine_inventory_label.text = "MINE remaining: %d" % mine_remaining
	mine_button.button_pressed = mine_selected
	mine_button.disabled = _level_finished or mine_remaining <= 0
	build_inventory_label.text = "BUILD remaining: %d" % build_remaining
	build_button.button_pressed = build_selected
	build_button.disabled = _level_finished or build_remaining <= 0
	block_inventory_label.text = "BLOCK remaining: %d" % block_remaining
	block_button.button_pressed = block_selected
	block_button.disabled = _level_finished or block_remaining <= 0
	bomb_inventory_label.text = "BOMB remaining: %d" % bomb_remaining
	bomb_button.button_pressed = bomb_selected
	bomb_button.disabled = _level_finished or bomb_remaining <= 0


func _refresh_simulation_display() -> void:
	var state_text := "PAUSED" if _paused else "RUNNING"
	simulation_label.text = "%s  •  %d×" % [state_text, int(_speed)]
	pause_button.text = "Resume [P]" if _paused else "Pause [P]"
	speed_1_button.button_pressed = is_equal_approx(_speed, 1.0)
	speed_2_button.button_pressed = is_equal_approx(_speed, 2.0)
	speed_4_button.button_pressed = is_equal_approx(_speed, 4.0)


func _request_restart() -> void:
	restart_requested.emit()


func _request_level_select() -> void:
	level_select_requested.emit()
