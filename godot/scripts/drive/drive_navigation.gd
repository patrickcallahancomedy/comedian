extends Label

## In-world turn guidance for the driving microgame.
## The arrow is anchored to the actual intersection where the player should turn.
## If that turn is missed, the route is recalculated and the arrow moves to the
## next best intersection. Driving logic and map topology are untouched.

const MAP = preload("res://scripts/drive/drive_grid_map.gd")

const MARKER_BG := Color(0.055, 0.062, 0.072, 0.90)
const MARKER_INNER := Color(0.11, 0.12, 0.135, 0.92)
const MARKER_BORDER := Color(1.0, 1.0, 1.0, 0.14)
const MARKER_ACCENT := Color(1.0, 0.82, 0.28, 0.96)
const MARKER_ICON := Color(0.99, 0.99, 0.985, 1.0)
const MARKER_SHADOW := Color(0.0, 0.0, 0.0, 0.26)
const MARKER_HALO := Color(1.0, 0.82, 0.28, 0.12)

const MARKER_RADIUS := 21.0
const MARKER_NEAR_CAR_DISTANCE := 76.0
const MARKER_LIFT := 50.0
const CHEVRON_WIDTH := 3.8
const CHEVRON_HALF_WIDTH := 6.8
const CHEVRON_HALF_HEIGHT := 9.5

const MARKER_FADE_OUT_SECONDS := 0.11
const MARKER_FADE_IN_SECONDS := 0.18
const MARKER_ATTENTION_SECONDS := 0.70

@onready var drive = $"../CityMap"
@onready var status_label: Label = $"../StatusLabel"

var ui_time := 0.0
var displayed_hint: Dictionary = {}
var pending_hint: Dictionary = {}
var marker_phase := "idle"
var marker_phase_time := 0.0
var marker_attention_time := MARKER_ATTENTION_SECONDS
var marker_alpha := 0.0
var marker_scale := 0.86


func _ready() -> void:
	# Reuse the existing Navigation node as a full-screen, non-interactive
	# drawing layer. No new embedded assets are needed.
	text = ""
	z_index = 4
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	ui_time += delta
	_update_status_visibility()
	_update_marker_state(delta)
	queue_redraw()


func get_turn_hint() -> Dictionary:
	if drive == null or not drive.started or drive.drive_complete:
		return {}
	return _current_turn_hint()


func _update_status_visibility() -> void:
	if drive == null or status_label == null:
		return

	# Keep the start/arrival state and highway lane guidance. Neighborhood and
	# city turn instructions are replaced completely by the in-world arrow.
	if not drive.started or drive.drive_complete:
		status_label.show()
		return

	if drive.road_kind == "highway" or drive.road_kind.begins_with("connector"):
		status_label.show()
	else:
		status_label.hide()


func _draw() -> void:
	if drive == null or displayed_hint.is_empty() or marker_alpha <= 0.001:
		return

	var cell: Vector2i = displayed_hint["cell"]
	var turn: String = displayed_hint["turn"]
	var world_position := Vector2.ZERO

	match drive.road_kind:
		"neighborhood":
			world_position = MAP.neighborhood_cell_center(cell)
		"city":
			world_position = MAP.city_cell_center(cell)
		_:
			return

	_draw_turn_marker(
		drive._world_to_screen(world_position),
		turn,
		marker_alpha,
		marker_scale
	)


func _update_marker_state(delta: float) -> void:
	var target: Dictionary = get_turn_hint()
	var target_key := _hint_key(target)
	var displayed_key := _hint_key(displayed_hint)
	var pending_key := _hint_key(pending_hint)

	if target_key != displayed_key and target_key != pending_key:
		pending_hint = target
		if displayed_hint.is_empty():
			_start_pending_hint()
		else:
			marker_phase = "fade_out"
			marker_phase_time = 0.0

	marker_phase_time += delta

	match marker_phase:
		"fade_out":
			var fade_t := clampf(
				marker_phase_time / MARKER_FADE_OUT_SECONDS,
				0.0,
				1.0
			)
			marker_alpha = 1.0 - smoothstep(0.0, 1.0, fade_t)
			marker_scale = lerpf(1.0, 0.95, fade_t)
			if fade_t >= 1.0:
				displayed_hint = {}
				_start_pending_hint()
		"fade_in":
			var appear_t := clampf(
				marker_phase_time / MARKER_FADE_IN_SECONDS,
				0.0,
				1.0
			)
			var eased := 1.0 - pow(1.0 - appear_t, 3.0)
			marker_alpha = eased
			marker_scale = lerpf(0.86, 1.0, eased)
			if appear_t >= 1.0:
				marker_phase = "visible"
				marker_phase_time = 0.0
		"visible":
			marker_alpha = 1.0
			marker_scale = 1.0
			marker_attention_time += delta
		_:
			marker_alpha = 0.0
			marker_scale = 0.86


func _start_pending_hint() -> void:
	if pending_hint.is_empty():
		displayed_hint = {}
		marker_phase = "idle"
		marker_phase_time = 0.0
		marker_alpha = 0.0
		marker_scale = 0.86
		return

	displayed_hint = pending_hint
	pending_hint = {}
	marker_phase = "fade_in"
	marker_phase_time = 0.0
	marker_attention_time = 0.0
	marker_alpha = 0.0
	marker_scale = 0.86


func _hint_key(hint: Dictionary) -> String:
	if hint.is_empty():
		return ""
	var cell: Vector2i = hint.get("cell", Vector2i(-99, -99))
	var turn: String = hint.get("turn", "")
	return "%d:%d:%s" % [cell.x, cell.y, turn]


func _current_turn_hint() -> Dictionary:
	match drive.road_kind:
		"neighborhood":
			var states := _find_route_states(
				drive.neighborhood_cell,
				drive.heading,
				MAP.NEIGHBORHOOD_GATE,
				MAP.NEIGHBORHOOD_SIZE,
				true
			)
			return _first_turn_on_route(
				states,
				MAP.NEIGHBORHOOD_GATE_SIDE
			)
		"city":
			var states := _find_route_states(
				drive.city_cell,
				drive.heading,
				MAP.CITY_DESTINATION,
				MAP.CITY_SIZE,
				false
			)
			return _first_turn_on_route(states, Vector2i.ZERO)

	return {}


func _find_route_states(
	start_cell: Vector2i,
	start_heading: Vector2i,
	goal_cell: Vector2i,
	grid_size: Vector2i,
	use_neighborhood_graph: bool
) -> Array[Vector3i]:
	var start_state := Vector3i(
		start_cell.x,
		start_cell.y,
		_direction_index(start_heading)
	)
	var queue: Array[Vector3i] = [start_state]
	var queue_index := 0
	var parent := {start_state: start_state}
	var goal_state := Vector3i.ZERO
	var found := false

	while queue_index < queue.size():
		var state := queue[queue_index]
		queue_index += 1

		var cell := Vector2i(state.x, state.y)
		var state_heading := _direction_from_index(state.z)

		if cell == goal_cell:
			goal_state = state
			found = true
			break

		for next_heading in _ordered_directions(state_heading):
			var next_cell := cell + next_heading
			if not _cell_inside(next_cell, grid_size):
				continue
			if (
				use_neighborhood_graph
				and not MAP.neighborhood_cells_connect(cell, next_cell)
			):
				continue

			var next_state := Vector3i(
				next_cell.x,
				next_cell.y,
				_direction_index(next_heading)
			)
			if parent.has(next_state):
				continue

			parent[next_state] = state
			queue.append(next_state)

	if not found:
		return []

	var route: Array[Vector3i] = []
	var cursor := goal_state

	while true:
		route.push_front(cursor)
		if cursor == start_state:
			break
		cursor = parent[cursor]

	return route


func _first_turn_on_route(
	route: Array[Vector3i],
	final_direction: Vector2i
) -> Dictionary:
	if route.is_empty():
		return {}

	for index in range(route.size() - 1):
		var state := route[index]
		var next_state := route[index + 1]
		var cell := Vector2i(state.x, state.y)
		var heading := _direction_from_index(state.z)
		var next_cell := Vector2i(next_state.x, next_state.y)
		var next_heading := next_cell - cell

		var turn := _relative_turn(heading, next_heading)
		if not turn.is_empty():
			return {
				"cell": cell,
				"turn": turn,
			}

	# The neighborhood gate has one final outward movement that is not a grid
	# cell. Mark the gate itself when that exit requires a turn.
	if final_direction != Vector2i.ZERO:
		var final_state: Vector3i = route.back()
		var final_cell := Vector2i(final_state.x, final_state.y)
		var final_heading := _direction_from_index(final_state.z)
		var final_turn := _relative_turn(final_heading, final_direction)

		if not final_turn.is_empty():
			return {
				"cell": final_cell,
				"turn": final_turn,
			}

	return {}


func _ordered_directions(current_heading: Vector2i) -> Array[Vector2i]:
	# Never route by asking for a U-turn. Prefer staying straight, then choose
	# the shortest reachable left/right route from the current state.
	return [
		current_heading,
		Vector2i(current_heading.y, -current_heading.x),
		Vector2i(-current_heading.y, current_heading.x),
	]


func _relative_turn(
	current_heading: Vector2i,
	desired_heading: Vector2i
) -> String:
	if desired_heading == Vector2i(current_heading.y, -current_heading.x):
		return "left"
	if desired_heading == Vector2i(-current_heading.y, current_heading.x):
		return "right"
	return ""


func _direction_index(direction: Vector2i) -> int:
	if direction == Vector2i.UP:
		return 0
	if direction == Vector2i.RIGHT:
		return 1
	if direction == Vector2i.DOWN:
		return 2
	return 3


func _direction_from_index(index: int) -> Vector2i:
	match index:
		0:
			return Vector2i.UP
		1:
			return Vector2i.RIGHT
		2:
			return Vector2i.DOWN
		_:
			return Vector2i.LEFT


func _cell_inside(cell: Vector2i, grid_size: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < grid_size.x
		and cell.y < grid_size.y
	)


func _draw_turn_marker(
	intersection: Vector2,
	turn: String,
	alpha: float,
	scale_value: float
) -> void:
	var center := intersection
	var distance_to_car := intersection.distance_to(drive.player_screen_center)

	# Keep the badge directly on the intersection until the car is almost on it,
	# then lift it just enough to avoid covering the vehicle.
	if distance_to_car < MARKER_NEAR_CAR_DISTANCE:
		center += Vector2(0.0, -MARKER_LIFT)

	var attention_left := clampf(
		1.0 - marker_attention_time / MARKER_ATTENTION_SECONDS,
		0.0,
		1.0
	)
	var attention_pulse := sin(marker_attention_time * PI * 5.0) * 0.018 * attention_left
	var final_scale := scale_value * (1.0 + attention_pulse)
	var radius := MARKER_RADIUS * final_scale

	# Compact glass badge: subtle depth, very thin edge, and a restrained accent.
	draw_circle(
		center + Vector2(0.0, 3.0),
		radius + 2.0,
		_color_alpha(MARKER_SHADOW, alpha)
	)
	if attention_left > 0.0:
		draw_circle(
			center,
			radius + 4.0 * attention_left,
			_color_alpha(MARKER_HALO, alpha * attention_left)
		)
	draw_circle(center, radius + 1.0, _color_alpha(MARKER_BORDER, alpha))
	draw_circle(center, radius, _color_alpha(MARKER_BG, alpha))
	draw_circle(
		center + Vector2(0.0, -1.0 * final_scale),
		radius - 4.0 * final_scale,
		_color_alpha(MARKER_INNER, alpha)
	)

	# Thin partial ring instead of a heavy progress-style circle.
	draw_arc(
		center,
		radius - 0.8,
		-PI * 0.72,
		PI * 0.22,
		22,
		_color_alpha(MARKER_ACCENT, alpha),
		1.35,
		true
	)

	_draw_chevron(center, turn, alpha, final_scale)


func _color_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * alpha)


func _draw_chevron(
	center: Vector2,
	turn: String,
	alpha: float,
	scale_value: float
) -> void:
	var direction := 1.0 if turn == "right" else -1.0
	var half_width := CHEVRON_HALF_WIDTH * scale_value
	var half_height := CHEVRON_HALF_HEIGHT * scale_value
	var width := CHEVRON_WIDTH * scale_value
	var tip := center + Vector2(half_width * direction, 0.0)
	var upper := center + Vector2(-half_width * direction, -half_height)
	var lower := center + Vector2(-half_width * direction, half_height)

	# Narrow, sharp chevron with a restrained under-stroke.
	draw_line(
		upper,
		tip,
		Color(0.0, 0.0, 0.0, 0.28 * alpha),
		width + 1.8,
		true
	)
	draw_line(
		tip,
		lower,
		Color(0.0, 0.0, 0.0, 0.28 * alpha),
		width + 1.8,
		true
	)
	draw_line(upper, tip, _color_alpha(MARKER_ICON, alpha), width, true)
	draw_line(tip, lower, _color_alpha(MARKER_ICON, alpha), width, true)
