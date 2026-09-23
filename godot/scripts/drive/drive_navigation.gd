extends Label

## In-world turn guidance for the driving microgame.
## The arrow is anchored to the actual intersection where the player should turn.
## If that turn is missed, the route is recalculated and the arrow moves to the
## next best intersection. Driving logic and map topology are untouched.

const MAP = preload("res://scripts/drive/drive_grid_map.gd")

const ARROW_COLOR := Color(0.96, 0.95, 0.90, 0.92)
const ARROW_OUTLINE := Color(0.04, 0.05, 0.04, 0.55)
const ARROW_LENGTH := 56.0
const ARROW_SHAFT_HALF := 5.5
const ARROW_HEAD_LENGTH := 18.0
const ARROW_HEAD_HALF_HEIGHT := 15.0
const ARROW_VERTICAL_OFFSET := -36.0

@onready var drive = $"../CityMap"
@onready var status_label: Label = $"../StatusLabel"


func _ready() -> void:
	# Reuse the existing Navigation node as a full-screen, non-interactive
	# drawing layer. No new embedded assets are needed.
	text = ""
	z_index = 2
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	queue_redraw()


func _process(_delta: float) -> void:
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

	# Keep the marker inside the road intersection but above the centered car.
	_draw_arrow(
		drive._world_to_screen(world_position) + Vector2(0.0, ARROW_VERTICAL_OFFSET),
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


func _draw_arrow(center: Vector2, turn: String) -> void:
	var horizontal := 1.0 if turn == "right" else -1.0

	# Use a filled road-marker shape instead of a thin HUD-style icon.
	# The dark outer shape is only a narrow readability edge.
	var outer := _arrow_polygon(
		center,
		horizontal,
		ARROW_LENGTH + 4.0,
		ARROW_SHAFT_HALF + 1.5,
		ARROW_HEAD_LENGTH + 2.0,
		ARROW_HEAD_HALF_HEIGHT + 2.0
	)
	var inner := _arrow_polygon(
		center,
		horizontal,
		ARROW_LENGTH,
		ARROW_SHAFT_HALF,
		ARROW_HEAD_LENGTH,
		ARROW_HEAD_HALF_HEIGHT
	)

	draw_colored_polygon(outer, ARROW_OUTLINE)
	draw_colored_polygon(inner, ARROW_COLOR)


func _arrow_polygon(
	center: Vector2,
	horizontal: float,
	length: float,
	shaft_half: float,
	head_length: float,
	head_half_height: float
) -> PackedVector2Array:
	var tail_x := -length * 0.5
	var tip_x := length * 0.5
	var head_base_x := tip_x - head_length

	return PackedVector2Array([
		center + Vector2(tail_x * horizontal, -shaft_half),
		center + Vector2(head_base_x * horizontal, -shaft_half),
		center + Vector2(head_base_x * horizontal, -head_half_height),
		center + Vector2(tip_x * horizontal, 0.0),
		center + Vector2(head_base_x * horizontal, head_half_height),
		center + Vector2(head_base_x * horizontal, shaft_half),
		center + Vector2(tail_x * horizontal, shaft_half),
	])
