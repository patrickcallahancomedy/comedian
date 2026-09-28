extends Control

const BASE_SPEED := 25.0
const SPEED_MULTIPLIERS := [1.0, 10.0, 100.0, 5000.0]
const SPEED_LABELS := ["1×", "10×", "100×", "MAX"]
const CAR_COLOR := Color(1.0, 0.92, 0.08)
const CAR_OUTLINE := Color(0.02, 0.02, 0.02)
const CAR_RADIUS := 8.0
const HIGHWAY_EXIT_PREP_DISTANCE := 60.0

var route: Array = []
var route_index := 0
var world_position := Vector2.ZERO
var running := false
var finished := false
var speed_index := 0

@onready var map = $"../Map"
@onready var run_button: Button = $"../DriveBox/Layout/RunButton"
@onready var reset_button: Button = $"../DriveBox/Layout/ResetButton"
@onready var speed_button: Button = $"../DriveBox/Layout/SpeedButton"
@onready var status_label: Label = $"../DriveBox/Layout/StatusLabel"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	run_button.pressed.connect(_run)
	reset_button.pressed.connect(_reset)
	speed_button.pressed.connect(_cycle_speed)
	map.map_generated.connect(_reset)
	call_deferred("_reset")


func _process(delta: float) -> void:
	# Keep the overlay synced even while idle if the map view changes.
	queue_redraw()

	if not running or route.size() < 2:
		return

	var remaining: float = (
		BASE_SPEED
		* float(SPEED_MULTIPLIERS[speed_index])
		* delta
	)

	while remaining > 0.0 and running:
		if route_index >= route.size() - 1:
			_finish()
			break

		var next_id: int = int(route[route_index + 1])
		var target := Vector2(map.generator.nodes[next_id])
		var distance := world_position.distance_to(target)

		if distance <= 0.0001:
			world_position = target
			route_index += 1
			continue

		if remaining >= distance:
			world_position = target
			remaining -= distance
			route_index += 1

			if route_index >= route.size() - 1:
				_finish()
		else:
			world_position = world_position.move_toward(target, remaining)
			remaining = 0.0

	queue_redraw()


func _draw() -> void:
	if route.is_empty():
		return

	var display_position: Vector2 = _display_world_position()
	var screen: Vector2 = map.world_to_screen(display_position)
	var radius: float = CAR_RADIUS

	draw_circle(screen, radius + 3.0, CAR_OUTLINE)
	draw_circle(screen, radius, CAR_COLOR)
	draw_circle(screen, 2.2, Color.WHITE)

	var font := get_theme_default_font()
	draw_string(
		font,
		screen + Vector2(11.0, 4.0),
		"CAR",
		HORIZONTAL_ALIGNMENT_LEFT,
		30.0,
		11,
		Color.WHITE
	)


func _display_world_position() -> Vector2:
	if route_index >= route.size() - 1:
		return world_position

	var current_id: int = int(route[route_index])
	var next_id: int = int(route[route_index + 1])
	if (
		map.generator.edge_class(current_id, next_id)
		!= map.generator.RoadClass.HIGHWAY
	):
		return world_position

	var exit_merge_id: int = _next_auxiliary_merge_id()
	if exit_merge_id < 0:
		return world_position

	var highway_a: Vector2 = Vector2(
		map.generator.nodes[int(map.generator.highway_nodes[0])]
	)
	var highway_b: Vector2 = Vector2(
		map.generator.nodes[int(map.generator.highway_nodes[1])]
	)
	var exit_merge: Vector2 = Vector2(
		map.generator.nodes[exit_merge_id]
	)
	var horizontal: bool = is_equal_approx(highway_a.y, highway_b.y)

	var center_axis: float = highway_a.y if horizontal else highway_a.x
	var merge_axis: float = exit_merge.y if horizontal else exit_merge.x
	var side: float = signf(merge_axis - center_axis)
	if is_zero_approx(side):
		return world_position

	var remaining_to_exit: float = (
		absf(exit_merge.x - world_position.x)
		if horizontal
		else absf(exit_merge.y - world_position.y)
	)
	var lane_progress: float = clampf(
		1.0 - (
			remaining_to_exit
			/ HIGHWAY_EXIT_PREP_DISTANCE
		),
		0.0,
		1.0
	)
	var lane_offset: float = (
		float(map.generator.HIGHWAY_LANE_SPACING)
		* lane_progress
		* side
	)

	if horizontal:
		return world_position + Vector2(0.0, lane_offset)
	return world_position + Vector2(lane_offset, 0.0)


func _next_auxiliary_merge_id() -> int:
	for future_index in range(route_index + 1, route.size()):
		var node_id: int = int(route[future_index])
		if map.generator.auxiliary_merge_nodes.has(node_id):
			return node_id
	return -1


func _run() -> void:
	if route.is_empty():
		_reset()

	if route.size() < 2:
		return

	map.show_whole_world()
	running = true
	finished = false
	status_label.text = "RUNNING"
	queue_redraw()


func _reset() -> void:
	running = false
	finished = false
	route_index = 0

	if map.generator.home_node < 0 or map.generator.venue_access_node < 0:
		route = []
		status_label.text = "NO ROUTE"
		queue_redraw()
		return

	route = map.generator.shortest_path(
		map.generator.home_node,
		map.generator.venue_access_node
	)

	if route.is_empty():
		status_label.text = "NO ROUTE"
		queue_redraw()
		return

	world_position = Vector2(map.generator.nodes[int(route[0])])
	status_label.text = "READY AT A"
	queue_redraw()


func _cycle_speed() -> void:
	speed_index = (speed_index + 1) % SPEED_MULTIPLIERS.size()
	speed_button.text = "SPEED  %s" % SPEED_LABELS[speed_index]


func _finish() -> void:
	running = false
	finished = true
	status_label.text = "ARRIVED"
	queue_redraw()
