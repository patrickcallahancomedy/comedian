extends Control

## DRIVE GRID v0.1
## A small playable proof of the Lego-grid driving idea.
## - one 800x800 logical board
## - modules snap to one master unit
## - one logical block per second
## - car scale comes directly from the current module cell size

signal trip_finished(result: Dictionary)

const MAP = preload("res://scripts/drive/drive_grid_map.gd")

const STEP_SECONDS := 1.0
const TURN_SECONDS := 0.22
const WORLD_ZOOM := 4.5
const CAR_REFERENCE_SCALE := 1.5

const NEIGHBORHOOD_COLOR := Color(0.34, 0.57, 0.31)
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

var step_elapsed := 0.0
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
	step_elapsed = STEP_SECONDS
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
	step_elapsed = STEP_SECONDS
	_begin_next_step()


func _process(delta: float) -> void:
	if drive_complete:
		return

	if not started:
		_update_car_visual()
		queue_redraw()
		return

	drive_time += delta
	step_elapsed += delta
	turn_elapsed += delta

	if turn_elapsed < TURN_SECONDS:
		var turn_t := clampf(turn_elapsed / TURN_SECONDS, 0.0, 1.0)
		map_rotation = lerp_angle(map_rotation_from, map_rotation_to, smoothstep(0.0, 1.0, turn_t))
	else:
		map_rotation = map_rotation_to

	var t := clampf(step_elapsed / STEP_SECONDS, 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, t)
	visual_world_position = move_from.lerp(move_to, eased)
	visual_cell_scale = lerpf(scale_from, scale_to, eased)

	if step_elapsed >= STEP_SECONDS:
		visual_world_position = move_to
		visual_cell_scale = scale_to
		_begin_next_step()

	_update_car_visual()
	queue_redraw()


func _begin_next_step() -> void:
	step_elapsed = 0.0
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
			scale_to = MAP.car_scale_for_cell(MAP.CITY_CELL)
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
		scale_to = MAP.car_scale_for_cell(MAP.CITY_CELL)
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
		queued_highway_lane = maxi(0, queued_highway_lane - 1)
		return

	if road_kind == "neighborhood" or road_kind == "city":
		_set_heading(Vector2i(heading.y, -heading.x))


func _turn_right() -> void:
	if not started or drive_complete:
		return

	if road_kind == "highway":
		queued_highway_lane = mini(MAP.HIGHWAY_LANES - 1, queued_highway_lane + 1)
		return

	if road_kind == "neighborhood" or road_kind == "city":
		_set_heading(Vector2i(-heading.y, heading.x))


func _set_heading(new_heading: Vector2i) -> void:
	heading = new_heading
	map_rotation_from = map_rotation
	map_rotation_to = -PI / 2.0 - Vector2(heading).angle()
	turn_elapsed = 0.0


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

	_draw_grid_zone(
		MAP.NEIGHBORHOOD_RECT,
		MAP.NEIGHBORHOOD_CELL,
		NEIGHBORHOOD_COLOR
	)
	_draw_neighborhood_border_with_gate()

	_draw_world_rect(MAP.CONNECTOR_ONE_RECT, CONNECTOR_COLOR)
	_draw_highway()
	_draw_world_rect(MAP.CONNECTOR_TWO_RECT, CONNECTOR_COLOR)

	_draw_grid_zone(
		MAP.CITY_RECT,
		MAP.CITY_CELL,
		CITY_COLOR
	)
	_draw_world_rect_outline(MAP.CITY_RECT, BORDER_COLOR, 3.0)

	_draw_destination()
	_draw_map_outline()


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


func _draw_highway() -> void:
	_draw_world_rect(MAP.HIGHWAY_RECT, HIGHWAY_COLOR)

	for lane in range(1, MAP.HIGHWAY_LANES):
		var y := MAP.HIGHWAY_RECT.position.y + lane * MAP.HIGHWAY_CELL
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
			MAP.HIGHWAY_RECT.position.y + MAP.HIGHWAY_EXIT_LANE * MAP.HIGHWAY_CELL
		),
		Vector2(MAP.HIGHWAY_CELL, MAP.HIGHWAY_CELL)
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
