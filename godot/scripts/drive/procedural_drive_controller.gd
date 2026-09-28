extends Control

signal trip_finished(result: Dictionary)

const NETWORK_SCRIPT = preload("res://scripts/drive/procedural_road_network.gd")

const WORLD_ZOOM := 2.15
const WORLD_SPEED := 74.0
const TURN_SECONDS := 0.28
const CAR_SCALE := 0.72

const GROUND_COLOR := Color(0.18, 0.27, 0.16)
const ROAD_SHOULDER_COLOR := Color(0.48, 0.47, 0.42)
const ROAD_COLOR := Color(0.13, 0.145, 0.16)
const INTERSECTION_COLOR := Color(0.145, 0.16, 0.175)
const ROUTE_SHADOW_COLOR := Color(0.02, 0.08, 0.18, 0.58)
const ROUTE_COLOR := Color(0.12, 0.43, 0.98, 0.96)
const POINT_A_COLOR := Color(0.24, 0.68, 1.0)
const POINT_B_COLOR := Color(0.96, 0.35, 0.23)

const STEERING_LEAN_RADIANS := 0.075
const STEERING_FEEDBACK_DECAY := 5.5
const CAMERA_NUDGE_PIXELS := 4.0
const CAMERA_NUDGE_DECAY := 7.0

@export var world_seed: int = 0

var network := NETWORK_SCRIPT.new()
var actual_seed := 0

var started := false
var drive_complete := false
var drive_time := 0.0
var missed_turns := 0

var current_node := -1
var previous_node := -1
var next_node := -1
var destination_node := -1

var queued_turn := 0
var heading := Vector2.UP
var current_edge_points := PackedVector2Array()
var edge_point_index := 0

var visual_world_position := Vector2.ZERO
var move_to := Vector2.ZERO
var map_rotation := 0.0
var map_rotation_from := 0.0
var map_rotation_to := 0.0
var turn_elapsed := TURN_SECONDS

var steering_feedback := 0.0
var camera_nudge := Vector2.ZERO
var player_screen_center := Vector2.ZERO
var car_base_position := Vector2.ZERO

var route_nodes: Array = []

@onready var player_car: TextureRect = $"../PlayerCar"
@onready var left_button: Button = $"../TouchControls/LeftButton"
@onready var forward_button: Button = $"../TouchControls/ForwardButton"
@onready var right_button: Button = $"../TouchControls/RightButton"
@onready var status_label: Label = $"../StatusLabel"


func _ready() -> void:
	left_button.pressed.connect(_turn_left)
	forward_button.pressed.connect(_start_or_regenerate)
	right_button.pressed.connect(_turn_right)

	player_car.pivot_offset = player_car.size * 0.5
	_generate_network()
	call_deferred("_refresh_layout")


func _refresh_layout() -> void:
	player_screen_center = Vector2(size.x * 0.5, size.y * 0.48)
	car_base_position = player_screen_center - player_car.size * 0.5
	_update_car_visual()
	queue_redraw()


func _generate_network() -> void:
	actual_seed = world_seed
	if actual_seed == 0:
		actual_seed = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_msec())

	network.generate(actual_seed)
	current_node = network.start_node
	destination_node = network.destination_node
	previous_node = -1
	next_node = -1
	queued_turn = 0
	started = false
	drive_complete = false
	drive_time = 0.0
	missed_turns = 0
	current_edge_points = PackedVector2Array()
	edge_point_index = 0

	visual_world_position = network.nodes[current_node]
	move_to = visual_world_position
	route_nodes = network.shortest_path(current_node, destination_node)

	if route_nodes.size() > 1:
		heading = (
			network.nodes[route_nodes[1]] - visual_world_position
		).normalized()
	else:
		heading = Vector2.UP

	map_rotation = -PI / 2.0 - heading.angle()
	map_rotation_from = map_rotation
	map_rotation_to = map_rotation
	turn_elapsed = TURN_SECONDS
	steering_feedback = 0.0
	camera_nudge = Vector2.ZERO

	status_label.text = "POINT A → POINT B"
	forward_button.text = "START"
	forward_button.show()
	left_button.disabled = false
	right_button.disabled = false
	queue_redraw()


func _start_or_regenerate() -> void:
	if drive_complete:
		world_seed = 0
		_generate_network()
		_start_drive()
		return
	if not started:
		_start_drive()


func _start_drive() -> void:
	started = true
	forward_button.hide()
	_begin_next_edge()


func _process(delta: float) -> void:
	if not started or drive_complete:
		_update_car_visual()
		queue_redraw()
		return

	drive_time += delta
	turn_elapsed += delta
	_update_map_rotation()
	_update_feedback(delta)
	_advance_along_road(delta)
	_update_car_visual()
	queue_redraw()


func _advance_along_road(delta: float) -> void:
	var remaining := WORLD_SPEED * delta

	while remaining > 0.0 and started and not drive_complete:
		var distance_to_target := visual_world_position.distance_to(move_to)
		if distance_to_target <= 0.001:
			_reach_curve_point()
			continue

		var step := minf(remaining, distance_to_target)
		visual_world_position = visual_world_position.move_toward(move_to, step)
		remaining -= step


func _reach_curve_point() -> void:
	visual_world_position = move_to

	if edge_point_index < current_edge_points.size() - 1:
		edge_point_index += 1
		_set_curve_target(current_edge_points[edge_point_index])
		return

	previous_node = current_node
	current_node = next_node
	next_node = -1

	if current_node == destination_node:
		_finish_drive()
		return

	_recalculate_route()
	_begin_next_edge()


func _begin_next_edge() -> void:
	var candidates: Array = network.neighbors(current_node)
	if candidates.is_empty():
		_finish_drive()
		return

	if previous_node >= 0 and candidates.size() > 1:
		candidates.erase(previous_node)

	var expected_next := -1
	_recalculate_route()
	if route_nodes.size() > 1:
		expected_next = int(route_nodes[1])

	var selected := _choose_candidate(candidates, expected_next)
	if selected < 0:
		selected = int(candidates[0])

	if expected_next >= 0 and selected != expected_next:
		missed_turns += 1

	next_node = selected
	current_edge_points = network.edge_curve(current_node, next_node)
	edge_point_index = 1 if current_edge_points.size() > 1 else 0

	if current_edge_points.is_empty():
		move_to = network.nodes[next_node]
		_set_heading(move_to - visual_world_position)
	else:
		_set_curve_target(current_edge_points[edge_point_index])


func _choose_candidate(candidates: Array, expected_next: int) -> int:
	if candidates.is_empty():
		return -1

	if previous_node < 0:
		return expected_next if expected_next >= 0 else int(candidates[0])

	var incoming := heading.normalized()
	var straightest := int(candidates[0])
	var straightest_abs := INF
	var requested := -1
	var requested_abs := INF

	for candidate_value in candidates:
		var candidate: int = int(candidate_value)
		var outgoing := (
			network.nodes[candidate] - network.nodes[current_node]
		).normalized()
		var cross := incoming.x * outgoing.y - incoming.y * outgoing.x
		var dot := clampf(incoming.dot(outgoing), -1.0, 1.0)
		var angle := atan2(cross, dot)
		var angle_abs := absf(angle)

		if angle_abs < straightest_abs:
			straightest_abs = angle_abs
			straightest = candidate

		if queued_turn < 0 and angle < -0.28 and angle_abs < requested_abs:
			requested = candidate
			requested_abs = angle_abs
		elif queued_turn > 0 and angle > 0.28 and angle_abs < requested_abs:
			requested = candidate
			requested_abs = angle_abs

	if requested >= 0:
		queued_turn = 0
		return requested

	# If a requested turn was not available, keep it queued for a later
	# junction and continue along the most natural branch.
	return straightest


func _set_curve_target(target: Vector2) -> void:
	move_to = target
	_set_heading(move_to - visual_world_position)


func _set_heading(delta: Vector2) -> void:
	if delta.length_squared() <= 0.001:
		return

	heading = delta.normalized()
	map_rotation_from = map_rotation
	map_rotation_to = -PI / 2.0 - heading.angle()
	turn_elapsed = 0.0


func _recalculate_route() -> void:
	route_nodes = network.shortest_path(current_node, destination_node)


func _turn_left() -> void:
	if not started or drive_complete:
		return
	queued_turn = -1
	_trigger_feedback(-1.0)


func _turn_right() -> void:
	if not started or drive_complete:
		return
	queued_turn = 1
	_trigger_feedback(1.0)


func _trigger_feedback(direction: float) -> void:
	steering_feedback = direction
	camera_nudge = Vector2(-direction * CAMERA_NUDGE_PIXELS, 0.0)


func _update_feedback(delta: float) -> void:
	steering_feedback = move_toward(
		steering_feedback,
		0.0,
		STEERING_FEEDBACK_DECAY * delta
	)
	camera_nudge = camera_nudge.lerp(
		Vector2.ZERO,
		clampf(CAMERA_NUDGE_DECAY * delta, 0.0, 1.0)
	)


func _update_map_rotation() -> void:
	if turn_elapsed < TURN_SECONDS:
		var t := clampf(turn_elapsed / TURN_SECONDS, 0.0, 1.0)
		map_rotation = lerp_angle(
			map_rotation_from,
			map_rotation_to,
			_smootherstep(t)
		)
	else:
		map_rotation = map_rotation_to


func _smootherstep(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


func _update_car_visual() -> void:
	player_car.position = car_base_position + Vector2(
		steering_feedback * 1.1,
		0.0
	)
	player_car.scale = Vector2.ONE * CAR_SCALE
	player_car.rotation = steering_feedback * STEERING_LEAN_RADIANS


func _finish_drive() -> void:
	if drive_complete:
		return

	drive_complete = true
	started = false
	status_label.text = "POINT B REACHED"
	forward_button.text = "NEW MAP"
	forward_button.show()
	left_button.disabled = true
	right_button.disabled = true

	trip_finished.emit({
		"status": "drive_complete",
		"real_drive_seconds": snappedf(drive_time, 0.1),
		"missed_turns": missed_turns,
		"wrong_way_tickets": 0,
		"bumps": 0,
		"seed": actual_seed,
	})


func current_route_after_edge() -> Array:
	if next_node >= 0:
		return network.shortest_path(next_node, destination_node)
	return network.shortest_path(current_node, destination_node)


func next_route_instruction() -> Dictionary:
	var route := current_route_after_edge()
	if route.size() < 2:
		return {
			"turn": "straight",
			"title": "Arrive at Point B",
			"subtitle": "",
			"key": "arrive",
		}

	var junction_node := next_node if next_node >= 0 else current_node
	var incoming_direction := heading

	if next_node >= 0:
		incoming_direction = (
			network.nodes[next_node] - network.nodes[current_node]
		).normalized()

	if route[0] != junction_node:
		junction_node = int(route[0])

	var outgoing := (
		network.nodes[int(route[1])] - network.nodes[junction_node]
	).normalized()
	var cross := incoming_direction.x * outgoing.y - incoming_direction.y * outgoing.x
	var dot := clampf(incoming_direction.dot(outgoing), -1.0, 1.0)
	var angle := atan2(cross, dot)

	var turn := "straight"
	if angle < -0.35:
		turn = "left"
	elif angle > 0.35:
		turn = "right"

	var title := "Continue ahead"
	if turn == "left":
		title = "Turn left"
	elif turn == "right":
		title = "Turn right"

	return {
		"turn": turn,
		"title": title,
		"subtitle": "Next junction",
		"key": "%s|%d" % [turn, junction_node],
	}


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), GROUND_COLOR, true)

	for a in range(network.nodes.size()):
		for b_value in network.adjacency[a]:
			var b: int = int(b_value)
			if b <= a:
				continue
			var curve := network.edge_curve(a, b)
			_draw_world_polyline(curve, ROAD_SHOULDER_COLOR, 16.0)
			_draw_world_polyline(curve, ROAD_COLOR, 11.0)

	for point in network.nodes:
		_draw_world_circle(point, 6.0, INTERSECTION_COLOR)

	_draw_route_line()
	_draw_world_marker(
		network.nodes[network.start_node],
		POINT_A_COLOR,
		"A"
	)
	_draw_world_marker(
		network.nodes[destination_node],
		POINT_B_COLOR,
		"B"
	)


func _draw_route_line() -> void:
	if drive_complete:
		return

	if next_node >= 0 and not current_edge_points.is_empty():
		var remaining_edge := PackedVector2Array([visual_world_position])
		for index in range(edge_point_index, current_edge_points.size()):
			remaining_edge.append(current_edge_points[index])
		_draw_world_polyline(remaining_edge, ROUTE_SHADOW_COLOR, 6.0)
		_draw_world_polyline(remaining_edge, ROUTE_COLOR, 3.6)

	var route := current_route_after_edge()
	for index in range(route.size() - 1):
		var curve := network.edge_curve(int(route[index]), int(route[index + 1]))
		_draw_world_polyline(curve, ROUTE_SHADOW_COLOR, 6.0)
		_draw_world_polyline(curve, ROUTE_COLOR, 3.6)


func _draw_world_marker(
	world_point: Vector2,
	color: Color,
	label_text: String
) -> void:
	var screen := _world_to_screen(world_point)
	draw_circle(screen, 8.0, color)
	draw_circle(screen, 3.5, Color.WHITE)
	var font := get_theme_default_font()
	draw_string(
		font,
		screen + Vector2(11.0, 5.0),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		28.0,
		15,
		Color.WHITE
	)


func _draw_world_circle(world_point: Vector2, radius: float, color: Color) -> void:
	draw_circle(_world_to_screen(world_point), radius * WORLD_ZOOM, color)


func _draw_world_polyline(
	world_points: PackedVector2Array,
	color: Color,
	world_width: float
) -> void:
	if world_points.size() < 2:
		return

	var screen_points := PackedVector2Array()
	for point in world_points:
		screen_points.append(_world_to_screen(point))

	draw_polyline(
		screen_points,
		color,
		world_width * WORLD_ZOOM,
		true
	)


func _world_to_screen(world_point: Vector2) -> Vector2:
	var offset := (world_point - visual_world_position) * WORLD_ZOOM
	offset = offset.rotated(map_rotation)
	return player_screen_center + offset + camera_nudge


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_LEFT, KEY_A:
			_turn_left()
		KEY_RIGHT, KEY_D:
			_turn_right()
		KEY_SPACE, KEY_ENTER:
			_start_or_regenerate()
