extends Label

## Subtle in-world route guidance for the driving microgame.
## Draws only a restrained road-center route line. There are no turn arrows,
## badges, chevrons, pulses, or marker animations.

const MAP = preload("res://scripts/drive/drive_grid_map.gd")

const ROUTE_LINE_COLOR := Color(0.95, 0.73, 0.28, 0.12)
const ROUTE_LINE_UNDERLAY := Color(0.02, 0.025, 0.03, 0.06)
const ROUTE_WIDTH_RATIO := 0.82
const ROUTE_START_AHEAD_RATIO := 0.28

@onready var drive = $"../CityMap"
@onready var status_label: Label = $"../StatusLabel"


func _ready() -> void:
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

	if not drive.started or drive.drive_complete:
		status_label.show()
		return

	if drive.road_kind == "highway":
		status_label.hide()
	elif drive.road_kind.begins_with("connector"):
		status_label.show()
	else:
		status_label.hide()


func _draw() -> void:
	if drive == null or not drive.started or drive.drive_complete:
		return
	if drive.road_kind != "neighborhood" and drive.road_kind != "city":
		return

	var route := _current_route_states()
	if route.size() < 2:
		return

	var points := PackedVector2Array()
	var next_state: Vector3i = route[1]
	var next_cell := Vector2i(next_state.x, next_state.y)
	var next_world: Vector2 = (
		MAP.neighborhood_cell_center(next_cell)
		if drive.road_kind == "neighborhood"
		else drive._city_cell_center(next_cell)
	)
	var next_screen: Vector2 = drive._world_to_screen(next_world)

	# Leave a clean gap around the car, then begin the guidance overlay ahead.
	points.append(
		drive.player_screen_center.lerp(
			next_screen,
			ROUTE_START_AHEAD_RATIO
		)
	)

	for index in range(1, route.size()):
		var state: Vector3i = route[index]
		var cell := Vector2i(state.x, state.y)
		var world_position: Vector2 = (
			MAP.neighborhood_cell_center(cell)
			if drive.road_kind == "neighborhood"
			else drive._city_cell_center(cell)
		)
		var screen_point: Vector2 = drive._world_to_screen(world_position)
		if points[points.size() - 1].distance_to(screen_point) > 1.0:
			points.append(screen_point)

	if points.size() < 2:
		return

	var road_world_width: float = (
		drive.NEIGHBORHOOD_ROAD_WIDTH
		if drive.road_kind == "neighborhood"
		else drive.CITY_ROAD_WIDTH
	)
	var route_width: float = (
		road_world_width
		* drive._current_world_zoom()
		* ROUTE_WIDTH_RATIO
	)

	draw_polyline(
		points,
		ROUTE_LINE_UNDERLAY,
		route_width + 3.0,
		true
	)
	draw_polyline(
		points,
		ROUTE_LINE_COLOR,
		route_width,
		true
	)


func _current_route_states() -> Array[Vector3i]:
	match drive.road_kind:
		"neighborhood":
			return _find_route_states(
				drive.neighborhood_cell,
				drive.heading,
				MAP.NEIGHBORHOOD_GATE,
				MAP.NEIGHBORHOOD_SIZE,
				true
			)
		"city":
			return _find_route_states(
				drive.city_cell,
				drive.heading,
				MAP.CITY_DESTINATION,
				MAP.CITY_SIZE,
				false
			)

	return []


func _current_turn_hint() -> Dictionary:
	var states := _current_route_states()
	match drive.road_kind:
		"neighborhood":
			return _first_turn_on_route(states, MAP.NEIGHBORHOOD_GATE_SIDE)
		"city":
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
