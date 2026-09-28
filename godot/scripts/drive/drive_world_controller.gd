extends Control

## COMEDIAN driving world rebuild.
## New world/road implementation with the same external UI + game contract.

signal trip_finished(result: Dictionary)

const MAP = preload("res://scripts/drive/drive_world_map.gd")
const PARKED_CAR_TEXTURE: Texture2D = preload("res://assets/car/player_car_top.png")

const TURN_SECONDS := 0.34
const WORLD_ZOOM := 8.4
const HIGHWAY_ZOOM := 6.1
const CITY_ZOOM := 7.0
const CAR_REFERENCE_SCALE := 0.65
const HIGHWAY_PLAYER_SCALE := 1.35
const CITY_PLAYER_SCALE := 1.15

const NEIGHBORHOOD_WORLD_SPEED := 42.0
const RAMP_WORLD_SPEED := 58.0
const HIGHWAY_WORLD_SPEED := 82.0
const CITY_WORLD_SPEED := 38.0
const PARKING_WORLD_SPEED := 22.0

const LOCAL_GROUND := Color(0.24, 0.38, 0.21)
const LOCAL_ROAD := Color(0.15, 0.17, 0.20)
const LOCAL_SIDEWALK := Color(0.68, 0.66, 0.59)
const CITY_GROUND := Color(0.24, 0.255, 0.27)
const CITY_ROAD := Color(0.105, 0.115, 0.13)
const CITY_SIDEWALK := Color(0.52, 0.52, 0.50)
const HIGHWAY_ASPHALT := Color(0.115, 0.125, 0.145)
const HIGHWAY_ASPHALT_ALT := Color(0.135, 0.145, 0.165)
const HIGHWAY_MARKING := Color(0.93, 0.92, 0.86, 0.92)
const HIGHWAY_EDGE := Color(0.97, 0.96, 0.90, 0.96)
const HIGHWAY_MEDIAN := Color(0.22, 0.30, 0.20)
const RAMP_SHOULDER := Color(0.23, 0.24, 0.24)
const RAMP_ASPHALT := Color(0.12, 0.13, 0.15)
const RAMP_EDGE := Color(0.95, 0.94, 0.88, 0.92)
const BUILDING_COLORS := [
	Color(0.32, 0.28, 0.24),
	Color(0.28, 0.30, 0.32),
	Color(0.36, 0.31, 0.25),
	Color(0.29, 0.27, 0.30),
]
const HOUSE_COLORS := [
	Color(0.64, 0.47, 0.33),
	Color(0.48, 0.58, 0.65),
	Color(0.73, 0.61, 0.42),
	Color(0.55, 0.52, 0.47),
]
const PARKING_LINE := Color(0.92, 0.91, 0.84, 0.76)
const PARKING_ASPHALT := Color(0.13, 0.14, 0.16)
const VENUE_COLOR := Color(0.18, 0.16, 0.15)
const VENUE_TRIM := Color(0.78, 0.47, 0.22)

const STEERING_LEAN_RADIANS := 0.085
const STEERING_SWAY_PIXELS := 0.75
const CAMERA_COUNTER_NUDGE_PIXELS := 5.0
const STEERING_FEEDBACK_DECAY := 5.5
const CAMERA_NUDGE_DECAY := 7.0
const CAR_STEERING_PIVOT_Y_RATIO := 0.28

const HIGHWAY_TRAFFIC_LANES := [2, 0, 3, 1, 2, 0]
const HIGHWAY_TRAFFIC_START_OFFSETS := [70.0, 120.0, 165.0, 215.0, 265.0, 315.0]
const HIGHWAY_TRAFFIC_APPROACH_SPEEDS := [4.0, 4.4, 4.8, 4.1, 4.5, 4.7]
const HIGHWAY_TRAFFIC_RESPAWN := 330.0
const HIGHWAY_COLLISION_LENGTH := 13.0
const HIGHWAY_COLLISION_LATERAL := 5.0
const HIGHWAY_COLLISION_SLOW_SECONDS := 0.8
const HIGHWAY_COLLISION_SPEED_MULTIPLIER := 0.45

@export var world_seed: int = 0

var started := false
var drive_complete := false
var drive_time := 0.0
var missed_turns := 0
var bumps := 0

var road_kind := "neighborhood"
var local_area := "neighborhood"
var local_node := MAP.NEIGHBORHOOD_START
var previous_local_node := ""
var heading := Vector2i.UP
var queued_turn := 0
var blocked_this_step := false

var path_points := PackedVector2Array()
var path_index := 0

var highway_lane := MAP.HIGHWAY_ENTRY_LANE
var queued_highway_lane := MAP.HIGHWAY_ENTRY_LANE
var highway_target_x := MAP.HIGHWAY_ENTRY_X
var highway_exit_passed := false

var parking_phase := 0
var parking_selected := 0

var move_from := Vector2.ZERO
var move_to := Vector2.ZERO
var visual_world_position := Vector2.ZERO
var visual_scale := 1.0
var scale_from := 1.0
var scale_to := 1.0
var motion_direction := Vector2.UP

var map_rotation := 0.0
var map_rotation_from := 0.0
var map_rotation_to := 0.0
var turn_elapsed := TURN_SECONDS

var steering_feedback := 0.0
var camera_nudge := Vector2.ZERO
var highway_collision_slow_remaining := 0.0
var highway_traffic_offsets: Array[float] = []

var player_screen_center := Vector2.ZERO
var car_base_position := Vector2.ZERO

@onready var player_car: TextureRect = $"../PlayerCar"
@onready var traffic_cars: Array[TextureRect] = [
	$"../TrafficCars/TrafficCarA",
	$"../TrafficCars/TrafficCarB",
	$"../TrafficCars/TrafficCarC",
	$"../TrafficCars/TrafficCarD",
	$"../TrafficCars/TrafficCarE",
	$"../TrafficCars/TrafficCarF",
]
@onready var left_button: Button = $"../TouchControls/LeftButton"
@onready var forward_button: Button = $"../TouchControls/ForwardButton"
@onready var right_button: Button = $"../TouchControls/RightButton"
@onready var status_label: Label = $"../StatusLabel"


func _ready() -> void:
	left_button.pressed.connect(_turn_left)
	forward_button.pressed.connect(_start_drive)
	right_button.pressed.connect(_turn_right)

	player_car.pivot_offset = Vector2(
		player_car.size.x * 0.5,
		player_car.size.y * CAR_STEERING_PIVOT_Y_RATIO
	)
	_reset_to_start()
	call_deferred("_refresh_layout")


func _refresh_layout() -> void:
	player_screen_center = Vector2(size.x * 0.5, size.y * 0.46)
	car_base_position = player_screen_center - player_car.size * 0.5
	_update_car_visual()
	_update_highway_traffic()
	queue_redraw()


func _reset_to_start() -> void:
	started = false
	drive_complete = false
	drive_time = 0.0
	missed_turns = 0
	bumps = 0
	road_kind = "neighborhood"
	local_area = "neighborhood"
	local_node = MAP.NEIGHBORHOOD_START
	previous_local_node = ""
	heading = Vector2i.UP
	queued_turn = 0
	blocked_this_step = false
	path_points = PackedVector2Array()
	path_index = 0
	highway_lane = MAP.HIGHWAY_ENTRY_LANE
	queued_highway_lane = MAP.HIGHWAY_ENTRY_LANE
	highway_target_x = MAP.HIGHWAY_ENTRY_X
	highway_exit_passed = false
	parking_phase = 0
	parking_selected = 0
	visual_world_position = MAP.node_position("neighborhood", local_node)
	move_from = visual_world_position
	move_to = visual_world_position
	visual_scale = 1.0
	scale_from = 1.0
	scale_to = 1.0
	motion_direction = Vector2.UP
	map_rotation = 0.0
	map_rotation_from = 0.0
	map_rotation_to = 0.0
	turn_elapsed = TURN_SECONDS
	steering_feedback = 0.0
	camera_nudge = Vector2.ZERO
	highway_collision_slow_remaining = 0.0
	highway_traffic_offsets = []
	for value in HIGHWAY_TRAFFIC_START_OFFSETS:
		highway_traffic_offsets.append(float(value))
	status_label.text = "TAP START"
	forward_button.show()
	left_button.disabled = false
	right_button.disabled = false


func _start_drive() -> void:
	if started or drive_complete:
		return
	started = true
	forward_button.hide()
	status_label.text = "NEIGHBORHOOD"
	_begin_next_step()


func _process(delta: float) -> void:
	if drive_complete:
		return

	if not started:
		_update_car_visual()
		_update_highway_traffic()
		queue_redraw()
		return

	drive_time += delta
	turn_elapsed += delta
	highway_collision_slow_remaining = maxf(
		0.0,
		highway_collision_slow_remaining - delta
	)
	_update_game_feel(delta)
	_update_map_rotation()
	_advance_motion(delta)
	_update_car_visual()
	_update_highway_traffic(delta)
	queue_redraw()


func _update_map_rotation() -> void:
	if turn_elapsed < TURN_SECONDS:
		var turn_t := clampf(turn_elapsed / TURN_SECONDS, 0.0, 1.0)
		map_rotation = lerp_angle(
			map_rotation_from,
			map_rotation_to,
			_smootherstep(turn_t)
		)
	else:
		map_rotation = map_rotation_to


func _advance_motion(delta: float) -> void:
	var remaining_time := delta

	while remaining_time > 0.0 and not drive_complete:
		if blocked_this_step:
			return

		var distance_to_target := visual_world_position.distance_to(move_to)
		if distance_to_target <= 0.001:
			visual_world_position = move_to
			visual_scale = scale_to
			_begin_next_step()
			continue

		var speed := _current_world_speed()
		var time_to_target := distance_to_target / speed
		var travel_time := minf(remaining_time, time_to_target)

		visual_world_position = visual_world_position.move_toward(
			move_to,
			speed * travel_time
		)

		var segment_length := move_from.distance_to(move_to)
		if segment_length > 0.001:
			var progress := 1.0 - (
				visual_world_position.distance_to(move_to) / segment_length
			)
			visual_scale = lerpf(
				scale_from,
				scale_to,
				clampf(progress, 0.0, 1.0)
			)

		remaining_time -= travel_time

		if visual_world_position.distance_to(move_to) <= 0.001:
			visual_world_position = move_to
			visual_scale = scale_to
			_begin_next_step()


func _begin_next_step() -> void:
	move_from = visual_world_position
	scale_from = visual_scale
	blocked_this_step = false

	match road_kind:
		"neighborhood", "city":
			_begin_local_step()
		"onramp", "offramp":
			_begin_path_step()
		"highway":
			_begin_highway_step()
		"parking":
			_begin_parking_step()


func _begin_local_step() -> void:
	if road_kind == "neighborhood" and local_node == MAP.NEIGHBORHOOD_GATE:
		_begin_ramp("onramp")
		return

	if (
		road_kind == "city"
		and local_node == MAP.CITY_PARKING_NODE
		and queued_turn == 1
	):
		queued_turn = 0
		_begin_parking_entry()
		return

	var current_position := MAP.node_position(local_area, local_node)
	var candidates: Array[String] = MAP.neighbors(local_area, local_node)
	if not previous_local_node.is_empty():
		candidates.erase(previous_local_node)

	var selected := _select_local_candidate(current_position, candidates)
	if selected.is_empty():
		move_to = move_from
		scale_to = scale_from
		blocked_this_step = true
		status_label.text = "TURN"
		return

	var next_position := MAP.node_position(local_area, selected)
	previous_local_node = local_node
	local_node = selected
	heading = MAP.cardinal_direction(current_position, next_position)
	queued_turn = 0

	move_to = next_position
	scale_to = 1.0 if road_kind == "neighborhood" else CITY_PLAYER_SCALE
	_set_motion_direction(move_to - move_from)
	status_label.text = "NEIGHBORHOOD" if road_kind == "neighborhood" else "CITY"


func _select_local_candidate(
	current_position: Vector2,
	candidates: Array[String]
) -> String:
	var straight_candidate := ""
	var requested_candidate := ""

	for candidate in candidates:
		var candidate_position := MAP.node_position(local_area, candidate)
		var outgoing := MAP.cardinal_direction(current_position, candidate_position)
		var kind := MAP.turn_kind(heading, outgoing)

		if kind == "straight":
			straight_candidate = candidate
		if (
			(queued_turn < 0 and kind == "left")
			or (queued_turn > 0 and kind == "right")
		):
			requested_candidate = candidate

	if not requested_candidate.is_empty():
		return requested_candidate
	if queued_turn != 0:
		return ""
	if not straight_candidate.is_empty():
		return straight_candidate
	return ""


func _begin_ramp(kind: String, reroute: bool = false) -> void:
	road_kind = kind
	path_points = (
		MAP.onramp_points()
		if kind == "onramp"
		else MAP.offramp_points(reroute)
	)
	path_index = 0
	queued_turn = 0
	steering_feedback = 0.0
	camera_nudge = Vector2.ZERO

	if path_points.is_empty():
		return

	# If the graph node equals the first curve point, advance to the first
	# genuinely new point immediately.
	while (
		path_index < path_points.size() - 1
		and visual_world_position.distance_to(path_points[path_index]) <= 0.5
	):
		path_index += 1

	_set_path_target()


func _begin_path_step() -> void:
	if path_index < path_points.size() - 1:
		path_index += 1
		_set_path_target()
		return

	if road_kind == "onramp":
		_enter_highway()
	else:
		_enter_city()


func _set_path_target() -> void:
	move_to = path_points[path_index]
	if road_kind == "onramp":
		var denominator := maxi(1, path_points.size() - 1)
		var t := float(path_index) / float(denominator)
		scale_to = lerpf(1.0, HIGHWAY_PLAYER_SCALE, t)
	else:
		var denominator := maxi(1, path_points.size() - 1)
		var t := float(path_index) / float(denominator)
		scale_to = lerpf(HIGHWAY_PLAYER_SCALE, CITY_PLAYER_SCALE, t)
	_set_motion_direction(move_to - move_from)


func _enter_highway() -> void:
	road_kind = "highway"
	highway_lane = MAP.HIGHWAY_ENTRY_LANE
	queued_highway_lane = highway_lane
	highway_target_x = MAP.HIGHWAY_ENTRY_X - MAP.HIGHWAY_STEP
	visual_world_position = MAP.highway_entry_point()
	move_from = visual_world_position
	move_to = MAP.highway_lane_center(highway_lane, highway_target_x)
	visual_scale = HIGHWAY_PLAYER_SCALE
	scale_from = visual_scale
	scale_to = HIGHWAY_PLAYER_SCALE
	_set_motion_direction(move_to - move_from)
	status_label.text = "HIGHWAY"


func _begin_highway_step() -> void:
	if (
		not highway_exit_passed
		and visual_world_position.x <= MAP.HIGHWAY_EXIT_X + 1.0
	):
		if highway_lane == MAP.HIGHWAY_EXIT_LANE:
			_begin_ramp("offramp")
			return

		highway_exit_passed = true
		missed_turns += 1

	if (
		highway_exit_passed
		and visual_world_position.x <= MAP.HIGHWAY_REROUTE_EXIT_X + 1.0
		and highway_lane == MAP.HIGHWAY_EXIT_LANE
	):
		_begin_ramp("offramp", true)
		return

	# Keep the freeway continuous after a missed exit until the second physical
	# interchange gives the player another chance to leave.
	highway_target_x -= MAP.HIGHWAY_STEP
	move_to = MAP.highway_lane_center(highway_lane, highway_target_x)
	scale_to = HIGHWAY_PLAYER_SCALE
	_set_motion_direction(move_to - move_from)


func _enter_city() -> void:
	road_kind = "city"
	local_area = "city"
	local_node = MAP.CITY_ENTRY
	previous_local_node = ""
	heading = Vector2i.DOWN
	queued_turn = 0
	visual_world_position = MAP.node_position("city", local_node)
	move_from = visual_world_position
	move_to = visual_world_position
	visual_scale = CITY_PLAYER_SCALE
	scale_from = visual_scale
	scale_to = visual_scale
	_begin_local_step()


func _begin_parking_entry() -> void:
	road_kind = "parking"
	parking_phase = 0
	parking_selected = 0
	move_to = MAP.PARKING_ENTRY
	scale_to = CITY_PLAYER_SCALE
	_set_motion_direction(move_to - move_from)
	status_label.text = "PARKING"


func _begin_parking_step() -> void:
	match parking_phase:
		0:
			parking_phase = 1
			move_to = MAP.PARKING_AISLE
			scale_to = CITY_PLAYER_SCALE
			_set_motion_direction(move_to - move_from)
		1:
			move_to = move_from
			scale_to = scale_from
			blocked_this_step = true
			status_label.text = "PARK ON RIGHT"
		2:
			_finish_drive()


func _turn_left() -> void:
	if not started or drive_complete:
		return

	if road_kind == "highway":
		_trigger_steering_feedback(-1.0)
		_set_highway_lane(queued_highway_lane - 1)
		return

	if road_kind == "parking":
		_handle_parking_turn(-1)
		return

	if road_kind == "neighborhood" or road_kind == "city":
		queued_turn = -1
		_trigger_steering_feedback(-1.0)
		if blocked_this_step:
			_begin_next_step()


func _turn_right() -> void:
	if not started or drive_complete:
		return

	if road_kind == "highway":
		_trigger_steering_feedback(1.0)
		_set_highway_lane(queued_highway_lane + 1)
		return

	if road_kind == "parking":
		_handle_parking_turn(1)
		return

	if road_kind == "neighborhood" or road_kind == "city":
		queued_turn = 1
		_trigger_steering_feedback(1.0)
		if blocked_this_step:
			_begin_next_step()


func _handle_parking_turn(direction: int) -> void:
	if parking_phase != 1 or not blocked_this_step:
		return

	# The left stall is visibly occupied. The right stall is the destination.
	if direction < 0:
		parking_selected = -1
		return

	parking_selected = 1
	parking_phase = 2
	blocked_this_step = false
	move_from = visual_world_position
	scale_from = visual_scale
	move_to = MAP.PARKING_RIGHT_SPACE
	scale_to = CITY_PLAYER_SCALE
	_set_motion_direction(move_to - move_from)


func _set_highway_lane(requested_lane: int) -> void:
	var new_lane := clampi(requested_lane, 0, MAP.HIGHWAY_LANES - 1)
	if new_lane == queued_highway_lane:
		return

	queued_highway_lane = new_lane
	highway_lane = new_lane
	move_from = visual_world_position
	scale_from = visual_scale
	move_to = MAP.highway_lane_center(highway_lane, highway_target_x)
	scale_to = HIGHWAY_PLAYER_SCALE
	_set_motion_direction(move_to - move_from)


func _set_motion_direction(delta: Vector2) -> void:
	if delta.length_squared() <= 0.001:
		return
	motion_direction = delta.normalized()
	map_rotation_from = map_rotation
	map_rotation_to = -PI / 2.0 - motion_direction.angle()
	turn_elapsed = 0.0


func _current_world_speed() -> float:
	match road_kind:
		"neighborhood":
			return NEIGHBORHOOD_WORLD_SPEED
		"onramp":
			return lerpf(
				NEIGHBORHOOD_WORLD_SPEED,
				HIGHWAY_WORLD_SPEED,
				_path_progress()
			)
		"highway":
			if highway_collision_slow_remaining > 0.0:
				return HIGHWAY_WORLD_SPEED * HIGHWAY_COLLISION_SPEED_MULTIPLIER
			return HIGHWAY_WORLD_SPEED
		"offramp":
			return lerpf(
				HIGHWAY_WORLD_SPEED,
				CITY_WORLD_SPEED,
				_path_progress()
			)
		"city":
			return CITY_WORLD_SPEED
		"parking":
			return PARKING_WORLD_SPEED
	return NEIGHBORHOOD_WORLD_SPEED


func _path_progress() -> float:
	if path_points.size() <= 1:
		return 0.0
	return clampf(
		float(path_index) / float(path_points.size() - 1),
		0.0,
		1.0
	)


func _current_world_zoom() -> float:
	match road_kind:
		"onramp":
			return lerpf(WORLD_ZOOM, HIGHWAY_ZOOM, _path_progress())
		"highway":
			return HIGHWAY_ZOOM
		"offramp":
			return lerpf(HIGHWAY_ZOOM, CITY_ZOOM, _path_progress())
		"city", "parking":
			return CITY_ZOOM
	return WORLD_ZOOM


func _trigger_steering_feedback(direction: float) -> void:
	steering_feedback = clampf(direction, -1.0, 1.0)
	camera_nudge = Vector2(
		-steering_feedback * CAMERA_COUNTER_NUDGE_PIXELS,
		0.0
	)


func _update_game_feel(delta: float) -> void:
	steering_feedback = move_toward(
		steering_feedback,
		0.0,
		STEERING_FEEDBACK_DECAY * delta
	)
	camera_nudge = camera_nudge.lerp(
		Vector2.ZERO,
		clampf(CAMERA_NUDGE_DECAY * delta, 0.0, 1.0)
	)


func _smootherstep(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


func _update_car_visual() -> void:
	var feedback := steering_feedback
	if road_kind == "onramp" or road_kind == "offramp":
		feedback = 0.0

	var sway := Vector2(feedback * STEERING_SWAY_PIXELS, 0.0)
	player_car.position = car_base_position + sway
	player_car.scale = Vector2.ONE * CAR_REFERENCE_SCALE * visual_scale
	player_car.rotation = feedback * STEERING_LEAN_RADIANS
	player_car.modulate = (
		Color(1.0, 0.58, 0.58, 1.0)
		if highway_collision_slow_remaining > 0.0
		else Color.WHITE
	)


func _update_highway_traffic(delta: float = 0.0) -> void:
	var visible := road_kind == "highway"

	for index in range(traffic_cars.size()):
		var traffic_car := traffic_cars[index]
		traffic_car.visible = visible
		if not visible:
			continue

		highway_traffic_offsets[index] -= HIGHWAY_TRAFFIC_APPROACH_SPEEDS[index] * delta
		if highway_traffic_offsets[index] < -12.0:
			highway_traffic_offsets[index] = (
				HIGHWAY_TRAFFIC_RESPAWN + float(index) * 42.0
			)

		var traffic_world := MAP.highway_lane_center(
			HIGHWAY_TRAFFIC_LANES[index],
			visual_world_position.x - highway_traffic_offsets[index]
		)

		if (
			absf(traffic_world.x - visual_world_position.x) <= HIGHWAY_COLLISION_LENGTH
			and absf(traffic_world.y - visual_world_position.y) <= HIGHWAY_COLLISION_LATERAL
		):
			_register_highway_collision(index)
			traffic_world.x = (
				visual_world_position.x - highway_traffic_offsets[index]
			)

		var screen_position := _world_to_screen(traffic_world)
		var traffic_scale := CAR_REFERENCE_SCALE * HIGHWAY_PLAYER_SCALE
		traffic_car.scale = Vector2.ONE * traffic_scale
		traffic_car.position = (
			screen_position - traffic_car.size * traffic_scale * 0.5
		)
		traffic_car.rotation = 0.0


func _register_highway_collision(index: int) -> void:
	bumps += 1
	highway_collision_slow_remaining = HIGHWAY_COLLISION_SLOW_SECONDS
	steering_feedback = 0.0
	camera_nudge = Vector2.ZERO
	highway_traffic_offsets[index] = (
		HIGHWAY_TRAFFIC_RESPAWN + float(index) * 42.0
	)


func current_local_route() -> Array[String]:
	if road_kind == "neighborhood":
		return MAP.shortest_path(
			"neighborhood",
			local_node,
			MAP.NEIGHBORHOOD_GATE
		)
	if road_kind == "city":
		return MAP.shortest_path(
			"city",
			local_node,
			MAP.CITY_PARKING_NODE
		)
	return []


func current_local_target() -> String:
	if road_kind == "neighborhood":
		return MAP.NEIGHBORHOOD_GATE
	if road_kind == "city":
		return MAP.CITY_PARKING_NODE
	return ""


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.085, 0.08), true)
	_draw_world_ground()
	_draw_highways()
	_draw_local_network("neighborhood")
	_draw_local_network("city")
	_draw_ramp(MAP.onramp_points())
	_draw_ramp(MAP.offramp_points())
	_draw_ramp(MAP.offramp_points(true))
	_draw_neighborhood_blocks()
	_draw_city_blocks()
	_draw_parking_and_venue()


func _draw_world_ground() -> void:
	_draw_world_rect(MAP.WORLD_RECT, LOCAL_GROUND)


func _draw_highways() -> void:
	_draw_highway_carriageway(MAP.OPPOSITE_HIGHWAY_RECT)
	_draw_highway_carriageway(MAP.HIGHWAY_RECT)

	var median := Rect2(
		Vector2(MAP.HIGHWAY_RECT.position.x, MAP.OPPOSITE_HIGHWAY_RECT.end.y),
		Vector2(
			MAP.HIGHWAY_RECT.size.x,
			MAP.HIGHWAY_RECT.position.y - MAP.OPPOSITE_HIGHWAY_RECT.end.y
		)
	)
	_draw_world_rect(median, HIGHWAY_MEDIAN)


func _draw_highway_carriageway(rect: Rect2) -> void:
	for lane in range(MAP.HIGHWAY_LANES):
		var lane_rect := Rect2(
			Vector2(
				rect.position.x,
				rect.position.y + lane * MAP.HIGHWAY_LANE_WIDTH
			),
			Vector2(rect.size.x, MAP.HIGHWAY_LANE_WIDTH)
		)
		_draw_world_rect(
			lane_rect,
			HIGHWAY_ASPHALT_ALT if lane % 2 == 1 else HIGHWAY_ASPHALT
		)

	for lane in range(1, MAP.HIGHWAY_LANES):
		var y := rect.position.y + lane * MAP.HIGHWAY_LANE_WIDTH
		var x := rect.position.x + 8.0
		while x < rect.end.x:
			_draw_world_line(
				Vector2(x, y),
				Vector2(minf(x + 14.0, rect.end.x), y),
				HIGHWAY_MARKING,
				0.9
			)
			x += 28.0

	_draw_world_line(rect.position, Vector2(rect.end.x, rect.position.y), HIGHWAY_EDGE, 1.2)
	_draw_world_line(
		Vector2(rect.position.x, rect.end.y),
		rect.end,
		HIGHWAY_EDGE,
		1.2
	)


func _draw_local_network(area: String) -> void:
	var sidewalk_color := LOCAL_SIDEWALK if area == "neighborhood" else CITY_SIDEWALK
	var road_color := LOCAL_ROAD if area == "neighborhood" else CITY_ROAD

	for edge in MAP.all_local_edges(area):
		var a := MAP.node_position(area, String(edge[0]))
		var b := MAP.node_position(area, String(edge[1]))
		_draw_world_line(a, b, sidewalk_color, MAP.LOCAL_SIDEWALK_WIDTH)
		_draw_world_line(a, b, road_color, MAP.LOCAL_ROAD_WIDTH)


func _draw_ramp(points: PackedVector2Array) -> void:
	_draw_world_polyline(
		points,
		RAMP_SHOULDER,
		MAP.HIGHWAY_LANE_WIDTH + 6.0
	)
	_draw_world_polyline(
		points,
		RAMP_ASPHALT,
		MAP.HIGHWAY_LANE_WIDTH
	)


func _draw_neighborhood_blocks() -> void:
	for row in range(2):
		for column in range(2):
			var base := Vector2(
				1275.0 + float(column) * 140.0,
				635.0 + float(row) * 140.0
			)
			for house_index in range(4):
				var offset := Vector2(
					float(house_index % 2) * 58.0,
					float(house_index / 2) * 58.0
				)
				_draw_world_rect(
					Rect2(base + offset, Vector2(38, 28)),
					HOUSE_COLORS[(row * 2 + column + house_index) % HOUSE_COLORS.size()]
				)


func _draw_city_blocks() -> void:
	for row in range(2):
		for column in range(2):
			var base := Vector2(
				205.0 + float(column) * 140.0,
				650.0 + float(row) * 140.0
			)
			_draw_world_rect(
				Rect2(base, Vector2(85, 74)),
				BUILDING_COLORS[(row * 2 + column) % BUILDING_COLORS.size()]
			)


func _draw_parking_and_venue() -> void:
	_draw_world_rect(MAP.PARKING_LOT_RECT, PARKING_ASPHALT)

	for center in [MAP.PARKING_LEFT_SPACE, MAP.PARKING_RIGHT_SPACE]:
		var rect := Rect2(center - Vector2(13, 22), Vector2(26, 44))
		_draw_world_rect_outline(rect, PARKING_LINE, 0.9)

	# Occupied left stall uses the real car asset.
	_draw_world_car_texture(
		MAP.PARKING_LEFT_SPACE,
		Color(0.72, 0.84, 1.0, 1.0),
		0.86
	)

	_draw_world_rect(MAP.VENUE_RECT, VENUE_COLOR)
	_draw_world_rect(
		Rect2(
			MAP.VENUE_RECT.position + Vector2(10, 18),
			Vector2(MAP.VENUE_RECT.size.x - 20, 20)
		),
		VENUE_TRIM
	)


func _draw_world_car_texture(
	world_center: Vector2,
	tint: Color,
	scale_multiplier: float
) -> void:
	var screen_center := _world_to_screen(world_center)
	var texture_size := PARKED_CAR_TEXTURE.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return

	var target_height := player_car.size.y * CAR_REFERENCE_SCALE * CITY_PLAYER_SCALE * scale_multiplier
	var aspect := texture_size.x / texture_size.y
	var screen_size := Vector2(target_height * aspect, target_height)

	draw_set_transform(screen_center, map_rotation, Vector2.ONE)
	draw_texture_rect(
		PARKED_CAR_TEXTURE,
		Rect2(-screen_size * 0.5, screen_size),
		false,
		tint
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
		world_width * _current_world_zoom(),
		true
	)


func _draw_world_rect(rect: Rect2, color: Color) -> void:
	var points := PackedVector2Array([
		_world_to_screen(rect.position),
		_world_to_screen(Vector2(rect.end.x, rect.position.y)),
		_world_to_screen(rect.end),
		_world_to_screen(Vector2(rect.position.x, rect.end.y)),
	])
	draw_colored_polygon(points, color)


func _draw_world_rect_outline(rect: Rect2, color: Color, width: float) -> void:
	var points := [
		_world_to_screen(rect.position),
		_world_to_screen(Vector2(rect.end.x, rect.position.y)),
		_world_to_screen(rect.end),
		_world_to_screen(Vector2(rect.position.x, rect.end.y)),
	]
	for index in range(4):
		draw_line(points[index], points[(index + 1) % 4], color, width, true)


func _draw_world_line(
	a: Vector2,
	b: Vector2,
	color: Color,
	world_width: float
) -> void:
	draw_line(
		_world_to_screen(a),
		_world_to_screen(b),
		color,
		world_width * _current_world_zoom(),
		true
	)


func _world_to_screen(world_point: Vector2) -> Vector2:
	var offset := (world_point - visual_world_position) * _current_world_zoom()
	offset = offset.rotated(map_rotation)
	return player_screen_center + offset + camera_nudge


func _finish_drive() -> void:
	if drive_complete:
		return

	drive_complete = true
	started = false
	status_label.text = "ARRIVED"
	left_button.disabled = true
	right_button.disabled = true
	trip_finished.emit({
		"status": "drive_complete",
		"real_drive_seconds": snappedf(drive_time, 0.1),
		"missed_turns": missed_turns,
		"wrong_way_tickets": 0,
		"bumps": bumps,
		"seed": world_seed,
	})


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
			_start_drive()
