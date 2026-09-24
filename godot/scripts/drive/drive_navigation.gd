extends Label

## GPS-style route guidance for the driving microgame.
## Uses a conventional center route line plus a compact top instruction banner.

const MAP = preload("res://scripts/drive/drive_grid_map.gd")

const ROUTE_SHADOW_COLOR := Color(0.02, 0.08, 0.18, 0.52)
const ROUTE_LINE_COLOR := Color(0.10, 0.42, 0.96, 0.98)
const ROUTE_SHADOW_WIDTH_RATIO := 0.48
const ROUTE_LINE_WIDTH_RATIO := 0.32
const ROUTE_START_AHEAD_RATIO := 0.02

const BANNER_COLOR := Color(0.10, 0.14, 0.19, 0.96)
const BANNER_TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const BANNER_SUBTEXT_COLOR := Color(0.88, 0.96, 0.92, 0.92)
const BANNER_MARGIN := 16.0
const BANNER_HEIGHT := 82.0
const BANNER_RADIUS := 12.0

@onready var drive = $"../CityMap"
@onready var status_label: Label = $"../StatusLabel"

const MISSED_EXIT_NOTICE_SECONDS := 1.6

var last_missed_turns := 0
var missed_exit_notice_remaining := 0.0


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


func _process(delta: float) -> void:
	if drive != null:
		if drive.missed_turns > last_missed_turns:
			last_missed_turns = drive.missed_turns
			missed_exit_notice_remaining = MISSED_EXIT_NOTICE_SECONDS
		elif drive.missed_turns < last_missed_turns:
			last_missed_turns = drive.missed_turns

	if missed_exit_notice_remaining > 0.0:
		missed_exit_notice_remaining = maxf(
			0.0,
			missed_exit_notice_remaining - delta
		)

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

	# The GPS banner is the only driving status UI. This prevents legacy labels
	# such as "CONNECTOR" from appearing behind the banner.
	status_label.hide()


func _draw() -> void:
	if drive == null or not drive.started or drive.drive_complete:
		return

	_draw_route_line()
	_draw_instruction_banner()


func _should_draw_route_line() -> bool:
	return (
		drive != null
		and (drive.road_kind == "neighborhood" or drive.road_kind == "city")
	)


func _draw_route_line() -> void:
	# Blue route is only useful on the street grids. Keep ramps, highway,
	# and the parking lot visually clean.
	if not _should_draw_route_line():
		return

	var world_points: PackedVector2Array = _current_route_world_points()
	if world_points.size() < 2:
		return

	var road_world_width: float = _current_road_world_width()
	var zoom: float = drive._current_world_zoom()
	var shadow_width: float = road_world_width * zoom * ROUTE_SHADOW_WIDTH_RATIO
	var line_width: float = road_world_width * zoom * ROUTE_LINE_WIDTH_RATIO
	var screen_points := PackedVector2Array()

	for world_point in world_points:
		screen_points.append(drive._world_to_screen(world_point))

	if screen_points.size() < 2:
		return

	screen_points[0] = screen_points[0].lerp(
		screen_points[1],
		ROUTE_START_AHEAD_RATIO
	)

	# Keep one continuous GPS route line visible through every drive section.
	draw_polyline(screen_points, ROUTE_SHADOW_COLOR, shadow_width, true)
	draw_polyline(screen_points, ROUTE_LINE_COLOR, line_width, true)


func _current_road_world_width() -> float:
	match drive.road_kind:
		"neighborhood":
			return drive.NEIGHBORHOOD_ROAD_WIDTH
		"city":
			return drive.CITY_ROAD_WIDTH
		"highway":
			return float(MAP.HIGHWAY_LANE_WIDTH) * 0.72
		"connector_one", "connector_two":
			return float(MAP.HIGHWAY_LANE_WIDTH) * 0.85
	return drive.NEIGHBORHOOD_ROAD_WIDTH


func _current_route_world_points() -> PackedVector2Array:
	match drive.road_kind:
		"neighborhood", "city":
			if (
				drive.road_kind == "city"
				and drive.parking_maneuver_started
			):
				return PackedVector2Array([
					drive.visual_world_position,
					drive._parking_stop_point(),
				])

			var route: Array[Vector3i] = _current_route_states()
			if route.is_empty():
				return PackedVector2Array()
			return _route_world_points(route)

		"connector_one":
			return PackedVector2Array([
				drive.visual_world_position,
				MAP.highway_entry_point(),
			])

		"highway":
			var exit_lane_center: Vector2 = drive._highway_cell_center(
				MAP.HIGHWAY_COLUMNS - 1,
				MAP.HIGHWAY_EXIT_LANE
			)
			var points := PackedVector2Array([drive.visual_world_position])

			# If the player is not in the exit lane, aim the blue route gently
			# toward it instead of making the line disappear on the highway.
			if drive.highway_lane != MAP.HIGHWAY_EXIT_LANE:
				var merge_x: float = lerpf(
					drive.visual_world_position.x,
					exit_lane_center.x,
					0.42
				)
				points.append(Vector2(merge_x, exit_lane_center.y))

			points.append(exit_lane_center)
			return points

		"connector_two":
			return PackedVector2Array([
				drive.visual_world_position,
				drive._city_entry_point(),
			])

	return PackedVector2Array()


func _draw_instruction_banner() -> void:
	var instruction := _current_instruction()
	if instruction.is_empty():
		return

	var banner_width := minf(size.x - BANNER_MARGIN * 2.0, 420.0)
	var banner_rect := Rect2(
		Vector2((size.x - banner_width) * 0.5, BANNER_MARGIN),
		Vector2(banner_width, BANNER_HEIGHT)
	)
	draw_style_box(
		_make_banner_style(),
		banner_rect
	)

	var icon_rect := Rect2(
		banner_rect.position + Vector2(14.0, 14.0),
		Vector2(48.0, 48.0)
	)
	_draw_turn_icon(icon_rect, String(instruction.get("turn", "straight")))

	var font := get_theme_default_font()
	var title_size := 22
	var sub_size := 14
	var text_x := banner_rect.position.x + 76.0
	var title_y := banner_rect.position.y + 32.0
	var sub_y := banner_rect.position.y + 57.0

	draw_string(
		font,
		Vector2(text_x, title_y),
		String(instruction.get("title", "Continue")),
		HORIZONTAL_ALIGNMENT_LEFT,
		banner_rect.end.x - text_x - 12.0,
		title_size,
		BANNER_TEXT_COLOR
	)
	draw_string(
		font,
		Vector2(text_x, sub_y),
		String(instruction.get("subtitle", "")),
		HORIZONTAL_ALIGNMENT_LEFT,
		banner_rect.end.x - text_x - 12.0,
		sub_size,
		BANNER_SUBTEXT_COLOR
	)


func _make_banner_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BANNER_COLOR
	style.corner_radius_top_left = int(BANNER_RADIUS)
	style.corner_radius_top_right = int(BANNER_RADIUS)
	style.corner_radius_bottom_left = int(BANNER_RADIUS)
	style.corner_radius_bottom_right = int(BANNER_RADIUS)
	return style


func _draw_turn_icon(rect: Rect2, turn: String) -> void:
	var center := rect.get_center()
	var color := BANNER_TEXT_COLOR
	var width := 5.0
	var points := PackedVector2Array()

	match turn:
		"left":
			points = PackedVector2Array([
				Vector2(rect.end.x - 8.0, rect.end.y - 8.0),
				Vector2(rect.end.x - 8.0, center.y),
				Vector2(rect.position.x + 12.0, center.y),
			])
			draw_polyline(points, color, width, true)
			draw_line(
				Vector2(rect.position.x + 12.0, center.y),
				Vector2(rect.position.x + 24.0, center.y - 12.0),
				color, width, true
			)
			draw_line(
				Vector2(rect.position.x + 12.0, center.y),
				Vector2(rect.position.x + 24.0, center.y + 12.0),
				color, width, true
			)
		"right":
			points = PackedVector2Array([
				Vector2(rect.position.x + 8.0, rect.end.y - 8.0),
				Vector2(rect.position.x + 8.0, center.y),
				Vector2(rect.end.x - 12.0, center.y),
			])
			draw_polyline(points, color, width, true)
			draw_line(
				Vector2(rect.end.x - 12.0, center.y),
				Vector2(rect.end.x - 24.0, center.y - 12.0),
				color, width, true
			)
			draw_line(
				Vector2(rect.end.x - 12.0, center.y),
				Vector2(rect.end.x - 24.0, center.y + 12.0),
				color, width, true
			)
		_:
			draw_line(
				Vector2(center.x, rect.end.y - 8.0),
				Vector2(center.x, rect.position.y + 10.0),
				color, width, true
			)
			draw_line(
				Vector2(center.x, rect.position.y + 10.0),
				Vector2(center.x - 11.0, rect.position.y + 21.0),
				color, width, true
			)
			draw_line(
				Vector2(center.x, rect.position.y + 10.0),
				Vector2(center.x + 11.0, rect.position.y + 21.0),
				color, width, true
			)


func _current_instruction() -> Dictionary:
	if (
		drive.road_kind == "highway"
		and missed_exit_notice_remaining > 0.0
	):
		return {
			"turn": "straight",
			"title": "Missed exit",
			"subtitle": "Continue ahead — rerouting",
		}

	match drive.road_kind:
		"neighborhood", "city":
			var hint: Dictionary = _current_turn_hint()
			if hint.is_empty():
				if drive.road_kind == "city":
					return {
						"turn": "right",
						"title": "Turn right",
						"subtitle": "Into parking lot",
					}
				return {
					"turn": "straight",
					"title": "Continue straight",
					"subtitle": "Follow the blue route",
				}
			var turn := String(hint.get("turn", "straight"))
			var turn_cell: Vector2i = hint.get("cell", Vector2i.ZERO)
			var turn_world: Vector2 = (
				MAP.neighborhood_cell_center(turn_cell)
				if drive.road_kind == "neighborhood"
				else drive._city_cell_center(turn_cell)
			)
			var block_size: float = (
				float(MAP.NEIGHBORHOOD_CELL)
				if drive.road_kind == "neighborhood"
				else float(MAP.CITY_CELL)
			)
			# Logical cells advance as soon as a segment begins, while the car is
			# still visually travelling through that block. Count from the car's
			# actual world position so the banner matches what the player sees.
			var blocks: int = maxi(
				1,
				int(ceil(drive.visual_world_position.distance_to(turn_world) / block_size))
			)
			return {
				"turn": turn,
				"title": "Turn %s" % turn,
				"subtitle": "In %d block%s" % [
					blocks,
					"" if blocks == 1 else "s",
				],
			}
		"connector_one":
			return {
				"turn": "straight",
				"title": "Merge onto highway",
				"subtitle": "Continue ahead",
			}
		"highway":
			if drive.highway_lane < MAP.HIGHWAY_EXIT_LANE:
				return {
					"turn": "right",
					"title": "Move right",
					"subtitle": "Use lane 4 for the exit",
				}
			return {
				"turn": "straight",
				"title": "Stay in lane 4",
				"subtitle": "Exit ahead",
			}
		"connector_two":
			return {
				"turn": "straight",
				"title": "Take the exit",
				"subtitle": "Continue into the city",
			}
		"parking":
			if drive.parking_phase == 0:
				return {
					"turn": "straight",
					"title": "Choose an aisle",
					"subtitle": "Turn left or right",
				}
			if drive.parking_phase == 1:
				return {
					"turn": "straight",
					"title": "Enter aisle",
					"subtitle": "Then choose a space",
				}
			if drive.parking_phase == 2:
				return {
					"turn": "straight",
					"title": "Choose a parking spot",
					"subtitle": "Left or right",
				}
			return {
				"turn": "straight",
				"title": "Parking",
				"subtitle": "Open space selected",
			}
	return {}


func _route_world_points(route: Array[Vector3i]) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.append(drive.visual_world_position)

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


func _world_segment_is_local(from_world: Vector2, to_world: Vector2) -> bool:
	var expected_length: float = (
		float(MAP.NEIGHBORHOOD_CELL)
		if drive.road_kind == "neighborhood"
		else float(MAP.CITY_CELL)
	)
	var delta := to_world - from_world
	var axis_aligned := (
		is_zero_approx(delta.x)
		or is_zero_approx(delta.y)
	)
	return axis_aligned and delta.length() <= expected_length + 0.5


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
