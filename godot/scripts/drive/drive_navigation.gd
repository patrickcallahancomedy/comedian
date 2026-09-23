extends Label

## In-world turn guidance for the driving microgame.
## The arrow is anchored to the actual intersection where the player should turn.
## If that turn is missed, the route is recalculated and the arrow moves to the
## next best intersection. Driving logic and map topology are untouched.

const MAP = preload("res://scripts/drive/drive_grid_map.gd")

const MARKER_BG := Color(0.045, 0.052, 0.062, 0.92)
const MARKER_INNER := Color(0.105, 0.115, 0.132, 0.94)
const MARKER_BORDER := Color(1.0, 1.0, 1.0, 0.18)
const MARKER_ACCENT := Color(1.0, 0.80, 0.22, 0.98)
const MARKER_ICON := Color(0.99, 0.99, 0.98, 1.0)
const MARKER_SHADOW := Color(0.0, 0.0, 0.0, 0.30)
const MARKER_HALO := Color(1.0, 0.80, 0.22, 0.16)

const MARKER_RADIUS := 26.0
const MARKER_NEAR_CAR_DISTANCE := 86.0
const MARKER_LIFT := 62.0
const CHEVRON_WIDTH := 5.0
const CHEVRON_HALF_WIDTH := 8.5
const CHEVRON_HALF_HEIGHT := 12.0

@onready var drive = $"../CityMap"
@onready var status_label: Label = $"../StatusLabel"

var ui_time := 0.0


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
	if drive == null or not drive.started or drive.drive_complete:
		return

	var hint: Dictionary = get_turn_hint()
	if hint.is_empty():
		return

	var cell: Vector2i = hint["cell"]
	var turn: String = hint["turn"]
	var world_position := Vector2.ZERO

	match drive.road_kind:
		"neighborhood":
			world_position = MAP.neighborhood_cell_center(cell)
		"city":
			world_position = MAP.city_cell_center(cell)
		_:
			return

	# Modern mobile-game waypoint: a compact floating badge, visually tied
	# to the exact intersection by a small pointer.
	_draw_turn_marker(
		drive._world_to_screen(world_position),
		turn
	)


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


func _draw_turn_marker(intersection: Vector2, turn: String) -> void:
	var pulse := 1.0 + sin(ui_time * 3.0) * 0.025
	var center := intersection
	var distance_to_car := intersection.distance_to(drive.player_screen_center)
	var lifted := distance_to_car < MARKER_NEAR_CAR_DISTANCE

	# Upcoming turns live directly on the intersection. Once the car reaches
	# that intersection, the badge lifts just enough to stay readable.
	if lifted:
		center += Vector2(0.0, -MARKER_LIFT)

	var radius := MARKER_RADIUS * pulse

	# Soft halo + glassy dark disc. This reads as a game waypoint rather than
	# a map pin or a road decal.
	draw_circle(center + Vector2(0.0, 4.0), radius + 3.0, MARKER_SHADOW)
	draw_circle(center, radius + 6.0 + sin(ui_time * 2.6) * 1.5, MARKER_HALO)
	draw_circle(center, radius + 1.5, MARKER_BORDER)
	draw_circle(center, radius, MARKER_BG)
	draw_circle(center, radius - 4.0, MARKER_INNER)

	# A restrained accent arc adds polish without turning into a progress ring.
	draw_arc(
		center,
		radius - 1.0,
		-PI * 0.78,
		PI * 0.78,
		32,
		MARKER_ACCENT,
		2.4,
		true
	)

	if lifted:
		# Minimal stem + glowing anchor dot keeps the floating badge tied to the
		# exact intersection while avoiding the old map-pin triangle.
		var stem_start := center + Vector2(0.0, radius + 3.0)
		var stem_end := intersection + Vector2(0.0, -8.0)
		draw_line(stem_start, stem_end, Color(1.0, 1.0, 1.0, 0.24), 1.5, true)
		draw_circle(intersection, 6.0, Color(1.0, 0.80, 0.22, 0.12))
		draw_circle(intersection, 3.0, MARKER_ACCENT)

	_draw_chevron(center, turn)


func _draw_chevron(center: Vector2, turn: String) -> void:
	var direction := 1.0 if turn == "right" else -1.0
	var tip := center + Vector2(CHEVRON_HALF_WIDTH * direction, 0.0)
	var upper := center + Vector2(-CHEVRON_HALF_WIDTH * direction, -CHEVRON_HALF_HEIGHT)
	var lower := center + Vector2(-CHEVRON_HALF_WIDTH * direction, CHEVRON_HALF_HEIGHT)

	# Layer a dark under-stroke beneath the bright chevron for crisp readability.
	draw_line(upper, tip, Color(0.0, 0.0, 0.0, 0.34), CHEVRON_WIDTH + 3.0, true)
	draw_line(tip, lower, Color(0.0, 0.0, 0.0, 0.34), CHEVRON_WIDTH + 3.0, true)
	draw_line(upper, tip, MARKER_ICON, CHEVRON_WIDTH, true)
	draw_line(tip, lower, MARKER_ICON, CHEVRON_WIDTH, true)

	# Fake round line caps so the icon feels like polished UI, not debug drawing.
	draw_circle(upper, CHEVRON_WIDTH * 0.5, MARKER_ICON)
	draw_circle(tip, CHEVRON_WIDTH * 0.5, MARKER_ICON)
	draw_circle(lower, CHEVRON_WIDTH * 0.5, MARKER_ICON)
