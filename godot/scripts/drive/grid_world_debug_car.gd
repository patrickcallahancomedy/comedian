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
var wrap_route_index := -1
var drive_forward := Vector2.UP

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

		# The highway is one-way. When the route reaches the forward end,
		# wrap to the opposite end as though the highway continues off-map.
		if route_index == wrap_route_index:
			world_position = target
			route_index += 1
			continue

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

	_sync_drive_camera()
	queue_redraw()


func _draw() -> void:
	if route.is_empty():
		return

	var screen: Vector2 = (
		map.drive_camera_screen_position()
		if map.drive_camera_enabled
		else map.world_to_screen(_display_world_position())
	)
	var radius: float = CAR_RADIUS

	# Fixed upward-facing debug car. The world moves and rotates beneath it.
	var nose := screen + Vector2(0.0, -radius - 3.0)
	var left := screen + Vector2(-radius, radius)
	var right := screen + Vector2(radius, radius)
	draw_colored_polygon(
		PackedVector2Array([nose, left, right]),
		CAR_OUTLINE
	)
	draw_colored_polygon(
		PackedVector2Array([
			screen + Vector2(0.0, -radius),
			screen + Vector2(-radius + 2.5, radius - 2.0),
			screen + Vector2(radius - 2.5, radius - 2.0),
		]),
		CAR_COLOR
	)
	draw_circle(screen + Vector2(0.0, 2.0), 2.0, Color.WHITE)

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
	var entry_center_index: int = entry_merge_index + 1
	var exit_center_index: int = exit_merge_index - 1
	var entry_center_id: int = int(route[entry_center_index])
	var exit_center_id: int = int(route[exit_center_index])

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

	# Progress follows the actual one-way route indices, so a highway wrap
	# does not make the lane-change interpolation run backward.
	var route_span: float = maxf(
		1.0,
		float(exit_center_index - entry_center_index)
	)
	var segment_fraction := 0.0
	if route_index >= entry_center_index and route_index < exit_center_index:
		var current_id: int = int(route[route_index])
		var next_id: int = int(route[route_index + 1])
		if route_index != wrap_route_index:
			var current_point: Vector2 = Vector2(
				map.generator.nodes[current_id]
			)
			var next_point: Vector2 = Vector2(
				map.generator.nodes[next_id]
			)
			var segment_length: float = current_point.distance_to(next_point)
			if segment_length > 0.0001:
				segment_fraction = clampf(
					current_point.distance_to(world_position)
					/ segment_length,
					0.0,
					1.0
				)

	var progress: float = clampf(
		(
			float(route_index - entry_center_index)
			+ segment_fraction
		) / route_span,
		0.0,
		1.0
	)

	# Stay in the entry-side outer lane, make any needed lane change through
	# the middle of the one-way highway trip, and be fully in the exit-side
	# outer lane before reaching pink.
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
	return _auxiliary_merge_indices_for(route)


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


func _auxiliary_merge_indices_for(candidate_route: Array) -> Array:
	var indices: Array = []
	for index in range(candidate_route.size()):
		var node_id: int = int(candidate_route[index])
		if map.generator.auxiliary_merge_nodes.has(node_id):
			indices.append(index)
	return indices


func _build_one_way_route() -> Array:
	wrap_route_index = -1

	var base_route: Array = map.generator.shortest_path(
		map.generator.home_node,
		map.generator.venue_access_node
	)
	if base_route.is_empty() or not map.generator.uses_highway:
		return base_route

	var merge_indices: Array = _auxiliary_merge_indices_for(base_route)
	if merge_indices.size() != 2:
		return base_route

	var entry_merge_index: int = int(merge_indices[0])
	var exit_merge_index: int = int(merge_indices[1])
	if (
		entry_merge_index + 1 >= base_route.size()
		or exit_merge_index <= 0
	):
		return base_route

	var entry_center_id: int = int(base_route[entry_merge_index + 1])
	var exit_center_id: int = int(base_route[exit_merge_index - 1])
	var spine: Array = _directed_highway_spine_nodes()
	var entry_spine_index: int = spine.find(entry_center_id)
	var exit_spine_index: int = spine.find(exit_center_id)

	if entry_spine_index < 0 or exit_spine_index < 0:
		return base_route

	# Exit already lies ahead in the legal highway direction.
	if exit_spine_index >= entry_spine_index:
		return base_route

	# Exit lies behind us. Continue forward to the end, wrap to the highway
	# start, then keep moving forward until the exit comes around again.
	var result: Array = []
	for index in range(entry_merge_index + 2):
		result.append(base_route[index])

	for index in range(entry_spine_index + 1, spine.size()):
		result.append(spine[index])

	wrap_route_index = result.size() - 1

	for index in range(0, exit_spine_index + 1):
		result.append(spine[index])

	for index in range(exit_merge_index, base_route.size()):
		result.append(base_route[index])

	return result


func _directed_highway_spine_nodes() -> Array:
	var spine: Array = []
	for key in map.generator.edge_classes.keys():
		if (
			int(map.generator.edge_classes[key])
			!= map.generator.RoadClass.HIGHWAY
		):
			continue
		var ids: Array = str(key).split(":")
		if ids.size() != 2:
			continue
		for id_value in ids:
			var node_id := int(id_value)
			if not spine.has(node_id):
				spine.append(node_id)

	var horizontal: bool = _highway_is_horizontal()
	spine.sort_custom(func(a, b):
		var pa: Vector2i = map.generator.nodes[int(a)]
		var pb: Vector2i = map.generator.nodes[int(b)]
		return pa.x < pb.x if horizontal else pa.y < pb.y
	)

	if _highway_travel_sign() < 0:
		spine.reverse()

	return spine


func _highway_travel_sign() -> int:
	var neighborhood_center := Vector2i(
		map.generator.neighborhood_rect.get_center()
	)
	var city_center := Vector2i(
		map.generator.city_rect.get_center()
	)
	if _highway_is_horizontal():
		return 1 if city_center.x >= neighborhood_center.x else -1
	return 1 if city_center.y >= neighborhood_center.y else -1


func _sync_drive_camera() -> void:
	if route.is_empty():
		return

	var next_forward := _current_forward_direction()
	if next_forward.length_squared() > 0.0001:
		drive_forward = next_forward.normalized()

	map.set_drive_camera(
		_display_world_position(),
		drive_forward
	)


func _current_forward_direction() -> Vector2:
	if route.size() < 2:
		return drive_forward

	for index in range(route_index, route.size() - 1):
		if index == wrap_route_index:
			continue

		var a: int = int(route[index])
		var b: int = int(route[index + 1])
		if map.generator.edge_class(a, b) < 0:
			continue

		var delta := Vector2(
			map.generator.nodes[b] - map.generator.nodes[a]
		)
		if delta.length_squared() > 0.0001:
			return delta.normalized()

	return drive_forward


func _run() -> void:
	if route.is_empty():
		_reset()

	if route.size() < 2:
		return

	_sync_drive_camera()
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

	route = _build_one_way_route()

	if route.is_empty():
		status_label.text = "NO ROUTE"
		queue_redraw()
		return

	world_position = Vector2(map.generator.nodes[int(route[0])])
	drive_forward = _current_forward_direction()
	_sync_drive_camera()
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
