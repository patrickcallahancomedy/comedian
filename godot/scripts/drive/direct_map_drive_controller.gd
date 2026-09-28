extends Control

## Drives directly on the exact procedural road graph.
## There are no replacement neighborhood/highway/city scenes. The only
## transformation is one continuous camera centered on the player.

signal trip_finished(result: Dictionary)

const GENERATOR = preload("res://scripts/drive/grid_world_generator.gd")

const CAMERA_SCALE := 5.0
const CAMERA_ROTATE_SPEED := 8.0

const NEIGHBORHOOD_SPEED := 20.0
const CITY_SPEED := 28.0
const CONNECTOR_SPEED := 38.0
const HIGHWAY_SPEED := 72.0

const WORLD_BG := Color(0.29, 0.39, 0.22)
const GRID_MINOR := Color(1.0, 1.0, 1.0, 0.025)
const GRID_MAJOR := Color(1.0, 1.0, 1.0, 0.055)

const ROAD_COLOR := Color(0.115, 0.125, 0.14)
const CITY_ROAD_COLOR := Color(0.105, 0.115, 0.13)
const CONNECTOR_COLOR := Color(0.13, 0.14, 0.155)
const HIGHWAY_COLOR := Color(0.105, 0.115, 0.13)
const HIGHWAY_SHOULDER := Color(0.20, 0.21, 0.22)

const ROUTE_SHADOW := Color(0.02, 0.08, 0.18, 0.52)
const ROUTE_BLUE := Color(0.10, 0.42, 0.96, 0.98)
const VENUE_FILL := Color(0.47, 0.20, 0.11, 0.88)
const VENUE_MARKER := Color(0.84, 0.39, 0.19)

const NEIGHBORHOOD_ROAD_WORLD_WIDTH := 7.0
const CITY_ROAD_WORLD_WIDTH := 8.0
const CONNECTOR_ROAD_WORLD_WIDTH := 8.0
const HIGHWAY_ROAD_WORLD_WIDTH := 18.0

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
var camera_rotation: float = 0.0
var camera_rotation_target: float = 0.0
var queued_turn: int = 0
var blocked_at_node: bool = false

var route: Array = []
var player_screen_center := Vector2.ZERO

@onready var player_car: TextureRect = $"../PlayerCar"
@onready var left_button: Button = $"../TouchControls/LeftButton"
@onready var start_button: Button = $"../TouchControls/StartButton"
@onready var right_button: Button = $"../TouchControls/RightButton"
@onready var new_map_button: Button = $"../NewMapButton"
@onready var seed_label: Label = $"../SeedLabel"
@onready var gps_title: Label = $"../GpsPanel/GpsLayout/GpsTitle"
@onready var gps_subtitle: Label = $"../GpsPanel/GpsLayout/GpsSubtitle"
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
	queued_turn = 0
	blocked_at_node = false

	start_button.show()
	player_car.show()
	arrival_panel.hide()
	left_button.disabled = false
	right_button.disabled = false

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
	camera_rotation = lerp_angle(
		camera_rotation,
		camera_rotation_target,
		clampf(CAMERA_ROTATE_SPEED * delta, 0.0, 1.0)
	)

	if started and not drive_complete:
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

	visual_world_position = segment_end
	_arrive_at_target()


func _arrive_at_target() -> void:
	previous_node = current_node
	current_node = target_node
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

	var choices: Array = _non_backtracking_neighbors()
	if choices.size() == 1:
		_begin_segment(int(choices[0]))
		return

	blocked_at_node = true
	_update_gps()


func _begin_segment(next_node: int) -> void:
	if next_node < 0:
		return

	_recalculate_route()
	var expected_next: int = -1
	if route.size() >= 2:
		expected_next = int(route[1])

	if started and expected_next >= 0 and next_node != expected_next:
		missed_turns += 1

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

	_update_gps()


func _turn_left() -> void:
	_handle_turn(-1)


func _turn_right() -> void:
	_handle_turn(1)


func _handle_turn(direction: int) -> void:
	if not started or drive_complete:
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
			camera_rotation_target = _rotation_for_heading(heading)
			_begin_segment(neighbor)
		return

	queued_turn = direction


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

	return -PI / 2.0 - Vector2(direction).angle()


func _speed_for_class(road_class: int) -> float:
	match road_class:
		generator.RoadClass.CITY:
			return CITY_SPEED
		generator.RoadClass.CONNECTOR:
			return CONNECTOR_SPEED
		generator.RoadClass.HIGHWAY:
			return HIGHWAY_SPEED
	return NEIGHBORHOOD_SPEED


func _recalculate_route() -> void:
	if current_node < 0:
		route = []
		return

	route = generator.shortest_path(
		current_node,
		generator.venue_access_node
	)


func _update_gps() -> void:
	if drive_complete:
		gps_title.text = "Arrived"
		gps_subtitle.text = "Venue"
		return

	if not started:
		gps_title.text = "Route ready"
		gps_subtitle.text = "Drive to the venue"
		return

	if blocked_at_node:
		var blocked_instruction: Dictionary = _next_route_instruction()
		gps_title.text = String(
			blocked_instruction.get("title", "Choose a turn")
		)
		gps_subtitle.text = "At this intersection"
		return

	if current_edge_class == generator.RoadClass.HIGHWAY:
		gps_title.text = "Continue on highway"
		gps_subtitle.text = "Stay on the generated route"
		return

	if current_edge_class == generator.RoadClass.CONNECTOR:
		gps_title.text = "Follow connector"
		gps_subtitle.text = "Continue"
		return

	var instruction: Dictionary = _next_route_instruction()
	gps_title.text = String(
		instruction.get("title", "Continue")
	)
	gps_subtitle.text = String(
		instruction.get("subtitle", "")
	)


func _next_route_instruction() -> Dictionary:
	if route.size() < 2:
		return {
			"title": "Continue",
			"subtitle": "Venue ahead",
		}

	for index in range(route.size() - 1):
		var a: int = int(route[index])
		var b: int = int(route[index + 1])
		var current_direction: Vector2i = _direction_between(a, b)

		if index == 0 and current_direction != heading:
			return {
				"title": _turn_title(heading, current_direction),
				"subtitle": "At this intersection",
			}

		if index + 2 >= route.size():
			break

		var next_direction: Vector2i = _direction_between(
			b,
			int(route[index + 2])
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
	if to_direction == _rotated_heading(from_direction, -1):
		return "Turn left"
	if to_direction == _rotated_heading(from_direction, 1):
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
		+ "Drive time: %.1f sec\nWrong turns: %d"
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
		WORLD_BG,
		true
	)
	_draw_grid()
	_draw_roads()
	_draw_route_line()
	_draw_venue_block()


func _draw_grid() -> void:
	for coordinate in range(0, generator.GRID_SIZE + 1, 10):
		var color: Color = (
			GRID_MAJOR
			if coordinate % 50 == 0
			else GRID_MINOR
		)
		var width: float = (
			1.0
			if coordinate % 50 == 0
			else 0.6
		)

		draw_line(
			_world_to_screen(
				Vector2(0.0, float(coordinate))
			),
			_world_to_screen(
				Vector2(
					float(generator.GRID_SIZE),
					float(coordinate)
				)
			),
			color,
			width
		)

		draw_line(
			_world_to_screen(
				Vector2(float(coordinate), 0.0)
			),
			_world_to_screen(
				Vector2(
					float(coordinate),
					float(generator.GRID_SIZE)
				)
			),
			color,
			width
		)


func _draw_roads() -> void:
	for a in range(generator.nodes.size()):
		for b_value in generator.adjacency[a]:
			var b: int = int(b_value)
			if b <= a:
				continue

			var p1: Vector2 = _world_to_screen(
				Vector2(generator.nodes[a])
			)
			var p2: Vector2 = _world_to_screen(
				Vector2(generator.nodes[b])
			)
			if not _segment_near_screen(p1, p2):
				continue

			var road_class: int = generator.edge_class(a, b)
			var road_width: float = (
				_road_world_width(road_class)
				* CAMERA_SCALE
			)
			var color: Color = _road_color(road_class)

			if road_class == generator.RoadClass.HIGHWAY:
				draw_line(
					p1,
					p2,
					HIGHWAY_SHOULDER,
					road_width + 12.0,
					true
				)

			draw_line(
				p1,
				p2,
				color,
				road_width,
				true
			)

	for node_id in range(generator.nodes.size()):
		var center: Vector2 = _world_to_screen(
			Vector2(generator.nodes[node_id])
		)
		if not _point_near_screen(center):
			continue

		var strongest: int = _strongest_node_class(node_id)
		var radius: float = (
			_road_world_width(strongest)
			* CAMERA_SCALE
			* 0.5
		)
		draw_circle(
			center,
			radius,
			_road_color(strongest)
		)


func _road_world_width(road_class: int) -> float:
	match road_class:
		generator.RoadClass.CITY:
			return CITY_ROAD_WORLD_WIDTH
		generator.RoadClass.CONNECTOR:
			return CONNECTOR_ROAD_WORLD_WIDTH
		generator.RoadClass.HIGHWAY:
			return HIGHWAY_ROAD_WORLD_WIDTH
	return NEIGHBORHOOD_ROAD_WORLD_WIDTH


func _road_color(road_class: int) -> Color:
	match road_class:
		generator.RoadClass.CITY:
			return CITY_ROAD_COLOR
		generator.RoadClass.CONNECTOR:
			return CONNECTOR_COLOR
		generator.RoadClass.HIGHWAY:
			return HIGHWAY_COLOR
	return ROAD_COLOR


func _strongest_node_class(node_id: int) -> int:
	var strongest: int = generator.RoadClass.NEIGHBORHOOD

	for neighbor_value in generator.adjacency[node_id]:
		var neighbor: int = int(neighbor_value)
		strongest = maxi(
			strongest,
			generator.edge_class(node_id, neighbor)
		)

	return strongest


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
	points.append(_world_to_screen(visual_world_position))

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
		11.0,
		true
	)
	draw_polyline(
		points,
		ROUTE_BLUE,
		7.0,
		true
	)


func _draw_venue_block() -> void:
	var inset := 2.0
	var corners := PackedVector2Array([
		_world_to_screen(
			Vector2(generator.venue_block.position)
			+ Vector2(inset, inset)
		),
		_world_to_screen(
			Vector2(
				generator.venue_block.end.x - inset,
				generator.venue_block.position.y + inset
			)
		),
		_world_to_screen(
			Vector2(generator.venue_block.end)
			- Vector2(inset, inset)
		),
		_world_to_screen(
			Vector2(
				generator.venue_block.position.x + inset,
				generator.venue_block.end.y - inset
			)
		),
	])

	draw_colored_polygon(corners, VENUE_FILL)

	var center: Vector2 = _world_to_screen(
		Vector2(generator.venue_block.get_center())
	)
	if _point_near_screen(center):
		draw_circle(center, 7.0, VENUE_MARKER)


func _world_to_screen(world_point: Vector2) -> Vector2:
	var offset: Vector2 = world_point - visual_world_position
	offset = offset.rotated(camera_rotation)
	offset *= CAMERA_SCALE
	return player_screen_center + offset


func _segment_near_screen(
	a: Vector2,
	b: Vector2
) -> bool:
	var margin := 180.0
	var bounds := Rect2(
		Vector2(-margin, -margin),
		size + Vector2.ONE * margin * 2.0
	)

	return (
		bounds.has_point(a)
		or bounds.has_point(b)
		or Rect2(a, b - a).abs().intersects(bounds)
	)


func _point_near_screen(point: Vector2) -> bool:
	var margin := 180.0
	return Rect2(
		Vector2(-margin, -margin),
		size + Vector2.ONE * margin * 2.0
	).has_point(point)


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
