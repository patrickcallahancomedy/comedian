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
const TURN_SECONDS := 0.20
const DISPLAY_SCALE := 1.0
const WORLD_SCALE := 2.0
const WORLD_ZOOM := 4.5 * DISPLAY_SCALE * WORLD_SCALE
const CAR_REFERENCE_SCALE := 0.65 * DISPLAY_SCALE
const CITY_CAR_SCALE := 6.0
const CITY_SPEED_MULTIPLIER := 0.8

const NEIGHBORHOOD_COLOR := Color(0.30, 0.50, 0.24)
const NEIGHBORHOOD_SIDEWALK_COLOR := Color(0.72, 0.69, 0.62)
const NEIGHBORHOOD_ROAD_COLOR := Color(0.18, 0.20, 0.23)
const NEIGHBORHOOD_HOUSE_COLOR := Color(0.64, 0.39, 0.25)
const NEIGHBORHOOD_ROOF_COLOR := Color(0.36, 0.24, 0.20)
const NEIGHBORHOOD_ROAD_WIDTH := 12.0
const NEIGHBORHOOD_SIDEWALK_WIDTH := 18.0
const CONNECTOR_COLOR := Color(0.93, 0.56, 0.20)
const HIGHWAY_COLOR := Color(0.72, 0.42, 0.58)
const CITY_COLOR := Color(0.42, 0.44, 0.48)
const GRID_COLOR := Color(0.08, 0.09, 0.09, 0.45)
const BORDER_COLOR := Color(0.93, 0.92, 0.86)

@export var world_seed: int = 0

var started := false
var drive_complete := false
var drive_time := 0.0
var missed_turns := 0

var road_kind := "neighborhood"

var neighborhood_cell := MAP.NEIGHBORHOOD_START
var city_cell := MAP.CITY_ENTRY
var heading := Vector2i.UP

var highway_column := 0
var highway_lane := MAP.HIGHWAY_ENTRY_LANE
var queued_highway_lane := MAP.HIGHWAY_ENTRY_LANE

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

	player_car.pivot_offset = player_car.size * 0.5
	_reset_to_start()
	call_deferred("_refresh_layout")


func _refresh_layout() -> void:
	player_screen_center = Vector2(size.x * 0.5, minf(size.y * 0.46, 360.0))
	car_base_position = player_screen_center - player_car.size * 0.5
	_update_car_visual()
	queue_redraw()


func _reset_to_start() -> void:
	started = false
	drive_complete = false
	drive_time = 0.0
	missed_turns = 0
	road_kind = "neighborhood"
	neighborhood_cell = MAP.NEIGHBORHOOD_START
	city_cell = MAP.CITY_ENTRY
	heading = Vector2i.UP
	highway_column = 0
	highway_lane = MAP.HIGHWAY_ENTRY_LANE
	queued_highway_lane = highway_lane
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

	if turn_elapsed < TURN_SECONDS:
		var turn_t := clampf(turn_elapsed / TURN_SECONDS, 0.0, 1.0)
		map_rotation = lerp_angle(map_rotation_from, map_rotation_to, smoothstep(0.0, 1.0, turn_t))
	else:
		map_rotation = map_rotation_to

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
			return float(MAP.NEIGHBORHOOD_CELL) / STEP_SECONDS
		"highway":
			return float(MAP.HIGHWAY_CELL) * 4.0 / STEP_SECONDS
		"city":
			return float(MAP.NEIGHBORHOOD_CELL) * CITY_SPEED_MULTIPLIER / STEP_SECONDS
		"connector_one":
			var neighborhood_speed := float(MAP.NEIGHBORHOOD_CELL) / STEP_SECONDS
			var highway_speed := float(MAP.HIGHWAY_CELL) * 4.0 / STEP_SECONDS
			return lerpf(
				neighborhood_speed,
				highway_speed,
				_connector_one_progress()
			)
		"connector_two":
			var highway_speed := float(MAP.HIGHWAY_CELL) * 4.0 / STEP_SECONDS
			var city_speed := float(MAP.NEIGHBORHOOD_CELL) * CITY_SPEED_MULTIPLIER / STEP_SECONDS
			return lerpf(
				highway_speed,
				city_speed,
				_connector_two_progress()
			)
	return float(MAP.NEIGHBORHOOD_CELL) / STEP_SECONDS


func _connector_one_progress() -> float:
	var ramp_start := MAP.CONNECTOR_ONE_RECT.position.x
	var ramp_end := MAP.CONNECTOR_ONE_RECT.end.x
	return clampf(
		inverse_lerp(ramp_start, ramp_end, visual_world_position.x),
		0.0,
		1.0
	)


func _connector_two_progress() -> float:
	var ramp_start := MAP.CONNECTOR_TWO_RECT.position.x
	var ramp_end := MAP.CONNECTOR_TWO_RECT.end.x
	return clampf(
		inverse_lerp(ramp_start, ramp_end, visual_world_position.x),
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

	if _cell_inside(desired, MAP.NEIGHBORHOOD_SIZE):
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

	if highway_column >= MAP.HIGHWAY_COLUMNS - 1:
		if highway_lane == MAP.HIGHWAY_EXIT_LANE:
			road_kind = "connector_two"
			move_to = MAP.city_entry_point()
			# The off-ramp widens to a full city-block width, so the car can
			# grow smoothly all the way to its city scale before crossing in.
			scale_to = CITY_CAR_SCALE
			motion_direction = (move_to - move_from).normalized()
			status_label.text = "CONNECTOR"
			return

		missed_turns += 1
		highway_column = 0
		highway_lane = queued_highway_lane
		move_from = MAP.highway_cell_center(highway_column, highway_lane)
		visual_world_position = move_from
		move_to = MAP.highway_cell_center(1, highway_lane)
		highway_column = 1
		scale_from = MAP.car_scale_for_cell(MAP.HIGHWAY_CELL)
		scale_to = scale_from
		visual_cell_scale = scale_from
		motion_direction = Vector2.RIGHT
		status_label.text = "MISSED EXIT - LOOP"
		return

	highway_column += 1
	highway_lane = queued_highway_lane
	move_to = MAP.highway_cell_center(highway_column, highway_lane)
	scale_to = MAP.car_scale_for_cell(MAP.HIGHWAY_CELL)
	motion_direction = (move_to - move_from).normalized()
	status_label.text = "HIGHWAY  •  EXIT LANE 4"


func _begin_city_step() -> void:
	if road_kind == "connector_two":
		road_kind = "city"
		city_cell = MAP.CITY_ENTRY
		heading = Vector2i.RIGHT

	if city_cell == MAP.CITY_DESTINATION:
		_finish_drive()
		return

	var desired := city_cell + heading
	if _cell_inside(desired, MAP.CITY_SIZE):
		city_cell = desired
		move_to = MAP.city_cell_center(city_cell)
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
		_set_highway_lane(queued_highway_lane - 1)
		return

	if road_kind == "neighborhood" or road_kind == "city":
		_set_heading(Vector2i(heading.y, -heading.x))


func _turn_right() -> void:
	if not started or drive_complete:
		return

	if road_kind == "highway":
		_set_highway_lane(queued_highway_lane + 1)
		return

	if road_kind == "neighborhood" or road_kind == "city":
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
	move_to = MAP.highway_cell_center(highway_column, new_lane)
	motion_direction = (move_to - visual_world_position).normalized()


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
	player_car.position = car_base_position
	player_car.scale = Vector2.ONE * CAR_REFERENCE_SCALE * visual_cell_scale
	# The car stays visually upright; steering rotates the world around it.
	player_car.rotation = 0.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.085, 0.08), true)

	_draw_neighborhood()
	_draw_neighborhood_border_with_gate()

	_draw_world_rect(MAP.CONNECTOR_ONE_RECT, CONNECTOR_COLOR)
	_draw_highway()
	_draw_city_connector()

	_draw_grid_zone(
		MAP.CITY_RECT,
		MAP.CITY_CELL,
		CITY_COLOR
	)
	_draw_world_rect_outline(MAP.CITY_RECT, BORDER_COLOR, 3.0)

	_draw_destination()
	_draw_map_outline()


func _draw_neighborhood() -> void:
	# Simple built-in neighborhood art. No TileMap, atlas, or generated assets:
	# just grass, sidewalks, streets, and small house blocks drawn in world space.
	var rect := MAP.NEIGHBORHOOD_RECT

	_draw_world_rect(rect, NEIGHBORHOOD_COLOR)

	# Sidewalk strips go down first so the roads stay clean at intersections.
	for x_index in range(MAP.NEIGHBORHOOD_SIZE.x):
		var center_x := rect.position.x + (float(x_index) + 0.5) * MAP.NEIGHBORHOOD_CELL
		_draw_world_rect(
			Rect2(
				Vector2(center_x - NEIGHBORHOOD_SIDEWALK_WIDTH * 0.5, rect.position.y),
				Vector2(NEIGHBORHOOD_SIDEWALK_WIDTH, rect.size.y)
			),
			NEIGHBORHOOD_SIDEWALK_COLOR
		)

	for y_index in range(MAP.NEIGHBORHOOD_SIZE.y):
		var center_y := rect.position.y + (float(y_index) + 0.5) * MAP.NEIGHBORHOOD_CELL
		_draw_world_rect(
			Rect2(
				Vector2(rect.position.x, center_y - NEIGHBORHOOD_SIDEWALK_WIDTH * 0.5),
				Vector2(rect.size.x, NEIGHBORHOOD_SIDEWALK_WIDTH)
			),
			NEIGHBORHOOD_SIDEWALK_COLOR
		)

	for x_index in range(MAP.NEIGHBORHOOD_SIZE.x):
		var center_x := rect.position.x + (float(x_index) + 0.5) * MAP.NEIGHBORHOOD_CELL
		_draw_world_rect(
			Rect2(
				Vector2(center_x - NEIGHBORHOOD_ROAD_WIDTH * 0.5, rect.position.y),
				Vector2(NEIGHBORHOOD_ROAD_WIDTH, rect.size.y)
			),
			NEIGHBORHOOD_ROAD_COLOR
		)

	for y_index in range(MAP.NEIGHBORHOOD_SIZE.y):
		var center_y := rect.position.y + (float(y_index) + 0.5) * MAP.NEIGHBORHOOD_CELL
		_draw_world_rect(
			Rect2(
				Vector2(rect.position.x, center_y - NEIGHBORHOOD_ROAD_WIDTH * 0.5),
				Vector2(rect.size.x, NEIGHBORHOOD_ROAD_WIDTH)
			),
			NEIGHBORHOOD_ROAD_COLOR
		)

	# Nine tiny houses make the area read as a neighborhood without introducing
	# another asset pipeline. They live in the grassy blocks between streets.
	for lot_y in range(3):
		for lot_x in range(3):
			var lot_center := rect.position + Vector2(
				float(lot_x + 1) * MAP.NEIGHBORHOOD_CELL,
				float(lot_y + 1) * MAP.NEIGHBORHOOD_CELL
			)
			var house_size := Vector2(13.0, 10.0)
			var house_rect := Rect2(lot_center - house_size * 0.5, house_size)
			_draw_world_rect(house_rect, NEIGHBORHOOD_HOUSE_COLOR)

			var roof_inset := Vector2(2.0, 2.0)
			var roof_rect := Rect2(
				house_rect.position + roof_inset,
				house_rect.size - roof_inset * 2.0
			)
			_draw_world_rect(roof_rect, NEIGHBORHOOD_ROOF_COLOR)


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


func _draw_city_connector() -> void:
	# The city off-ramp starts at the existing highway-sized width and
	# widens linearly until its end matches one full city block.
	var rect := MAP.CONNECTOR_TWO_RECT
	var center_y := rect.get_center().y
	var start_half_width := rect.size.y * 0.5
	var end_half_width := float(MAP.CITY_CELL) * 0.5

	var points := PackedVector2Array([
		_world_to_screen(Vector2(rect.position.x, center_y - start_half_width)),
		_world_to_screen(Vector2(rect.end.x, center_y - end_half_width)),
		_world_to_screen(Vector2(rect.end.x, center_y + end_half_width)),
		_world_to_screen(Vector2(rect.position.x, center_y + start_half_width)),
	])
	draw_colored_polygon(points, CONNECTOR_COLOR)


func _draw_highway() -> void:
	_draw_world_rect(MAP.HIGHWAY_RECT, HIGHWAY_COLOR)

	for lane in range(1, MAP.HIGHWAY_LANES):
		var y := MAP.HIGHWAY_RECT.position.y + lane * MAP.HIGHWAY_LANE_WIDTH
		_draw_world_line(
			Vector2(MAP.HIGHWAY_RECT.position.x, y),
			Vector2(MAP.HIGHWAY_RECT.end.x, y),
			BORDER_COLOR,
			1.5
		)

	for column in range(1, MAP.HIGHWAY_COLUMNS):
		var x := MAP.HIGHWAY_RECT.position.x + column * MAP.HIGHWAY_CELL
		_draw_world_line(
			Vector2(x, MAP.HIGHWAY_RECT.position.y),
			Vector2(x, MAP.HIGHWAY_RECT.end.y),
			GRID_COLOR,
			1.0
		)

	_draw_world_rect_outline(MAP.HIGHWAY_RECT, BORDER_COLOR, 3.0)

	var exit_rect := Rect2(
		Vector2(
			MAP.HIGHWAY_RECT.end.x - MAP.HIGHWAY_CELL,
			MAP.HIGHWAY_RECT.position.y + MAP.HIGHWAY_EXIT_LANE * MAP.HIGHWAY_LANE_WIDTH
		),
		Vector2(MAP.HIGHWAY_CELL, MAP.HIGHWAY_LANE_WIDTH)
	)
	_draw_world_rect_outline(exit_rect, Color(1.0, 0.92, 0.34), 3.0)


func _draw_destination() -> void:
	var center := MAP.city_cell_center(MAP.CITY_DESTINATION)
	var half := Vector2.ONE * MAP.CITY_CELL * 0.34
	var rect := Rect2(center - half, half * 2.0)
	_draw_world_rect_outline(rect, Color(1.0, 0.92, 0.34), 4.0)


func _draw_map_outline() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(MAP.MAP_SIZE))
	_draw_world_rect_outline(rect, Color(0.50, 0.50, 0.47, 0.25), 1.0)


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


func _world_to_screen(world_point: Vector2) -> Vector2:
	var offset := (world_point - visual_world_position) * WORLD_ZOOM
	offset = offset.rotated(map_rotation)
	return player_screen_center + offset


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
