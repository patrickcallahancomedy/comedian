extends Label

## COMEDIAN DRIVE navigation
## Intentionally simple: one GPS-style instruction card, no route line.
## It stays active through neighborhood -> ramp -> highway -> ramp -> city.

const MAP = preload("res://scripts/drive/drive_grid_map.gd")

const FEET_PER_WORLD_UNIT := 4.0
const DISTANCE_ROUNDING_FT := 50
const CARD_TOP := 18.0
const CARD_HIDDEN_TOP := -96.0
const CARD_HEIGHT := 76.0
const CARD_SIDE_MARGIN := 18.0
const DROP_SPEED := 700.0

@onready var drive = $"../CityMap"
@onready var status_label: Label = $"../StatusLabel"

var card_visible := false


func _ready() -> void:
	z_index = 6
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_theme_font_size_override("font_size", 18)
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.30))
	add_theme_constant_override("shadow_offset_x", 1)
	add_theme_constant_override("shadow_offset_y", 1)
	add_theme_constant_override("outline_size", 0)

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.08, 0.10, 0.13, 0.96)
	panel.corner_radius_top_left = 14
	panel.corner_radius_top_right = 14
	panel.corner_radius_bottom_left = 14
	panel.corner_radius_bottom_right = 14
	panel.content_margin_left = 18.0
	panel.content_margin_right = 18.0
	panel.content_margin_top = 10.0
	panel.content_margin_bottom = 10.0
	add_theme_stylebox_override("normal", panel)

	_apply_card_rect(CARD_HIDDEN_TOP)
	text = ""
	hide()


func _process(delta: float) -> void:
	if drive == null:
		return

	card_visible = drive.started and not drive.drive_complete
	_update_status_visibility()

	if not card_visible:
		text = ""
		hide()
		_apply_card_rect(
			move_toward(offset_top, CARD_HIDDEN_TOP, DROP_SPEED * delta)
		)
		return

	show()
	text = _navigation_text()
	_apply_card_rect(
		move_toward(offset_top, CARD_TOP, DROP_SPEED * delta)
	)


func _apply_card_rect(top: float) -> void:
	var viewport_width := size.x
	if get_parent() is Control:
		viewport_width = (get_parent() as Control).size.x
	offset_left = CARD_SIDE_MARGIN
	offset_right = maxf(CARD_SIDE_MARGIN + 220.0, viewport_width - CARD_SIDE_MARGIN)
	offset_top = top
	offset_bottom = top + CARD_HEIGHT


func _update_status_visibility() -> void:
	if status_label == null:
		return
	if drive.started and not drive.drive_complete:
		status_label.hide()
	else:
		status_label.show()


func _navigation_text() -> String:
	match drive.road_kind:
		"neighborhood":
			return _local_road_instruction(true)
		"connector_one":
			return _connector_one_instruction()
		"highway":
			return _highway_instruction()
		"connector_two":
			return _connector_two_instruction()
		"city":
			return _local_road_instruction(false)
	return "CONTINUE"


func _local_road_instruction(neighborhood: bool) -> String:
	var route: Array[Vector3i] = _current_route_states()
	if route.is_empty():
		return "CONTINUE STRAIGHT"

	var final_direction := (
		MAP.NEIGHBORHOOD_GATE_SIDE
		if neighborhood
		else Vector2i.ZERO
	)
	var turn_info: Dictionary = _first_turn_on_route(route, final_direction)

	if not turn_info.is_empty():
		var turn_cell: Vector2i = turn_info.get("cell", Vector2i.ZERO)
		var turn_name := String(turn_info.get("turn", ""))
		var distance_world := _distance_along_route_to_cell(route, turn_cell)
		return "%s  TURN %s\n%s" % [
			_turn_symbol(turn_name),
			turn_name.to_upper(),
			_format_distance(distance_world),
		]

	if neighborhood:
		var gate_distance := drive.visual_world_position.distance_to(
			MAP.neighborhood_gate_outside_point()
		)
		return "↑  CONTINUE\nRAMP IN %s" % _format_distance(gate_distance)

	var destination := drive._parking_stop_point()
	var destination_distance := drive.visual_world_position.distance_to(destination)
	if destination_distance <= 28.0:
		return "P  PARK ON RIGHT\nDESTINATION"
	return "↑  CONTINUE\nDESTINATION IN %s" % _format_distance(destination_distance)


func _connector_one_instruction() -> String:
	var distance_world := drive.visual_world_position.distance_to(
		MAP.highway_entry_point()
	)
	return "↑  CONTINUE ON RAMP\nHIGHWAY IN %s" % _format_distance(distance_world)


func _highway_instruction() -> String:
	var exit_x := drive._highway_rect_for_lap(drive.highway_lap).end.x
	var distance_world := maxf(0.0, exit_x - drive.visual_world_position.x)

	if drive.highway_lane < MAP.HIGHWAY_EXIT_LANE:
		return "↱  KEEP RIGHT\nEXIT IN %s" % _format_distance(distance_world)

	return "↑  STAY IN RIGHT LANE\nEXIT IN %s" % _format_distance(distance_world)


func _connector_two_instruction() -> String:
	var distance_world := drive.visual_world_position.distance_to(
		drive._city_entry_point()
	)
	return "↑  TAKE EXIT RAMP\nCITY IN %s" % _format_distance(distance_world)


func _format_distance(world_distance: float) -> String:
	var feet := maxi(0, int(round(world_distance * FEET_PER_WORLD_UNIT)))
	if feet <= 25:
		return "NOW"
	var rounded := maxi(
		DISTANCE_ROUNDING_FT,
		int(round(float(feet) / DISTANCE_ROUNDING_FT)) * DISTANCE_ROUNDING_FT
	)
	if rounded >= 1000:
		var miles := float(rounded) / 5280.0
		if miles >= 0.2:
			return "%.1f MI" % miles
	return "%d FT" % rounded


func _turn_symbol(turn_name: String) -> String:
	if turn_name == "left":
		return "↰"
	if turn_name == "right":
		return "↱"
	return "↑"


func get_turn_hint() -> Dictionary:
	if drive == null or not drive.started or drive.drive_complete:
		return {}
	if drive.road_kind != "neighborhood" and drive.road_kind != "city":
		return {}
	return _current_turn_hint()


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


func _route_world_points(route: Array[Vector3i]) -> PackedVector2Array:
	var points := PackedVector2Array([drive.visual_world_position])
	for state in route:
		var cell := Vector2i(state.x, state.y)
		var world_position: Vector2 = (
			MAP.neighborhood_cell_center(cell)
			if drive.road_kind == "neighborhood"
			else drive._city_cell_center(cell)
		)
		if points[points.size() - 1].distance_to(world_position) > 0.5:
			points.append(world_position)
	return points


func _distance_along_route_to_cell(
	route: Array[Vector3i],
	target_cell: Vector2i
) -> float:
	var points := _route_world_points(route)
	if points.size() < 2:
		return 0.0

	var distance := 0.0
	var point_index := 1

	for state in route:
		var cell := Vector2i(state.x, state.y)
		var world_position: Vector2 = (
			MAP.neighborhood_cell_center(cell)
			if drive.road_kind == "neighborhood"
			else drive._city_cell_center(cell)
		)

		if point_index < points.size():
			var previous := points[point_index - 1]
			if previous.distance_to(world_position) > 0.5:
				distance += previous.distance_to(world_position)
				point_index += 1

		if cell == target_cell:
			break

	return distance


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
