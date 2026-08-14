class_name SimulationHUD
extends CanvasLayer

@export var simulation_controller_path: NodePath

@onready var total_label: Label = %TotalLabel
@onready var saved_label: Label = %SavedLabel
@onready var lost_label: Label = %LostLabel
@onready var simulation_label: Label = %SimulationLabel
@onready var pause_button: Button = %PauseButton
@onready var speed_1_button: Button = %Speed1Button
@onready var speed_2_button: Button = %Speed2Button
@onready var speed_4_button: Button = %Speed4Button

var _controller: SimulationController
var _paused: bool = false
var _speed: float = 1.0
var _expected_total: int = 0


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

	_paused = get_tree().paused
	_speed = _controller.speed_multiplier
	_refresh_simulation_display()


func set_population(total: int, saved: int, lost: int) -> void:
	total_label.text = "Spawned: %d / %d" % [total, _expected_total]
	saved_label.text = "Saved: %d" % saved
	lost_label.text = "Lost: %d" % lost


func set_expected_total(value: int) -> void:
	_expected_total = value


func _on_pause_changed(is_paused: bool) -> void:
	_paused = is_paused
	_refresh_simulation_display()


func _on_speed_changed(multiplier: float) -> void:
	_speed = multiplier
	_refresh_simulation_display()


func _refresh_simulation_display() -> void:
	var state_text := "PAUSED" if _paused else "RUNNING"
	simulation_label.text = "%s  •  %d×" % [state_text, int(_speed)]
	pause_button.text = "Resume [P]" if _paused else "Pause [P]"
	speed_1_button.button_pressed = is_equal_approx(_speed, 1.0)
	speed_2_button.button_pressed = is_equal_approx(_speed, 2.0)
	speed_4_button.button_pressed = is_equal_approx(_speed, 4.0)
