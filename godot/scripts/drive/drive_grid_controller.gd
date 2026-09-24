extends Control

## DRIVE GRID v0.1
## A small playable proof of the Lego-grid driving idea.
## - one 880x800 logical board
## - modules snap to one master unit
## - one logical block per second
## - car scale comes directly from the current module cell size

signal trip_finished(result: Dictionary)

const MAP = preload("res://scripts/drive/drive_grid_map.gd")

const STEP_SECONDS := 1.0
const TURN_SECONDS := 0.34
const DISPLAY_SCALE := 1.0
const WORLD_SCALE := 2.0
const WORLD_ZOOM := 4.5 * DISPLAY_SCALE * WORLD_SCALE
const CITY_WORLD_ZOOM := WORLD_ZOOM * 0.72
const CAR_REFERENCE_SCALE := 0.65 * DISPLAY_SCALE
const CITY_CAR_SCALE := 1.5
const CITY_SPEED_MULTIPLIER := 0.8
const NEIGHBORHOOD_WORLD_SPEED := 40.0
const HIGHWAY_WORLD_SPEED := 80.0
const CITY_WORLD_SPEED := 32.0

const NEIGHBORHOOD_COLOR := Color(0.27, 0.43, 0.23)
const NEIGHBORHOOD_SIDEWALK_COLOR := Color(0.70, 0.67, 0.60)
const NEIGHBORHOOD_ROAD_COLOR := Color(0.16, 0.18, 0.22)
const NEIGHBORHOOD_ROAD_WIDTH := 26.0
const NEIGHBORHOOD_SIDEWALK_WIDTH := 34.0
const NEIGHBORHOOD_VISUAL_PADDING_CELLS := 1.5
const NEIGHBORHOOD_EDGE_COLOR := Color(0.24, 0.36, 0.20)
const RAMP_ASPHALT_COLOR := Color(0.12, 0.13, 0.15)
const RAMP_ASPHALT_ALT := Color(0.145, 0.155, 0.175)
const RAMP_SHOULDER_COLOR := Color(0.23, 0.24, 0.24)
const RAMP_EDGE_COLOR := Color(0.95, 0.94, 0.88, 0.92)
const RAMP_GUIDE_COLOR := Color(1.0, 0.78, 0.24, 0.90)
const RAMP_TEXTURE_COLOR := Color(0.04, 0.045, 0.055, 0.26)
const RAMP_TERRAIN_PADDING := 144.0
const HIGHWAY_ASPHALT_COLOR := Color(0.115, 0.125, 0.145)
const HIGHWAY_ASPHALT_ALT := Color(0.135, 0.145, 0.165)
const HIGHWAY_TEXTURE_COLOR := Color(0.04, 0.045, 0.055, 0.22)
const HIGHWAY_SHOULDER_COLOR := Color(0.20, 0.21, 0.22)
const HIGHWAY_MARKING_COLOR := Color(0.93, 0.92, 0.86, 0.92)
const HIGHWAY_EDGE_COLOR := Color(0.97, 0.96, 0.90, 0.96)
const HIGHWAY_EXIT_GUIDE_COLOR := Color(1.0, 0.78, 0.24, 0.90)
const HIGHWAY_TERRAIN_COLOR := Color(0.20, 0.29, 0.20)
const HIGHWAY_TERRAIN_ALT := Color(0.23, 0.32, 0.22)
const HIGHWAY_TERRAIN_GRID_COLOR := Color(0.08, 0.12, 0.08, 0.24)
const HIGHWAY_TERRAIN_PADDING := 180.0
const HIGHWAY_TERRAIN_CELL := 40.0
const CITY_GROUND_COLOR := Color(0.24, 0.255, 0.27)
const CITY_SIDEWALK_COLOR := Color(0.52, 0.52, 0.50)
const CITY_SIDEWALK_EDGE := Color(0.68, 0.67, 0.63, 0.55)
const CITY_ROAD_COLOR := Color(0.105, 0.115, 0.13)
const CITY_ROAD_WIDTH := 40.0
const CITY_SIDEWALK_WIDTH := 60.0
const CITY_BUILDING_COLORS := [
	Color(0.28, 0.25, 0.23),
	Color(0.32, 0.30, 0.28),
	Color(0.25, 0.29, 0.31),
	Color(0.34, 0.27, 0.24),
]
const CITY_ROOF_DETAIL := Color(0.10, 0.11, 0.12, 0.26)
const VENUE_BUILDING_COLOR := Color(0.18, 0.16, 0.15)
const VENUE_ROOF_COLOR := Color(0.13, 0.125, 0.12)
const VENUE_TRIM_COLOR := Color(0.08, 0.085, 0.09)
const VENUE_WINDOW_COLOR := Color(0.96, 0.66, 0.28, 0.88)
const VENUE_AWNING_COLOR := Color(0.42, 0.16, 0.13)
const VENUE_SIGN_COLOR := Color(0.78, 0.47, 0.22)
const VENUE_SIDEWALK_COLOR := Color(0.48, 0.48, 0.46)
const PARKING_LINE_COLOR := Color(0.92, 0.91, 0.84, 0.50)
const STEERING_LEAN_RADIANS := 0.085
const STEERING_SWAY_PIXELS := 0.75
const CAR_STEERING_PIVOT_Y_RATIO := 0.28
const CAMERA_COUNTER_NUDGE_PIXELS := 5.0
const STEERING_FEEDBACK_DECAY := 5.5
const CAMERA_NUDGE_DECAY := 7.0
const DRIFT_TAIL_START := 0.62
const DRIFT_TAIL_END := 1.0
const GRID_COLOR := Color(0.08, 0.09, 0.09, 0.45)
const BORDER_COLOR := Color(0.93, 0.92, 0.86)

@export var world_seed: int = 0

var started := false
var drive_complete := false
var parking_maneuver_started := false
var drive_time := 0.0
var missed_turns := 0
var steering_feedback := 0.0
var turn_drift_direction := 0.0
var camera_nudge := Vector2.ZERO

var road_kind := "neighborhood"

var neighborhood_cell := MAP.NEIGHBORHOOD_START
var city_cell := MAP.CITY_ENTRY
var heading := Vector2i.UP

var highway_column := 0
var highway_lane := MAP.HIGHWAY_ENTRY_LANE
var queued_highway_lane := MAP.HIGHWAY_ENTRY_LANE
var highway_lap := 0

var move_from := Vector2.ZERO
var move_to := Vector2.ZERO
var scale_from := 1.0
var scale_to := 1.0
var visual_world_position := Vector2.ZERO
var visual_cell_scale := 1.0
var motion_direction := Vector2.UP
var blocked_this_step := false

var map_rotation := 0.0
var map_rotation_from := 0.0
var map_rotation_to := 0.0
var turn_elapsed := TURN_SECONDS

var player_screen_center := Vector2.ZERO
var car_base_position := Vector2.ZERO

@onready var player_car: TextureRect = $"../PlayerCar"
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
	queue_redraw()


func _reset_to_start() -> void:
	started = false
	drive_complete = false
	parking_maneuver_started = false
	drive_time = 0.0
	missed_turns = 0
	steering_feedback = 0.0
	turn_drift_direction = 0.0
	camera_nudge = Vector2.ZERO
	road_kind = "neighborhood"
	neighborhood_cell = MAP.NEIGHBORHOOD_START
	city_cell = MAP.CITY_ENTRY
	heading = Vector2i.UP
	highway_column = 0
	highway_lane = MAP.HIGHWAY_ENTRY_LANE
	queued_highway_lane = highway_lane
	highway_lap = 0
	visual_world_position = MAP.neighborhood_cell_center(neighborhood_cell)
	visual_cell_scale = MAP.car_scale_for_cell(MAP.NEIGHBORHOOD_CELL)
	move_from = visual_world_position
	move_to = visual_world_position
	scale_from = visual_cell_scale
	scale_to = visual_cell_scale
	blocked_this_step = false
	map_rotation = 0.0
	map_rotation_from = 0.0
	map_rotation_to = 0.0
	turn_elapsed = TURN_SECONDS
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
		queue_redraw()
		return

	drive_time += delta
	turn_elapsed += delta
	_update_game_feel(delta)

	if turn_elapsed < TURN_SECONDS:
		var turn_t := clampf(turn_elapsed / TURN_SECONDS, 0.0, 1.0)
		map_rotation = lerp_angle(
			map_rotation_from,
			map_rotation_to,
			_ease_turn_in_out(turn_t)
		)
		if absf(turn_drift_direction) > 0.001:
			steering_feedback = _late_fishtail_amount(turn_t) * turn_drift_direction
	else:
		map_rotation = map_rotation_to
		if absf(turn_drift_direction) > 0.001:
			turn_drift_direction = 0.0
			steering_feedback = 0.0

	_advance_continuous_motion(delta)

	_update_car_visual()
	queue_redraw()


func _advance_continuous_motion(delta: float) -> void:
	var remaining_time := delta

	while remaining_time > 0.0 and not drive_complete:
		if blocked_this_step:
			return

		var distance_to_target := visual_world_position.distance_to(move_to)
		if distance_to_target <= 0.001:
			visual_world_position = move_to
			visual_cell_scale = scale_to
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
			visual_cell_scale = lerpf(
				scale_from,
				scale_to,
				clampf(progress, 0.0, 1.0)
			)

		remaining_time -= travel_time

		if visual_world_position.distance_to(move_to) <= 0.001:
			visual_world_position = move_to
			visual_cell_scale = scale_to
			_begin_next_step()


func _current_world_speed() -> float:
	match road_kind:
		"neighborhood":
			return NEIGHBORHOOD_WORLD_SPEED
		"highway":
			return HIGHWAY_WORLD_SPEED
		"city":
			return CITY_WORLD_SPEED
		"connector_one":
			return lerpf(
				NEIGHBORHOOD_WORLD_SPEED,
				HIGHWAY_WORLD_SPEED,
				_connector_one_progress()
			)
		"connector_two":
			return lerpf(
				HIGHWAY_WORLD_SPEED,
				CITY_WORLD_SPEED,
				_connector_two_progress()
			)
	return NEIGHBORHOOD_WORLD_SPEED


func _connector_one_progress() -> float:
	var ramp_start := MAP.CONNECTOR_ONE_RECT.position.x
	var ramp_end := MAP.CONNECTOR_ONE_RECT.end.x
	return clampf(
		inverse_lerp(ramp_start, ramp_end, visual_world_position.x),
		0.0,
		1.0
	)


func _connector_two_progress() -> float:
	var rect := _connector_two_rect()
	return clampf(
		inverse_lerp(rect.position.x, rect.end.x, visual_world_position.x),
		0.0,
		1.0
	)


func _begin_next_step() -> void:
	move_from = visual_world_position
	scale_from = visual_cell_scale
	blocked_this_step = false

	match road_kind:
		"neighborhood":
			_begin_neighborhood_step()
		"connector_one":
			_begin_highway_step()
		"highway":
			_begin_highway_step()
		"connector_two":
			_begin_city_step()
		"city":
			_begin_city_step()


func _begin_neighborhood_step() -> void:
	var desired := neighborhood_cell + heading

	if (
		_cell_inside(desired, MAP.NEIGHBORHOOD_SIZE)
		and MAP.neighborhood_cells_connect(neighborhood_cell, desired)
	):
		neighborhood_cell = desired
		move_to = MAP.neighborhood_cell_center(neighborhood_cell)
		scale_to = MAP.car_scale_for_cell(MAP.NEIGHBORHOOD_CELL)
		motion_direction = Vector2(heading)
		status_label.text = "NEIGHBORHOOD"
		return

	if (
		neighborhood_cell == MAP.NEIGHBORHOOD_GATE
		and heading == MAP.NEIGHBORHOOD_GATE_SIDE
	):
		road_kind = "connector_one"
		_stabilize_for_connector()
		move_to = MAP.highway_entry_point()
		scale_to = MAP.car_scale_for_cell(MAP.HIGHWAY_CELL)
		motion_direction = (move_to - move_from).normalized()
		status_label.text = "CONNECTOR"
		return

	move_to = move_from
	scale_to = scale_from
	blocked_this_step = true
	status_label.text = "WALL - TURN"


func _begin_highway_step() -> void:
	if road_kind == "connector_one":
		road_kind = "highway"
		highway_column = 0
		highway_lane = MAP.HIGHWAY_ENTRY_LANE
		queued_highway_lane = highway_lane
		highway_lap = 0

	if highway_column >= MAP.HIGHWAY_COLUMNS - 1:
		if highway_lane == MAP.HIGHWAY_EXIT_LANE:
			road_kind = "connector_two"
			_stabilize_for_connector()
			move_to = _city_entry_point()
			# The off-ramp widens to a full city-block width, so the car can
			# grow smoothly all the way to its city scale before crossing in.
			scale_to = CITY_CAR_SCALE
			motion_direction = (move_to - move_from).normalized()
			status_label.text = "CONNECTOR"
			return

		# Missing the exit should feel like continuing down the same highway.
		# Advance the visual highway by one full span instead of teleporting the
		# player back to the original beginning.
		missed_turns += 1
		highway_lap += 1
		highway_column = 0
		highway_lane = queued_highway_lane
		move_to = _highway_cell_center(highway_column, highway_lane)
		scale_to = MAP.car_scale_for_cell(MAP.HIGHWAY_CELL)
		motion_direction = (move_to - move_from).normalized()
		status_label.text = "HIGHWAY  •  EXIT LANE 4"
		return

	highway_column += 1
	highway_lane = queued_highway_lane
	move_to = _highway_cell_center(highway_column, highway_lane)
	scale_to = MAP.car_scale_for_cell(MAP.HIGHWAY_CELL)
	motion_direction = (move_to - move_from).normalized()
	status_label.text = "HIGHWAY  •  EXIT LANE 4"


func _begin_city_step() -> void:
	if road_kind == "connector_two":
		road_kind = "city"
		city_cell = MAP.CITY_ENTRY
		heading = Vector2i.RIGHT

	if city_cell == MAP.CITY_DESTINATION:
		if not parking_maneuver_started:
			parking_maneuver_started = true
			move_to = _parking_stop_point()
			scale_to = CITY_CAR_SCALE
			motion_direction = (move_to - move_from).normalized()
			status_label.text = "PARKING"
			return

		_finish_drive()
		return

	var desired := city_cell + heading
	if _cell_inside(desired, MAP.CITY_SIZE):
		city_cell = desired
		move_to = _city_cell_center(city_cell)
		scale_to = CITY_CAR_SCALE
		motion_direction = Vector2(heading)
		status_label.text = "CITY"
		return

	move_to = move_from
	scale_to = scale_from
	blocked_this_step = true
	status_label.text = "CITY EDGE - TURN"


func _turn_left() -> void:
	if not started or drive_complete:
		return

	if road_kind == "highway":
		_trigger_steering_feedback(-1.0)
		_set_highway_lane(queued_highway_lane - 1)
		return

	if road_kind == "neighborhood" or road_kind == "city":
		turn_drift_direction = -1.0
		_set_heading(Vector2i(heading.y, -heading.x))


func _turn_right() -> void:
	if not started or drive_complete:
		return

	if road_kind == "highway":
		_trigger_steering_feedback(1.0)
		_set_highway_lane(queued_highway_lane + 1)
		return

	if road_kind == "neighborhood" or road_kind == "city":
		turn_drift_direction = 1.0
		_set_heading(Vector2i(-heading.y, heading.x))


func _set_highway_lane(requested_lane: int) -> void:
	var new_lane := clampi(requested_lane, 0, MAP.HIGHWAY_LANES - 1)
	if new_lane == queued_highway_lane:
		return

	queued_highway_lane = new_lane
	highway_lane = new_lane

	# Retarget the active highway segment immediately so the merge begins on tap,
	# rather than waiting for the next forward grid checkpoint.
	move_from = visual_world_position
	move_to = _highway_cell_center(highway_column, new_lane)
	motion_direction = (move_to - visual_world_position).normalized()


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


func _stabilize_for_connector() -> void:
	steering_feedback = 0.0
	turn_drift_direction = 0.0
	camera_nudge = Vector2.ZERO
	player_car.rotation = 0.0


func _ease_turn_in_out(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	# Smootherstep: zero angular velocity at both ends, fastest in the middle.
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


func _late_fishtail_amount(t: float) -> float:
	if t <= DRIFT_TAIL_START or t >= DRIFT_TAIL_END:
		return 0.0
	var phase := inverse_lerp(DRIFT_TAIL_START, DRIFT_TAIL_END, t)
	# One clean rear-end kick near the end of the turn, then settle to center.
	return sin(phase * PI)


func _set_heading(new_heading: Vector2i) -> void:
	heading = new_heading
	map_rotation_from = map_rotation
	map_rotation_to = -PI / 2.0 - Vector2(heading).angle()
	turn_elapsed = 0.0

	if blocked_this_step:
		_begin_next_step()


func _cell_inside(cell: Vector2i, grid_size: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < grid_size.x
		and cell.y < grid_size.y
	)


func _update_car_visual() -> void:
	var visual_feedback := steering_feedback
	if road_kind.begins_with("connector"):
		visual_feedback = 0.0

	var sway := Vector2(
		visual_feedback * STEERING_SWAY_PIXELS,
		0.0
	)
	player_car.position = car_base_position + sway
	player_car.scale = Vector2.ONE * CAR_REFERENCE_SCALE * visual_cell_scale
	player_car.rotation = visual_feedback * STEERING_LEAN_RADIANS


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.085, 0.08), true)

	# Fill the space around the ramps before drawing the neighborhood/highway
	# on top, so there is never a black void between map modules.
	_draw_connector_surroundings()
	_draw_neighborhood()

	_draw_highway_surroundings()
	_draw_connector_one()
	_draw_highway()
	_draw_city_connector()

	_draw_city()
	_draw_destination()
	_draw_map_outline()


func _draw_neighborhood() -> void:
	# Draw the 4x4 neighborhood as sixteen road tiles:
	# corners are L-turns, perimeter cells are inward-facing T-junctions,
	# and the four interior cells are four-way intersections.
	# The car always sits at a tile center, so art and movement stay identical.
	var rect := MAP.NEIGHBORHOOD_RECT
	var padding := float(MAP.NEIGHBORHOOD_CELL * NEIGHBORHOOD_VISUAL_PADDING_CELLS)

	_draw_world_rect(rect.grow(padding), NEIGHBORHOOD_EDGE_COLOR)
	_draw_world_rect(rect, NEIGHBORHOOD_COLOR)

	for y in range(MAP.NEIGHBORHOOD_SIZE.y):
		for x in range(MAP.NEIGHBORHOOD_SIZE.x):
			_draw_neighborhood_cell(Vector2i(x, y))


func _draw_neighborhood_cell(cell: Vector2i) -> void:
	var center := MAP.neighborhood_cell_center(cell)
	var connections: Array[Vector2i] = MAP.neighborhood_connections(cell)

	# Draw the sidewalk footprint first, then the road on top.
	for direction in connections:
		_draw_neighborhood_arm(
			center,
			direction,
			NEIGHBORHOOD_SIDEWALK_WIDTH,
			NEIGHBORHOOD_SIDEWALK_COLOR
		)

	_draw_world_rect(
		Rect2(
			center - Vector2.ONE * NEIGHBORHOOD_SIDEWALK_WIDTH * 0.5,
			Vector2.ONE * NEIGHBORHOOD_SIDEWALK_WIDTH
		),
		NEIGHBORHOOD_SIDEWALK_COLOR
	)

	for direction in connections:
		_draw_neighborhood_arm(
			center,
			direction,
			NEIGHBORHOOD_ROAD_WIDTH,
			NEIGHBORHOOD_ROAD_COLOR
		)

	_draw_world_rect(
		Rect2(
			center - Vector2.ONE * NEIGHBORHOOD_ROAD_WIDTH * 0.5,
			Vector2.ONE * NEIGHBORHOOD_ROAD_WIDTH
		),
		NEIGHBORHOOD_ROAD_COLOR
	)


func _draw_neighborhood_arm(
	center: Vector2,
	direction: Vector2i,
	width: float,
	color: Color
) -> void:
	var half_cell := float(MAP.NEIGHBORHOOD_CELL) * 0.5
	var half_width := width * 0.5

	if direction == Vector2i.UP:
		_draw_world_rect(
			Rect2(
				Vector2(center.x - half_width, center.y - half_cell),
				Vector2(width, half_cell)
			),
			color
		)
	elif direction == Vector2i.DOWN:
		_draw_world_rect(
			Rect2(
				Vector2(center.x - half_width, center.y),
				Vector2(width, half_cell)
			),
			color
		)
	elif direction == Vector2i.LEFT:
		_draw_world_rect(
			Rect2(
				Vector2(center.x - half_cell, center.y - half_width),
				Vector2(half_cell, width)
			),
			color
		)
	elif direction == Vector2i.RIGHT:
		_draw_world_rect(
			Rect2(
				Vector2(center.x, center.y - half_width),
				Vector2(half_cell, width)
			),
			color
		)


func _draw_city() -> void:
	var rect := _city_rect()
	_draw_world_rect(rect, CITY_GROUND_COLOR)
	_draw_city_buildings(rect)

	# City roads follow the same border rule as the neighborhood: perimeter
	# intersections stop at the city edge, and only the actual entry cell opens
	# outward toward the off-ramp.
	for y in range(MAP.CITY_SIZE.y):
		for x in range(MAP.CITY_SIZE.x):
			_draw_city_intersection(Vector2i(x, y))

	_draw_world_rect_outline(rect, Color(0.10, 0.11, 0.12, 0.55), 1.0)


func _city_connections(cell: Vector2i) -> Array[Vector2i]:
	# Match the locked neighborhood topology exactly:
	# - corners are two-way turns
	# - perimeter non-corners are inward-facing three-way intersections
	# - interior cells are four-way intersections
	# The off-ramp adds the one intentional opening through the city border.
	var max_x := MAP.CITY_SIZE.x - 1
	var max_y := MAP.CITY_SIZE.y - 1
	var connections: Array[Vector2i] = []

	if cell == Vector2i(0, 0):
		connections = [Vector2i.RIGHT, Vector2i.DOWN]
	elif cell == Vector2i(max_x, 0):
		connections = [Vector2i.LEFT, Vector2i.DOWN]
	elif cell == Vector2i(0, max_y):
		connections = [Vector2i.RIGHT, Vector2i.UP]
	elif cell == Vector2i(max_x, max_y):
		connections = [Vector2i.LEFT, Vector2i.UP]
	elif cell.y == 0:
		connections = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]
	elif cell.y == max_y:
		connections = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]
	elif cell.x == 0:
		connections = [Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT]
	elif cell.x == max_x:
		connections = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT]
	else:
		connections = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

	if cell == MAP.CITY_ENTRY and not connections.has(Vector2i.LEFT):
		connections.append(Vector2i.LEFT)

	return connections


func _draw_city_intersection(cell: Vector2i) -> void:
	var center := _city_cell_center(cell)
	var connections: Array[Vector2i] = _city_connections(cell)

	# Build each city tile the same way as the neighborhood tile system:
	# sidewalk arms first, then one continuous asphalt color on top.
	for direction in connections:
		_draw_city_arm(
			center,
			direction,
			CITY_SIDEWALK_WIDTH,
			CITY_SIDEWALK_COLOR
		)

	_draw_world_rect(
		Rect2(
			center - Vector2.ONE * CITY_SIDEWALK_WIDTH * 0.5,
			Vector2.ONE * CITY_SIDEWALK_WIDTH
		),
		CITY_SIDEWALK_COLOR
	)

	for direction in connections:
		_draw_city_arm(
			center,
			direction,
			CITY_ROAD_WIDTH,
			CITY_ROAD_COLOR
		)

	_draw_world_rect(
		Rect2(
			center - Vector2.ONE * CITY_ROAD_WIDTH * 0.5,
			Vector2.ONE * CITY_ROAD_WIDTH
		),
		CITY_ROAD_COLOR
	)


func _draw_city_arm(
	center: Vector2,
	direction: Vector2i,
	width: float,
	color: Color
) -> void:
	var half_cell := float(MAP.CITY_CELL) * 0.5
	var half_width := width * 0.5

	if direction == Vector2i.UP:
		_draw_world_rect(
			Rect2(
				Vector2(center.x - half_width, center.y - half_cell),
				Vector2(width, half_cell)
			),
			color
		)
	elif direction == Vector2i.DOWN:
		_draw_world_rect(
			Rect2(
				Vector2(center.x - half_width, center.y),
				Vector2(width, half_cell)
			),
			color
		)
	elif direction == Vector2i.LEFT:
		_draw_world_rect(
			Rect2(
				Vector2(center.x - half_cell, center.y - half_width),
				Vector2(half_cell, width)
			),
			color
		)
	elif direction == Vector2i.RIGHT:
		_draw_world_rect(
			Rect2(
				Vector2(center.x, center.y - half_width),
				Vector2(half_cell, width)
			),
			color
		)


func _draw_city_buildings(rect: Rect2) -> void:
	# Nine rooftops fill the interior blocks. The destination block is left
	# quieter so the curbside venue outside the city edge becomes the focus.
	for row in range(MAP.CITY_SIZE.y - 1):
		for column in range(MAP.CITY_SIZE.x - 1):
			# Keep the block immediately beside the parking destination clear for
			# the venue so it reads as one deliberate place, not stacked rooftops.
			if row == 0 and column == 2:
				continue

			var left_center := rect.position.x + (float(column) + 0.5) * MAP.CITY_CELL
			var right_center := left_center + MAP.CITY_CELL
			var top_center := rect.position.y + (float(row) + 0.5) * MAP.CITY_CELL
			var bottom_center := top_center + MAP.CITY_CELL
			var inset := CITY_SIDEWALK_WIDTH * 0.5 + 3.0
			var building_rect := Rect2(
				Vector2(left_center + inset, top_center + inset),
				Vector2(
					right_center - left_center - inset * 2.0,
					bottom_center - top_center - inset * 2.0
				)
			)
			var color_index := (row * 3 + column) % CITY_BUILDING_COLORS.size()
			_draw_world_rect(building_rect, CITY_BUILDING_COLORS[color_index])

			var roof_detail := Rect2(
				building_rect.position + Vector2(4.0, 4.0),
				Vector2(
					maxf(4.0, building_rect.size.x * 0.26),
					maxf(4.0, building_rect.size.y * 0.20)
				)
			)
			_draw_world_rect(roof_detail, CITY_ROOF_DETAIL)


func _draw_grid_zone(rect: Rect2, cell_size: int, color: Color) -> void:
	_draw_world_rect(rect, color)

	var x := rect.position.x + cell_size
	while x < rect.end.x:
		_draw_world_line(
			Vector2(x, rect.position.y),
			Vector2(x, rect.end.y),
			GRID_COLOR,
			1.5
		)
		x += cell_size

	var y := rect.position.y + cell_size
	while y < rect.end.y:
		_draw_world_line(
			Vector2(rect.position.x, y),
			Vector2(rect.end.x, y),
			GRID_COLOR,
			1.5
		)
		y += cell_size


func _draw_neighborhood_border_with_gate() -> void:
	var rect := MAP.NEIGHBORHOOD_RECT
	var gate_cell := MAP.NEIGHBORHOOD_GATE
	var gate_top := rect.position.y + gate_cell.y * MAP.NEIGHBORHOOD_CELL
	var gate_bottom := gate_top + MAP.NEIGHBORHOOD_CELL

	_draw_world_line(rect.position, Vector2(rect.end.x, rect.position.y), BORDER_COLOR, 4.0)
	_draw_world_line(Vector2(rect.position.x, rect.end.y), rect.end, BORDER_COLOR, 4.0)
	_draw_world_line(rect.position, Vector2(rect.position.x, rect.end.y), BORDER_COLOR, 4.0)

	_draw_world_line(
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x, gate_top),
		BORDER_COLOR,
		4.0
	)
	_draw_world_line(
		Vector2(rect.end.x, gate_bottom),
		Vector2(rect.end.x, rect.end.y),
		BORDER_COLOR,
		4.0
	)


func _draw_connector_surroundings() -> void:
	# Reuse the highway terrain language around both ramps. Drawn first so
	# neighborhood/highway/city geometry can naturally cover the patch edges.
	_draw_terrain_patch(MAP.CONNECTOR_ONE_RECT.grow(RAMP_TERRAIN_PADDING), 1)
	_draw_terrain_patch(_connector_two_rect().grow(RAMP_TERRAIN_PADDING), 2)


func _draw_terrain_patch(rect: Rect2, phase: int) -> void:
	var columns := int(ceil(rect.size.x / HIGHWAY_TERRAIN_CELL))
	var rows := int(ceil(rect.size.y / HIGHWAY_TERRAIN_CELL))

	for row in range(rows):
		for column in range(columns):
			var cell_position := rect.position + Vector2(
				float(column) * HIGHWAY_TERRAIN_CELL,
				float(row) * HIGHWAY_TERRAIN_CELL
			)
			var cell_size := Vector2(
				minf(HIGHWAY_TERRAIN_CELL, rect.end.x - cell_position.x),
				minf(HIGHWAY_TERRAIN_CELL, rect.end.y - cell_position.y)
			)
			var color := HIGHWAY_TERRAIN_COLOR
			if (row + column + phase) % 2 == 1:
				color = HIGHWAY_TERRAIN_ALT
			_draw_world_rect(Rect2(cell_position, cell_size), color)

	var x := rect.position.x + HIGHWAY_TERRAIN_CELL
	while x < rect.end.x:
		_draw_world_line(
			Vector2(x, rect.position.y),
			Vector2(x, rect.end.y),
			HIGHWAY_TERRAIN_GRID_COLOR,
			0.8
		)
		x += HIGHWAY_TERRAIN_CELL

	var y := rect.position.y + HIGHWAY_TERRAIN_CELL
	while y < rect.end.y:
		_draw_world_line(
			Vector2(rect.position.x, y),
			Vector2(rect.end.x, y),
			HIGHWAY_TERRAIN_GRID_COLOR,
			0.8
		)
		y += HIGHWAY_TERRAIN_CELL


func _draw_connector_one() -> void:
	# On-ramp: narrow where it leaves the neighborhood, then opens into the
	# highway merge area.
	var shoulder := _connector_one_points(2.5)
	var asphalt := _connector_one_points(0.0)
	_draw_world_polygon(shoulder, RAMP_SHOULDER_COLOR)
	_draw_world_polygon(asphalt, RAMP_ASPHALT_COLOR)
	_draw_ramp_edges(asphalt, true)
	_draw_ramp_texture(asphalt, 0)


func _draw_city_connector() -> void:
	# Off-ramp: starts as a highway lane and fans out toward the city street.
	var shoulder := _connector_two_points(2.5)
	var asphalt := _connector_two_points(0.0)
	_draw_world_polygon(shoulder, RAMP_SHOULDER_COLOR)
	_draw_world_polygon(asphalt, RAMP_ASPHALT_ALT)
	_draw_ramp_edges(asphalt, false)
	_draw_ramp_texture(asphalt, 1)


func _connector_one_points(extra_width: float = 0.0) -> PackedVector2Array:
	var rect := MAP.CONNECTOR_ONE_RECT
	var start_center_y := MAP.neighborhood_cell_center(MAP.NEIGHBORHOOD_GATE).y
	var end_center_y := MAP.highway_entry_point().y
	var start_half_width := NEIGHBORHOOD_ROAD_WIDTH * 0.5 + extra_width
	var end_half_width := 28.0 + extra_width

	return PackedVector2Array([
		Vector2(rect.position.x, start_center_y - start_half_width),
		Vector2(rect.end.x, end_center_y - end_half_width),
		Vector2(rect.end.x, end_center_y + end_half_width),
		Vector2(rect.position.x, start_center_y + start_half_width),
	])


func _connector_two_points(extra_width: float = 0.0) -> PackedVector2Array:
	var rect := _connector_two_rect()
	var start_center_y := _highway_cell_center(
		MAP.HIGHWAY_COLUMNS - 1,
		MAP.HIGHWAY_EXIT_LANE
	).y
	var end_center_y := _city_entry_point().y
	var start_half_width := MAP.HIGHWAY_LANE_WIDTH * 0.5 + extra_width
	var end_half_width := 44.0 + extra_width

	return PackedVector2Array([
		Vector2(rect.position.x, start_center_y - start_half_width),
		Vector2(rect.end.x, end_center_y - end_half_width),
		Vector2(rect.end.x, end_center_y + end_half_width),
		Vector2(rect.position.x, start_center_y + start_half_width),
	])


func _draw_ramp_edges(points: PackedVector2Array, on_ramp: bool) -> void:
	if points.size() != 4:
		return

	# One warm guide edge and one neutral edge make the ramps read as dedicated
	# merge/diverge lanes rather than another generic road rectangle.
	var upper_color := RAMP_GUIDE_COLOR if on_ramp else RAMP_EDGE_COLOR
	var lower_color := RAMP_EDGE_COLOR if on_ramp else RAMP_GUIDE_COLOR

	_draw_world_line(points[0], points[1], upper_color, 1.15)
	_draw_world_line(points[3], points[2], lower_color, 1.15)

	# Short dashed merge/diverge cue near the highway mouth.
	var cue_start := points[0].lerp(points[1], 0.62)
	var cue_end := points[0].lerp(points[1], 0.88)
	if not on_ramp:
		cue_start = points[3].lerp(points[2], 0.12)
		cue_end = points[3].lerp(points[2], 0.38)
	_draw_world_line(cue_start, cue_end, RAMP_EDGE_COLOR, 0.85)


func _draw_ramp_texture(points: PackedVector2Array, phase: int) -> void:
	if points.size() != 4:
		return

	for index in range(4):
		var t := 0.24 + float(index) * 0.18
		var top := points[0].lerp(points[1], t)
		var bottom := points[3].lerp(points[2], t)
		var center := top.lerp(bottom, 0.5)
		var offset := float(((index + phase) % 3) - 1) * 0.9
		_draw_world_line(
			center + Vector2(-3.5, offset),
			center + Vector2(3.5, offset),
			RAMP_TEXTURE_COLOR,
			0.55
		)


func _draw_highway_surroundings() -> void:
	for lap in range(maxi(0, highway_lap - 1), highway_lap + 2):
		_draw_highway_surroundings_for_lap(lap)


func _draw_highway_surroundings_for_lap(lap: int) -> void:
	var highway_rect := _highway_rect_for_lap(lap)
	var rect := Rect2(
		Vector2(
			highway_rect.position.x,
			highway_rect.position.y - HIGHWAY_TERRAIN_PADDING
		),
		Vector2(
			highway_rect.size.x,
			highway_rect.size.y + HIGHWAY_TERRAIN_PADDING * 2.0
		)
	)

	var columns := int(ceil(rect.size.x / HIGHWAY_TERRAIN_CELL))
	var rows := int(ceil(rect.size.y / HIGHWAY_TERRAIN_CELL))

	for row in range(rows):
		for column in range(columns):
			var cell_position := rect.position + Vector2(
				float(column) * HIGHWAY_TERRAIN_CELL,
				float(row) * HIGHWAY_TERRAIN_CELL
			)
			var cell_size := Vector2(
				minf(HIGHWAY_TERRAIN_CELL, rect.end.x - cell_position.x),
				minf(HIGHWAY_TERRAIN_CELL, rect.end.y - cell_position.y)
			)
			var color := HIGHWAY_TERRAIN_COLOR
			if (row + column + lap) % 2 == 1:
				color = HIGHWAY_TERRAIN_ALT
			_draw_world_rect(Rect2(cell_position, cell_size), color)

	var x := rect.position.x + HIGHWAY_TERRAIN_CELL
	while x < rect.end.x:
		_draw_world_line(
			Vector2(x, rect.position.y),
			Vector2(x, rect.end.y),
			HIGHWAY_TERRAIN_GRID_COLOR,
			0.8
		)
		x += HIGHWAY_TERRAIN_CELL

	var y := rect.position.y + HIGHWAY_TERRAIN_CELL
	while y < rect.end.y:
		_draw_world_line(
			Vector2(rect.position.x, y),
			Vector2(rect.end.x, y),
			HIGHWAY_TERRAIN_GRID_COLOR,
			0.8
		)
		y += HIGHWAY_TERRAIN_CELL


func _draw_highway() -> void:
	# Draw the current stretch plus the next stretch so missing the exit never
	# exposes the end of the highway or reveals a reset.
	for lap in range(maxi(0, highway_lap - 1), highway_lap + 2):
		_draw_highway_for_lap(lap)


func _draw_highway_for_lap(lap: int) -> void:
	var rect := _highway_rect_for_lap(lap)

	for lane in range(MAP.HIGHWAY_LANES):
		var lane_rect := Rect2(
			Vector2(
				rect.position.x,
				rect.position.y + lane * MAP.HIGHWAY_LANE_WIDTH
			),
			Vector2(rect.size.x, MAP.HIGHWAY_LANE_WIDTH)
		)
		var lane_color := HIGHWAY_ASPHALT_COLOR
		if lane % 2 == 1:
			lane_color = HIGHWAY_ASPHALT_ALT
		_draw_world_rect(lane_rect, lane_color)

	var shoulder_width := 2.2
	_draw_world_rect(
		Rect2(
			rect.position,
			Vector2(rect.size.x, shoulder_width)
		),
		HIGHWAY_SHOULDER_COLOR
	)
	_draw_world_rect(
		Rect2(
			Vector2(rect.position.x, rect.end.y - shoulder_width),
			Vector2(rect.size.x, shoulder_width)
		),
		HIGHWAY_SHOULDER_COLOR
	)

	for column in range(MAP.HIGHWAY_COLUMNS):
		var column_x := rect.position.x + float(column) * MAP.HIGHWAY_CELL
		for lane in range(MAP.HIGHWAY_LANES):
			var lane_center_y := (
				rect.position.y
				+ float(lane) * MAP.HIGHWAY_LANE_WIDTH
				+ MAP.HIGHWAY_LANE_WIDTH * 0.5
			)
			var offset_y := float(((column + lane * 2 + lap) % 3) - 1) * 1.15
			var streak_start := column_x + 3.0 + float((column + lane + lap) % 3)
			var streak_length := 5.0 + float((column * 2 + lane + lap) % 4)
			_draw_world_line(
				Vector2(streak_start, lane_center_y + offset_y),
				Vector2(streak_start + streak_length, lane_center_y + offset_y),
				HIGHWAY_TEXTURE_COLOR,
				0.65
			)

	for lane in range(1, MAP.HIGHWAY_LANES):
		var divider_y := rect.position.y + lane * MAP.HIGHWAY_LANE_WIDTH
		var dash_x := rect.position.x + 4.0
		while dash_x < rect.end.x:
			var dash_end := minf(dash_x + 8.0, rect.end.x)
			_draw_world_line(
				Vector2(dash_x, divider_y),
				Vector2(dash_end, divider_y),
				HIGHWAY_MARKING_COLOR,
				0.9
			)
			dash_x += 16.0

	_draw_world_line(
		Vector2(rect.position.x, rect.position.y + shoulder_width),
		Vector2(rect.end.x, rect.position.y + shoulder_width),
		HIGHWAY_EDGE_COLOR,
		1.15
	)
	_draw_world_line(
		Vector2(rect.position.x, rect.end.y - shoulder_width),
		Vector2(rect.end.x, rect.end.y - shoulder_width),
		HIGHWAY_EDGE_COLOR,
		1.15
	)

	var exit_edge_y := (
		rect.position.y
		+ MAP.HIGHWAY_EXIT_LANE * MAP.HIGHWAY_LANE_WIDTH
		+ 1.25
	)
	_draw_world_line(
		Vector2(rect.end.x - 55.0, exit_edge_y),
		Vector2(rect.end.x, exit_edge_y),
		HIGHWAY_EXIT_GUIDE_COLOR,
		1.2
	)

	_draw_world_rect_outline(
		rect,
		Color(0.03, 0.035, 0.045, 0.85),
		1.0
	)


func _highway_lap_offset(lap: int = highway_lap) -> Vector2:
	return Vector2(float(lap) * MAP.HIGHWAY_RECT.size.x, 0.0)


func _highway_rect_for_lap(lap: int) -> Rect2:
	return Rect2(
		MAP.HIGHWAY_RECT.position + _highway_lap_offset(lap),
		MAP.HIGHWAY_RECT.size
	)


func _highway_cell_center(column: int, lane: int) -> Vector2:
	return MAP.highway_cell_center(column, lane) + _highway_lap_offset()


func _connector_two_rect() -> Rect2:
	return Rect2(
		MAP.CONNECTOR_TWO_RECT.position + _highway_lap_offset(),
		MAP.CONNECTOR_TWO_RECT.size
	)


func _city_rect() -> Rect2:
	return Rect2(
		MAP.CITY_RECT.position + _highway_lap_offset(),
		MAP.CITY_RECT.size
	)


func _city_cell_center(cell: Vector2i) -> Vector2:
	return MAP.city_cell_center(cell) + _highway_lap_offset()


func _city_entry_point() -> Vector2:
	return MAP.city_entry_point() + _highway_lap_offset()


func _parking_stop_point() -> Vector2:
	# Nudge the final car position toward the curb instead of ending in the
	# middle of the lane. The logical destination cell itself does not change.
	return _city_cell_center(MAP.CITY_DESTINATION) + Vector2(5.5, 0.0)


func _parking_space_rect() -> Rect2:
	var center := _parking_stop_point()
	return Rect2(
		center + Vector2(-4.0, -12.0),
		Vector2(8.0, 24.0)
	)


func _venue_rect() -> Rect2:
	var destination_center := _city_cell_center(MAP.CITY_DESTINATION)
	return Rect2(
		Vector2(
			destination_center.x + CITY_SIDEWALK_WIDTH * 0.5 + 2.0,
			destination_center.y - 22.0
		),
		Vector2(18.0, 44.0)
	)


func _draw_destination() -> void:
	var parking_rect := _parking_space_rect()
	var venue_rect := _venue_rect()
	var destination_center := _city_cell_center(MAP.CITY_DESTINATION)
	var curb_x := destination_center.x + CITY_ROAD_WIDTH * 0.5

	# Two short curbside ticks imply a parallel-parking bay without drawing a
	# large target box under the car.
	_draw_world_line(
		Vector2(parking_rect.end.x, parking_rect.position.y),
		Vector2(parking_rect.end.x, parking_rect.position.y + 4.5),
		PARKING_LINE_COLOR,
		0.65
	)
	_draw_world_line(
		Vector2(parking_rect.end.x, parking_rect.end.y - 4.5),
		Vector2(parking_rect.end.x, parking_rect.end.y),
		PARKING_LINE_COLOR,
		0.65
	)

	# A narrow sidewalk strip bridges the curb directly to the venue frontage.
	var venue_sidewalk := Rect2(
		Vector2(curb_x, destination_center.y - 26.0),
		Vector2(maxf(1.0, venue_rect.position.x - curb_x + 1.5), 52.0)
	)
	_draw_world_rect(venue_sidewalk, VENUE_SIDEWALK_COLOR)

	# Compact commercial building. Keeping the footprint close to the curb
	# makes the venue visible while the car is actually parked.
	_draw_world_rect(
		Rect2(venue_rect.position + Vector2(1.3, 1.3), venue_rect.size),
		Color(0.0, 0.0, 0.0, 0.22)
	)
	_draw_world_rect(venue_rect, VENUE_BUILDING_COLOR)

	var roof := Rect2(
		venue_rect.position + Vector2(2.5, 2.5),
		venue_rect.size - Vector2(5.0, 5.0)
	)
	_draw_world_rect(roof, VENUE_ROOF_COLOR)

	# Street-facing front wall and recessed warm doorway.
	var facade := Rect2(
		Vector2(venue_rect.position.x, venue_rect.position.y + 2.5),
		Vector2(3.6, venue_rect.size.y - 5.0)
	)
	_draw_world_rect(facade, VENUE_TRIM_COLOR)

	var door_rect := Rect2(
		Vector2(venue_rect.position.x - 0.4, destination_center.y - 5.0),
		Vector2(5.0, 10.0)
	)
	_draw_world_rect(door_rect, VENUE_WINDOW_COLOR)

	# Small marquee over the door: enough to read as a venue entrance without
	# putting a giant label in the world.
	var marquee := PackedVector2Array([
		Vector2(venue_rect.position.x - 3.0, destination_center.y - 8.0),
		Vector2(venue_rect.position.x + 7.0, destination_center.y - 8.0),
		Vector2(venue_rect.position.x + 6.0, destination_center.y - 5.2),
		Vector2(venue_rect.position.x - 3.0, destination_center.y - 5.2),
	])
	_draw_world_polygon(marquee, VENUE_AWNING_COLOR)

	var sign_rect := Rect2(
		Vector2(venue_rect.position.x - 0.2, destination_center.y - 15.0),
		Vector2(5.4, 4.0)
	)
	_draw_world_rect(sign_rect, VENUE_SIGN_COLOR)

	var poster_rect := Rect2(
		Vector2(venue_rect.position.x - 0.1, destination_center.y + 9.0),
		Vector2(3.8, 6.0)
	)
	_draw_world_rect(poster_rect, Color(0.36, 0.44, 0.50, 0.80))

	# One rooftop unit gives the top-down footprint some believable structure.
	_draw_world_rect(
		Rect2(venue_rect.position + Vector2(10.0, 9.0), Vector2(5.0, 4.0)),
		Color(0.22, 0.23, 0.23)
	)


func _draw_map_outline() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(MAP.MAP_SIZE))
	_draw_world_rect_outline(rect, Color(0.50, 0.50, 0.47, 0.25), 1.0)


func _draw_world_polygon(world_points: PackedVector2Array, color: Color) -> void:
	var screen_points := PackedVector2Array()
	for point in world_points:
		screen_points.append(_world_to_screen(point))
	draw_colored_polygon(screen_points, color)


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


func _draw_world_line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	draw_line(
		_world_to_screen(a),
		_world_to_screen(b),
		color,
		width,
		true
	)


func _current_world_zoom() -> float:
	if road_kind == "connector_two":
		return lerpf(
			WORLD_ZOOM,
			CITY_WORLD_ZOOM,
			_connector_two_progress()
		)
	if road_kind == "city":
		return CITY_WORLD_ZOOM
	return WORLD_ZOOM


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
		"bumps": 0,
		"seed": world_seed,
	})


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_A, KEY_LEFT:
			_turn_left()
		KEY_D, KEY_RIGHT:
			_turn_right()
		KEY_W, KEY_UP, KEY_SPACE:
			_start_drive()
