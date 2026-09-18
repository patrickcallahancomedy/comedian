extends GameModule

## DRIVE — smallest playable version.
##
## One verb: DRIVE.
## - LEFT / RIGHT dodges traffic on the current block.
## - Near an intersection, LEFT / RIGHT chooses the turn.
## - The minimap shows the complete route from the start.
##
## Keep this small. Add new effects only after this loop is fun.

const ROUTE_TURNS := [1, -1, 1, -1] # RIGHT, LEFT, RIGHT, LEFT
const TURN_ZONE := 0.72

const OBSTACLE_BLOCKS := [
	[Vector2(-1, 0.28), Vector2(1, 0.52)],
	[Vector2(1, 0.30), Vector2(-1, 0.56)],
	[Vector2(-1, 0.24), Vector2(-1, 0.50)],
	[Vector2(1, 0.27), Vector2(-1, 0.54)],
	[Vector2(-1, 0.32), Vector2(1, 0.60)],
]

@export_category("Drive Tuning")
@export_range(1.5, 4.0, 0.1) var seconds_per_block: float = 2.5
@export_range(100.0, 600.0, 10.0) var steering_speed: float = 360.0
@export_range(0.2, 1.0, 0.05) var title_seconds: float = 0.55

@export_category("Comedy Night Clock")
@export var departure_clock_minutes: int = 19 * 60 + 16
@export var signup_close_clock_minutes: int = 19 * 60 + 45

@onready var road: DriveRoad = $Road
@onready var minimap: DriveMinimap = $HUD/MiniMapPanel/Margin/MiniMap
@onready var player_car: TextureRect = $Road/PlayerCar
@onready var left_button: Button = $Controls/LeftButton
@onready var right_button: Button = $Controls/RightButton
@onready var result_panel: PanelContainer = $ResultPanel
@onready var result_label: Label = $ResultPanel/Margin/Layout/ResultLabel
@onready var continue_button: Button = $ResultPanel/Margin/Layout/ContinueButton

var block_index: int = 0
var block_progress: float = 0.0
var lane: int = -1
var queued_turn: int = 0
var waiting_for_turn: bool = false

var collisions: int = 0
var missed_turns: int = 0
var elapsed_seconds: float = 0.0
var finished: bool = false
var started: bool = false

var checked_obstacles: Dictionary = {}


func _ready() -> void:
	module_id = "drive"
	if next_route_id.is_empty():
		next_route_id = "venue"

	result_panel.hide()
	left_button.pressed.connect(_on_left_pressed)
	right_button.pressed.connect(_on_right_pressed)
	continue_button.pressed.connect(_finish_and_continue)

	# DRIVE starts immediately. No intro overlay can block the controls.
	started = true
	left_button.disabled = false
	right_button.disabled = false
	_refresh_visuals()


func _process(delta: float) -> void:
	if not started or finished:
		return

	elapsed_seconds += delta

	var previous_progress := block_progress
	if not waiting_for_turn:
		block_progress = minf(1.0, block_progress + delta / seconds_per_block)

	_check_obstacles(previous_progress, block_progress)

	if block_progress >= 1.0:
		_resolve_end_of_block()

	_update_player_position(delta)
	_refresh_visuals()


func _on_left_pressed() -> void:
	_handle_direction(-1)


func _on_right_pressed() -> void:
	_handle_direction(1)


func _handle_direction(direction: int) -> void:
	if finished or not started:
		return

	if waiting_for_turn or _is_turn_zone():
		queued_turn = direction
		if waiting_for_turn:
			_resolve_end_of_block()
	else:
		lane = direction


func _is_turn_zone() -> bool:
	return block_index < ROUTE_TURNS.size() and block_progress >= TURN_ZONE


func _resolve_end_of_block() -> void:
	# Final straight reaches the destination.
	if block_index >= ROUTE_TURNS.size():
		_finish_drive()
		return

	if queued_turn == 0:
		waiting_for_turn = true
		block_progress = 0.99
		return

	waiting_for_turn = false
	var correct_turn := int(ROUTE_TURNS[block_index])

	if queued_turn != correct_turn:
		missed_turns += 1
		GameState.change_stress(2)

		# Small, visible retry instead of a hidden penalty system.
		block_progress = TURN_ZONE
		queued_turn = 0
		return

	block_index += 1
	block_progress = 0.0
	queued_turn = 0
	checked_obstacles.clear()


func _check_obstacles(previous_progress: float, new_progress: float) -> void:
	var obstacles := _current_obstacles()

	for index in range(obstacles.size()):
		if checked_obstacles.has(index):
			continue

		var obstacle := obstacles[index]
		var obstacle_progress := obstacle.y

		if previous_progress < obstacle_progress and new_progress >= obstacle_progress:
			checked_obstacles[index] = true

			if lane == int(obstacle.x):
				collisions += 1
				GameState.change_stress(1)
				GameState.change_car_condition(-1)
				_flash_car()


func _flash_car() -> void:
	player_car.modulate = Color(1.0, 0.55, 0.55, 1.0)
	var tween := create_tween()
	tween.tween_property(player_car, "modulate", Color.WHITE, 0.18)


func _current_obstacles() -> Array[Vector2]:
	var output: Array[Vector2] = []
	var source: Array = OBSTACLE_BLOCKS[mini(block_index, OBSTACLE_BLOCKS.size() - 1)]

	for item in source:
		output.append(item)

	return output


func _update_player_position(delta: float) -> void:
	var target_x := road.get_lane_x(lane) - player_car.size.x * 0.5
	var target_y := road.get_player_y() - player_car.size.y * 0.5

	player_car.position.x = move_toward(
		player_car.position.x,
		target_x,
		steering_speed * delta
	)
	player_car.position.y = target_y


func _refresh_visuals() -> void:
	var upcoming_turn := 0
	if block_index < ROUTE_TURNS.size():
		upcoming_turn = int(ROUTE_TURNS[block_index])

	road.set_drive_state(
		block_progress,
		lane,
		queued_turn,
		upcoming_turn,
		_current_obstacles()
	)
	minimap.set_route_progress(
		mini(block_index, DriveMinimap.ROUTE.size() - 2),
		block_progress
	)


func _finish_drive() -> void:
	if finished:
		return

	finished = true
	left_button.disabled = true
	right_button.disabled = true

	GameState.change_energy(-1)
	GameState.change_gas(-2)
	GameState.increment_history("drives_completed")

	var game_minutes := maxi(1, ceili(elapsed_seconds))
	var arrival_clock_minutes := departure_clock_minutes + game_minutes
	var minutes_before_signup := signup_close_clock_minutes - arrival_clock_minutes

	GameState.night_context["arrival_minutes_before_signup"] = minutes_before_signup
	GameState.night_context["arrival_clock_minutes"] = arrival_clock_minutes
	GameState.night_context["drive_collisions"] = collisions
	GameState.night_context["drive_missed_turns"] = missed_turns

	result_label.text = "YOU MADE IT.\n\n%d hit%s. %d missed turn%s." % [
		collisions,
		"" if collisions == 1 else "s",
		missed_turns,
		"" if missed_turns == 1 else "s",
	]
	result_panel.show()


func _finish_and_continue() -> void:
	finish_module({
		"status": "drive_complete",
		"collisions": collisions,
		"missed_turns": missed_turns,
		"real_drive_seconds": snappedf(elapsed_seconds, 0.1),
	})
