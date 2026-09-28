extends Control

const BASE_SPEED := 25.0
const SPEED_MULTIPLIERS := [1.0, 10.0, 100.0, 5000.0]
const SPEED_LABELS := ["1×", "10×", "100×", "MAX"]
const CAR_COLOR := Color(1.0, 0.92, 0.08)
const CAR_OUTLINE := Color(0.02, 0.02, 0.02)
const CAR_RADIUS := 8.0
const LANE_MERGE_DISTANCE := 40.0

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

		var current_id: int = int(route[route_index])
		var next_id: int = int(route[route_index + 1])
		var target: Vector2 = Vector2(map.generator.nodes[next_id])

		# Hidden links only connect the logical highway spine to its visual
		# lanes. They are routing metadata, not roads the car should visibly
		# drive across.
		if map.generator.edge_class(current_id, next_id) < 0:
			world_position = target
			route_index += 1
			continue

		var distance: float = world_position.distance_to(target)

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
	var road_class: int = map.generator.edge_class(current_id, next_id)

	if road_class == map.generator.RoadClass.HIGHWAY:
		return _highway_display_position()
	if road_class == map.generator.RoadClass.RAMP:
		return _ramp_display_position()

	return world_position


func _highway_display_position() -> Vector2:
	var merge_indices: Array = _auxiliary_merge_route_indices()
	if merge_indices.size() < 2:
		return world_position

	var entry_merge_index: int = int(merge_indices[0])
	var exit_merge_index: int = int(merge_indices[-1])
	if entry_merge_index + 1 >= route.size() or exit_merge_index <= 0:
		return world_position

	var entry_lane_id: int = int(route[entry_merge_index])
	var exit_lane_id: int = int(route[exit_merge_index])
	var entry_center_id: int = int(route[entry_merge_index + 1])
	var exit_center_id: int = int(route[exit_merge_index - 1])

	var entry_lane: Vector2 = Vector2(map.generator.nodes[entry_lane_id])
	var exit_lane: Vector2 = Vector2(map.generator.nodes[exit_lane_id])
	var entry_center: Vector2 = Vector2(map.generator.nodes[entry_center_id])
	var exit_center: Vector2 = Vector2(map.generator.nodes[exit_center_id])
	var horizontal: bool = _highway_is_horizontal()

	var entry_side: float = signf(
		(entry_lane.y - entry_center.y)
		if horizontal
		else (entry_lane.x - entry_center.x)
	)
	var exit_side: float = signf(
		(exit_lane.y - exit_center.y)
		if horizontal
		else (exit_lane.x - exit_center.x)
	)
	if is_zero_approx(entry_side) or is_zero_approx(exit_side):
		return world_position

	var start_axis: float = entry_center.x if horizontal else entry_center.y
	var end_axis: float = exit_center.x if horizontal else exit_center.y
	var current_axis: float = world_position.x if horizontal else world_position.y
	var denominator: float = end_axis - start_axis
	var progress := 0.0
	if not is_zero_approx(denominator):
		progress = clampf(
			(current_axis - start_axis) / denominator,
			0.0,
			1.0
		)

	# Stay in the entry-side outer lane, make any needed lane change through
	# the middle of the highway, and be fully in the exit-side outer lane
	# well before the pink exit.
	var lane_change: float = smoothstep(0.35, 0.65, progress)
	var side: float = lerpf(entry_side, exit_side, lane_change)
	var offset: float = float(map.generator.HIGHWAY_LANE_SPACING) * side

	if horizontal:
		return Vector2(world_position.x, entry_center.y + offset)
	return Vector2(entry_center.x + offset, world_position.y)


func _ramp_display_position() -> Vector2:
	var merge_indices: Array = _auxiliary_merge_route_indices()
	if merge_indices.size() < 2:
		return world_position

	var entry_merge_index: int = int(merge_indices[0])
	var exit_merge_index: int = int(merge_indices[-1])
	var horizontal: bool = _highway_is_horizontal()

	# Entry ramp: the pink lane gradually merges into the adjacent outer
	# highway lane during the final stretch, rather than crossing lanes at
	# the hidden graph junction.
	if route_index < entry_merge_index:
		var highway_end_index := entry_merge_index - 1
		if highway_end_index < 0:
			return world_position
		var highway_end: Vector2 = Vector2(
			map.generator.nodes[int(route[highway_end_index])]
		)
		var lane_merge: Vector2 = Vector2(
			map.generator.nodes[int(route[entry_merge_index])]
		)
		var remaining: float = (
			absf(highway_end.x - world_position.x)
			if horizontal
			else absf(highway_end.y - world_position.y)
		)
		var blend: float = clampf(
			1.0 - remaining / LANE_MERGE_DISTANCE,
			0.0,
			1.0
		)
		if horizontal:
			return Vector2(
				world_position.x,
				lerpf(world_position.y, lane_merge.y, blend)
			)
		return Vector2(
			lerpf(world_position.x, lane_merge.x, blend),
			world_position.y
		)

	# Exit ramp: start on the adjacent outer highway lane and gradually move
	# onto the pink lane over the first stretch of the ramp.
	if route_index > exit_merge_index:
		var highway_end_index := exit_merge_index + 1
		if highway_end_index >= route.size():
			return world_position
		var highway_end: Vector2 = Vector2(
			map.generator.nodes[int(route[highway_end_index])]
		)
		var lane_merge: Vector2 = Vector2(
			map.generator.nodes[int(route[exit_merge_index])]
		)
		var traveled: float = (
			absf(world_position.x - highway_end.x)
			if horizontal
			else absf(world_position.y - highway_end.y)
		)
		var blend: float = clampf(
			traveled / LANE_MERGE_DISTANCE,
			0.0,
			1.0
		)
		if horizontal:
			return Vector2(
				world_position.x,
				lerpf(lane_merge.y, world_position.y, blend)
			)
		return Vector2(
			lerpf(lane_merge.x, world_position.x, blend),
			world_position.y
		)

	return world_position


func _auxiliary_merge_route_indices() -> Array:
	var indices: Array = []
	for index in range(route.size()):
		var node_id: int = int(route[index])
		if map.generator.auxiliary_merge_nodes.has(node_id):
			indices.append(index)
	return indices


func _highway_is_horizontal() -> bool:
	if map.generator.highway_nodes.size() != 2:
		return true
	var a: Vector2i = map.generator.nodes[
		int(map.generator.highway_nodes[0])
	]
	var b: Vector2i = map.generator.nodes[
		int(map.generator.highway_nodes[1])
	]
	return a.y == b.y


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
