extends Control

## First playable pass for the procedural 500x500 driving world.
## The generated graph stays authoritative; this script only drives through it.

signal trip_finished(result: Dictionary)

const GENERATOR = preload("res://scripts/drive/grid_world_generator.gd")

const PAGE_BG := Color(0.055, 0.06, 0.065)
const TERRAIN_COLOR := Color(0.23, 0.32, 0.20)
const TERRAIN_GRID := Color(1.0, 1.0, 1.0, 0.025)
const ROAD_COLOR := Color(0.115, 0.125, 0.14)
const CITY_ROAD_COLOR := Color(0.10, 0.11, 0.125)
const CONNECTOR_COLOR := Color(0.13, 0.14, 0.155)
const HIGHWAY_COLOR := Color(0.105, 0.115, 0.13)
const HIGHWAY_SHOULDER := Color(0.20, 0.21, 0.22)
const HIGHWAY_MARKING := Color(0.94, 0.93, 0.87, 0.88)
const ROUTE_SHADOW := Color(0.02, 0.08, 0.18, 0.55)
const ROUTE_BLUE := Color(0.10, 0.42, 0.96, 0.98)
const VENUE_FILL := Color(0.47, 0.20, 0.11, 0.90)
const VENUE_MARKER := Color(0.84, 0.39, 0.19)

const NEIGHBORHOOD_SPEED := 18.0
const CITY_SPEED := 28.0
const CONNECTOR_SPEED := 34.0
const HIGHWAY_SPEED := 72.0

const NEIGHBORHOOD_SCALE := 7.2
const CITY_SCALE := 4.2
const CONNECTOR_SCALE := 5.2
const HIGHWAY_SCALE := 5.0

const CAMERA_ROTATE_SPEED := 7.5
const CAMERA_SCALE_SPEED := 4.0

const HIGHWAY_LANES := 4
const HIGHWAY_EXIT_LANE := 3
const HIGHWAY_LANE_WIDTH := 22.0
const MISSED_NOTICE_SECONDS := 1.8

@export var world_seed: int = 0

var generator = GENERATOR.new()
var actual_seed: int = 0

var started: bool = false
var drive_complete: bool = false
var drive_time: float = 0.0
var missed_turns: int = 0

var current_node: int = -1
var previous_node: int = -1
var target_node: int = -1
var current_edge_class: int = -1

var visual_world_position := Vector2.ZERO
var segment_start := Vector2.ZERO
var segment_end := Vector2.ZERO
var segment_progress: float = 0.0

var heading := Vector2i.ZERO
var queued_turn: int = 0
var blocked_at_node: bool = false

var route: Array = []

var camera_rotation: float = 0.0
var camera_rotation_target: float = 0.0
var camera_scale: float = NEIGHBORHOOD_SCALE
var camera_scale_target: float = NEIGHBORHOOD_SCALE
var player_screen_center := Vector2.ZERO

var highway_lane: int = HIGHWAY_EXIT_LANE
var highway_lane_shift: float = 0.0
var highway_lane_shift_target: float = 0.0
var highway_passes: int = 0

var missed_notice_remaining: float = 0.0
var missed_notice_title: String = ""

@onready var left_button: Button = $"../TouchControls/LeftButton"
@onready var start_button: Button = $"../TouchControls/StartButton"
@onready var right_button: Button = $"../TouchControls/RightButton"
@onready var new_map_button: Button = $"../NewMapButton"
@onready var seed_label: Label = $"../SeedLabel"
@onready var gps_title: Label = $"../GpsPanel/GpsTitle"
@onready var gps_subtitle: Label = $"../GpsPanel/GpsSubtitle"
@onready var player_car: TextureRect = $"../PlayerCar"
@onready var arrival_panel: PanelContainer = $"../Arrival"
@onready var arrival_text: Label = $"../Arrival/Layout/ArrivalText"


func _ready() -> void:
	left_button.pressed.connect(_turn_left)
	start_button.pressed.connect(_start_drive)
	right_button.pressed.connect(_turn_right)
	new_map_button.pressed.connect(_new_map)
	resized.connect(_refresh_layout)

	_generate_world()
	call_deferred("_refresh_layout")


func _generate_world() -> void:
	actual_seed = world_seed
	if actual_seed == 0:
		actual_seed = (
			int(Time.get_unix_time_from_system())
			^ int(Time.get_ticks_msec())
		)

	generator.generate(actual_seed)
	seed_label.text = "SEED %d" % actual_seed
	_reset_drive()


func _new_map() -> void:
	world_seed = 0
	_generate_world()


func _reset_drive() -> void:
	started = false
	drive_complete = false
	drive_time = 0.0
	missed_turns = 0
	current_node = generator.home_node
	previous_node = -1
	target_node = -1
	current_edge_class = -1
	visual_world_position = Vector2(generator.nodes[current_node])
	segment_start = visual_world_position
	segment_end = visual_world_position
	segment_progress = 0.0
	queued_turn = 0
	blocked_at_node = false
	highway_lane = HIGHWAY_EXIT_LANE
	highway_lane_shift = _lane_shift_for(highway_lane)
	highway_lane_shift_target = highway_lane_shift
	highway_passes = 0
	missed_notice_remaining = 0.0
	missed_notice_title = ""
	route = generator.shortest_path(
		current_node,
		generator.venue_access_node
	)

	if route.size() >= 2:
		heading = _direction_between(
			current_node,
			int(route[1])
		)
	else:
		heading = Vector2i.UP

	camera_rotation_target = _rotation_for_heading(heading)
	camera_rotation = camera_rotation_target
	camera_scale_target = NEIGHBORHOOD_SCALE
	camera_scale = camera_scale_target

	start_button.show()
	start_button.text = "START"
	left_button.disabled = false
	right_button.disabled = false
	arrival_panel.hide()
	player_car.show()
	_update_gps()
	queue_redraw()


func _refresh_layout() -> void:
	player_screen_center = Vector2(
		size.x * 0.5,
		size.y * 0.56
	)

	player_car.position = (
		player_screen_center
		- player_car.size * 0.5
	)
	queue_redraw()


func _start_drive() -> void:
	if started or drive_complete:
		return

	started = true
	start_button.hide()
	_recalculate_route()

	if route.size() >= 2:
		_begin_segment(int(route[1]))
	else:
		_finish_trip()


func _process(delta: float) -> void:
	if missed_notice_remaining > 0.0:
		missed_notice_remaining = maxf(
			0.0,
			missed_notice_remaining - delta
		)
		if missed_notice_remaining <= 0.0:
			_update_gps()

	camera_rotation = lerp_angle(
		camera_rotation,
		camera_rotation_target,
		clampf(CAMERA_ROTATE_SPEED * delta, 0.0, 1.0)
	)
	camera_scale = lerpf(
		camera_scale,
		camera_scale_target,
		clampf(CAMERA_SCALE_SPEED * delta, 0.0, 1.0)
	)
	highway_lane_shift = lerpf(
		highway_lane_shift,
		highway_lane_shift_target,
		clampf(8.0 * delta, 0.0, 1.0)
	)

	if not started or drive_complete:
		queue_redraw()
		return

	drive_time += delta

	if target_node >= 0:
		_advance_segment(delta)

	queue_redraw()


func _advance_segment(delta: float) -> void:
	var length: float = segment_start.distance_to(segment_end)
	if length <= 0.001:
		_arrive_at_target()
		return

	var speed: float = _speed_for_class(current_edge_class)
	segment_progress += speed * delta / length

	if segment_progress < 1.0:
		visual_world_position = segment_start.lerp(
			segment_end,
			segment_progress
		)
		return

	if (
		current_edge_class == generator.RoadClass.HIGHWAY
		and highway_lane != HIGHWAY_EXIT_LANE
	):
		_miss_highway_exit()
		return

	visual_world_position = segment_end
	_arrive_at_target()


func _miss_highway_exit() -> void:
	missed_turns += 1
	highway_passes += 1
	missed_notice_title = "Missed exit"
	missed_notice_remaining = MISSED_NOTICE_SECONDS

	# The highway view is intentionally homogeneous, so restarting the same
	# generated straight span reads as continuing to the next opportunity
	# rather than teleporting the world.
	segment_progress = 0.0
	visual_world_position = segment_start
	gps_title.text = "Missed exit"
	gps_subtitle.text = "Move right • next exit"


func _arrive_at_target() -> void:
	var arrived_node: int = target_node
	previous_node = current_node
	current_node = arrived_node
	target_node = -1
	segment_progress = 0.0
	visual_world_position = Vector2(generator.nodes[current_node])
	blocked_at_node = false

	if current_node == generator.venue_access_node:
		_finish_trip()
		return

	_recalculate_route()
	_continue_from_node()


func _continue_from_node() -> void:
	if drive_complete:
		return

	if queued_turn != 0:
		var requested_heading: Vector2i = _rotated_heading(
			heading,
			queued_turn
		)
		var requested_neighbor: int = _neighbor_in_direction(
			current_node,
			requested_heading
		)
		queued_turn = 0

		if requested_neighbor >= 0:
			_begin_segment(requested_neighbor)
			return

	var straight_neighbor: int = _neighbor_in_direction(
		current_node,
		heading
	)
	if straight_neighbor >= 0:
		_begin_segment(straight_neighbor)
		return

	var forward_choices: Array = _non_backtracking_neighbors()
	if forward_choices.size() == 1:
		_begin_segment(int(forward_choices[0]))
		return

	blocked_at_node = true
	_update_gps()


func _begin_segment(next_node: int) -> void:
	if next_node < 0:
		return

	_recalculate_route()
	var expected_next: int = (
		int(route[1])
		if route.size() >= 2
		else -1
	)

	if (
		expected_next >= 0
		and next_node != expected_next
		and started
	):
		missed_turns += 1
		missed_notice_title = "Rerouting"
		missed_notice_remaining = 1.1

	target_node = next_node
	current_edge_class = generator.edge_class(
		current_node,
		target_node
	)
	segment_start = Vector2(generator.nodes[current_node])
	segment_end = Vector2(generator.nodes[target_node])
	segment_progress = 0.0
	visual_world_position = segment_start
	blocked_at_node = false

	var new_heading: Vector2i = _direction_between(
		current_node,
		target_node
	)
	if new_heading != Vector2i.ZERO:
		heading = new_heading
		camera_rotation_target = _rotation_for_heading(heading)

	camera_scale_target = _scale_for_class(
		current_edge_class
	)

	if current_edge_class == generator.RoadClass.HIGHWAY:
		highway_lane = HIGHWAY_EXIT_LANE
		highway_lane_shift_target = _lane_shift_for(
			highway_lane
		)
		highway_passes = 0
	else:
		highway_lane_shift_target = 0.0

	_update_gps()


func _turn_left() -> void:
	_handle_turn(-1)


func _turn_right() -> void:
	_handle_turn(1)


func _handle_turn(direction: int) -> void:
	if not started or drive_complete:
		return

	if current_edge_class == generator.RoadClass.HIGHWAY:
		_change_highway_lane(direction)
		return

	if blocked_at_node and target_node < 0:
		var desired: Vector2i = _rotated_heading(
			heading,
			direction
		)
		var neighbor: int = _neighbor_in_direction(
			current_node,
			desired
		)
		if neighbor >= 0:
			heading = desired
			camera_rotation_target = _rotation_for_heading(
				heading
			)
			_begin_segment(neighbor)
		return

	queued_turn = direction


func _change_highway_lane(direction: int) -> void:
	var requested: int = clampi(
		highway_lane + direction,
		0,
		HIGHWAY_LANES - 1
	)
	if requested == highway_lane:
		return

	highway_lane = requested
	highway_lane_shift_target = _lane_shift_for(
		highway_lane
	)
	_update_gps()


func _lane_shift_for(lane: int) -> float:
	return (
		float(lane) - (float(HIGHWAY_LANES - 1) * 0.5)
	) * HIGHWAY_LANE_WIDTH


func _recalculate_route() -> void:
	if current_node < 0:
		route = []
		return

	route = generator.shortest_path(
		current_node,
		generator.venue_access_node
	)


func _neighbor_in_direction(
	node_id: int,
	direction: Vector2i
) -> int:
	for neighbor_value in generator.adjacency[node_id]:
		var neighbor: int = int(neighbor_value)
		if _direction_between(node_id, neighbor) == direction:
			return neighbor

	return -1


func _non_backtracking_neighbors() -> Array:
	var result: Array = []

	for neighbor_value in generator.adjacency[current_node]:
		var neighbor: int = int(neighbor_value)
		if neighbor == previous_node:
			continue
		result.append(neighbor)

	return result


func _direction_between(
	from_node: int,
	to_node: int
) -> Vector2i:
	var a: Vector2i = generator.nodes[from_node]
	var b: Vector2i = generator.nodes[to_node]
	var delta: Vector2i = b - a

	if abs(delta.x) >= abs(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))


func _rotated_heading(
	source: Vector2i,
	direction: int
) -> Vector2i:
	if direction < 0:
		return Vector2i(source.y, -source.x)
	return Vector2i(-source.y, source.x)


func _rotation_for_heading(direction: Vector2i) -> float:
	if direction == Vector2i.ZERO:
		return camera_rotation_target

	return (
		-PI / 2.0
		- Vector2(direction).angle()
	)


func _speed_for_class(road_class: int) -> float:
	match road_class:
		generator.RoadClass.CITY:
			return CITY_SPEED
		generator.RoadClass.CONNECTOR:
			return CONNECTOR_SPEED
		generator.RoadClass.HIGHWAY:
			return HIGHWAY_SPEED
	return NEIGHBORHOOD_SPEED


func _scale_for_class(road_class: int) -> float:
	match road_class:
		generator.RoadClass.CITY:
			return CITY_SCALE
		generator.RoadClass.CONNECTOR:
			return CONNECTOR_SCALE
		generator.RoadClass.HIGHWAY:
			return HIGHWAY_SCALE
	return NEIGHBORHOOD_SCALE


func _update_gps() -> void:
	if missed_notice_remaining > 0.0:
		return

	if drive_complete:
		gps_title.text = "Arrived"
		gps_subtitle.text = "Venue"
		return

	if not started:
		gps_title.text = "Route ready"
		gps_subtitle.text = "Drive to the venue"
		return

	if current_edge_class == generator.RoadClass.HIGHWAY:
		gps_title.text = "Stay on highway"
		if highway_lane == HIGHWAY_EXIT_LANE:
			gps_subtitle.text = "Exit lane ready"
		else:
			gps_subtitle.text = "Move right for exit"
		return

	if current_edge_class == generator.RoadClass.CONNECTOR:
		if _route_contains_highway():
			gps_title.text = "Merge onto highway"
			gps_subtitle.text = "Follow the ramp"
		else:
			gps_title.text = "Exit toward venue"
			gps_subtitle.text = "Follow the connector"
		return

	if route.size() < 2:
		gps_title.text = "Continue"
		gps_subtitle.text = "Venue ahead"
		return

	var instruction: Dictionary = _next_route_instruction()
	gps_title.text = String(
		instruction.get("title", "Continue")
	)
	gps_subtitle.text = String(
		instruction.get("subtitle", "")
	)


func _route_contains_highway() -> bool:
	if route.size() < 2:
		return false

	for index in range(route.size() - 1):
		if generator.edge_class(
			int(route[index]),
			int(route[index + 1])
		) == generator.RoadClass.HIGHWAY:
			return true

	return false


func _next_route_instruction() -> Dictionary:
	if route.size() < 2:
		return {
			"title": "Continue",
			"subtitle": "Venue ahead",
		}

	var base_direction: Vector2i = _direction_between(
		int(route[0]),
		int(route[1])
	)

	if heading != Vector2i.ZERO and base_direction != heading:
		return {
			"title": _turn_title(heading, base_direction),
			"subtitle": "At this intersection",
		}

	for index in range(route.size() - 1):
		var a: int = int(route[index])
		var b: int = int(route[index + 1])
		var edge_class: int = generator.edge_class(a, b)

		if edge_class == generator.RoadClass.HIGHWAY:
			return {
				"title": "Merge onto highway",
				"subtitle": _blocks_subtitle(index + 1),
			}

		if edge_class == generator.RoadClass.CONNECTOR:
			return {
				"title": "Continue to connector",
				"subtitle": _blocks_subtitle(index + 1),
			}

		if index + 2 >= route.size():
			break

		var next_direction: Vector2i = _direction_between(
			b,
			int(route[index + 2])
		)
		var current_direction: Vector2i = _direction_between(
			a,
			b
		)

		if next_direction != current_direction:
			return {
				"title": _turn_title(
					current_direction,
					next_direction
				),
				"subtitle": _blocks_subtitle(index + 1),
			}

	return {
		"title": "Continue straight",
		"subtitle": _blocks_subtitle(route.size() - 1),
	}


func _turn_title(
	from_direction: Vector2i,
	to_direction: Vector2i
) -> String:
	var left: Vector2i = _rotated_heading(
		from_direction,
		-1
	)
	if to_direction == left:
		return "Turn left"

	var right: Vector2i = _rotated_heading(
		from_direction,
		1
	)
	if to_direction == right:
		return "Turn right"

	return "Turn around"


func _blocks_subtitle(count: int) -> String:
	if count <= 1:
		return "In 1 block"
	return "In %d blocks" % count


func _finish_trip() -> void:
	if drive_complete:
		return

	drive_complete = true
	started = false
	target_node = -1
	gps_title.text = "Arrived"
	gps_subtitle.text = "Venue"
	arrival_text.text = (
		"ARRIVED AT THE VENUE\n\n"
		+ "Drive time: %.1f sec\nMissed turns/exits: %d"
		% [drive_time, missed_turns]
	)
	arrival_panel.show()

	var result := {
		"status": "drive_complete",
		"real_drive_seconds": drive_time,
		"missed_turns": missed_turns,
		"wrong_way_tickets": 0,
		"bumps": 0,
		"seed": actual_seed,
	}
	trip_finished.emit(result)


func _draw() -> void:
	draw_rect(
		Rect2(Vector2.ZERO, size),
		PAGE_BG,
		true
	)
	draw_rect(
		Rect2(Vector2.ZERO, size),
		TERRAIN_COLOR,
		true
	)

	_draw_terrain_grid()

	if current_edge_class == generator.RoadClass.HIGHWAY:
		_draw_highway_view()
	else:
		_draw_world_roads()
		_draw_route_line()
		_draw_venue_block()


func _draw_terrain_grid() -> void:
	var spacing: float = 70.0
	var start_x: float = fposmod(
		-player_screen_center.x,
		spacing
	)
	var start_y: float = fposmod(
		-player_screen_center.y,
		spacing
	)

	var x: float = start_x
	while x < size.x:
		draw_line(
			Vector2(x, 0.0),
			Vector2(x, size.y),
			TERRAIN_GRID,
			1.0
		)
		x += spacing

	var y: float = start_y
	while y < size.y:
		draw_line(
			Vector2(0.0, y),
			Vector2(size.x, y),
			TERRAIN_GRID,
			1.0
		)
		y += spacing


func _draw_world_roads() -> void:
	for a in range(generator.nodes.size()):
		for b_value in generator.adjacency[a]:
			var b: int = int(b_value)
			if b <= a:
				continue

			var road_class: int = generator.edge_class(a, b)
			var p1: Vector2 = _world_to_screen(
				Vector2(generator.nodes[a])
			)
			var p2: Vector2 = _world_to_screen(
				Vector2(generator.nodes[b])
			)

			if not _segment_near_screen(p1, p2):
				continue

			var width: float = 18.0
			var color: Color = ROAD_COLOR

			match road_class:
				generator.RoadClass.CITY:
					width = 24.0
					color = CITY_ROAD_COLOR
				generator.RoadClass.CONNECTOR:
					width = 26.0
					color = CONNECTOR_COLOR
				generator.RoadClass.HIGHWAY:
					width = 70.0
					color = HIGHWAY_COLOR

			if road_class == generator.RoadClass.HIGHWAY:
				draw_line(
					p1,
					p2,
					HIGHWAY_SHOULDER,
					width + 10.0,
					true
				)

			draw_line(
				p1,
				p2,
				color,
				width,
				true
			)


func _draw_highway_view() -> void:
	var road_center_x: float = (
		player_screen_center.x
		- highway_lane_shift
	)
	var top := Vector2(
		road_center_x,
		-120.0
	)
	var bottom := Vector2(
		road_center_x,
		size.y + 120.0
	)

	draw_line(
		top,
		bottom,
		HIGHWAY_SHOULDER,
		102.0,
		true
	)
	draw_line(
		top,
		bottom,
		HIGHWAY_COLOR,
		90.0,
		true
	)

	var left_edge: float = (
		road_center_x
		- HIGHWAY_LANE_WIDTH * 2.0
	)

	for divider in range(HIGHWAY_LANES + 1):
		var x: float = (
			left_edge
			+ float(divider) * HIGHWAY_LANE_WIDTH
		)
		var width: float = (
			3.0
			if divider == 0 or divider == HIGHWAY_LANES
			else 1.5
		)

		draw_line(
			Vector2(x, -40.0),
			Vector2(x, size.y + 40.0),
			HIGHWAY_MARKING,
			width,
			true
		)


func _draw_route_line() -> void:
	if not started or drive_complete:
		return
	if route.size() < 2:
		return
	if (
		current_edge_class == generator.RoadClass.CONNECTOR
		or current_edge_class == generator.RoadClass.HIGHWAY
	):
		return

	var points := PackedVector2Array()
	points.append(
		_world_to_screen(visual_world_position)
	)

	for index in range(1, route.size()):
		var previous: int = int(route[index - 1])
		var node_id: int = int(route[index])
		var road_class: int = generator.edge_class(
			previous,
			node_id
		)

		if (
			road_class == generator.RoadClass.CONNECTOR
			or road_class == generator.RoadClass.HIGHWAY
		):
			break

		points.append(
			_world_to_screen(
				Vector2(generator.nodes[node_id])
			)
		)

	if points.size() < 2:
		return

	draw_polyline(
		points,
		ROUTE_SHADOW,
		10.0,
		true
	)
	draw_polyline(
		points,
		ROUTE_BLUE,
		6.0,
		true
	)


func _draw_venue_block() -> void:
	var corners := PackedVector2Array([
		_world_to_screen(
			Vector2(generator.venue_block.position)
		),
		_world_to_screen(
			Vector2(
				generator.venue_block.end.x,
				generator.venue_block.position.y
			)
		),
		_world_to_screen(
			Vector2(generator.venue_block.end)
		),
		_world_to_screen(
			Vector2(
				generator.venue_block.position.x,
				generator.venue_block.end.y
			)
		),
	])

	draw_colored_polygon(
		corners,
		VENUE_FILL
	)

	var center: Vector2 = _world_to_screen(
		Vector2(generator.venue_block.get_center())
	)
	draw_circle(
		center,
		7.0,
		VENUE_MARKER
	)

	var font := get_theme_default_font()
	draw_string(
		font,
		center + Vector2(10.0, 5.0),
		"B",
		HORIZONTAL_ALIGNMENT_LEFT,
		24.0,
		15,
		Color.WHITE
	)


func _world_to_screen(world_point: Vector2) -> Vector2:
	var offset: Vector2 = (
		world_point - visual_world_position
	)
	offset = offset.rotated(camera_rotation)
	offset *= camera_scale

	var lane_shift: float = (
		highway_lane_shift
		if current_edge_class == generator.RoadClass.HIGHWAY
		else 0.0
	)

	return (
		player_screen_center
		+ offset
		- Vector2(lane_shift, 0.0)
	)


func _segment_near_screen(
	a: Vector2,
	b: Vector2
) -> bool:
	var margin: float = 180.0
	var bounds := Rect2(
		Vector2(-margin, -margin),
		size + Vector2.ONE * margin * 2.0
	)

	return (
		bounds.has_point(a)
		or bounds.has_point(b)
		or Rect2(a, b - a).abs().intersects(bounds)
	)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return

	if event.keycode == KEY_LEFT:
		_turn_left()
	elif event.keycode == KEY_RIGHT:
		_turn_right()
	elif event.keycode == KEY_SPACE:
		_start_drive()
	elif event.keycode == KEY_R:
		_new_map()
