extends Control

## DRIVE v0.12
## One world-space road network. Neighborhood, connectors, highway, city and
## parking are not loaded as separate stages; the car simply enters different
## connected road geometry and the control rules follow the road under it.

signal trip_finished(result: Dictionary)

const NETWORK = preload("res://scripts/drive/drive_road_network.gd")

@export var world_seed: int = 0 # Kept for compatibility with the existing harness.

var started := false
var drive_complete := false
var drive_time := 0.0
var missed_turns := 0
var bumps := 0

var current_road_kind := "neighborhood"
var active_stage_id := "neighborhood" # Compatibility label; never loads a stage.
var camera_zoom := NETWORK.NEIGHBORHOOD_ZOOM
var player_world_position := Vector2.ZERO
var camera_world_position := Vector2.ZERO

var street_nodes: Dictionary = {}
var street_edges: Array = []
var street_adjacency: Dictionary = {}
var street_current := ""
var street_target := ""
var street_previous := ""
var street_goal := ""
var street_heading := Vector2.UP
var street_driving := false
var waiting_for_turn := false
var shortest_route: Array[String] = []

var connector_progress := 0.0
var exit_progress := 0.0
var parking_widen_progress := 0.0

var lane_count := 1
var current_lane := 0
var target_lane := 0
var highway_after_fork := false
var parking_spot_y := NETWORK.FIRST_PARKING_SPOT_Y

var player_screen_center := Vector2.ZERO
var car_base_position := Vector2.ZERO

@onready var player_car: TextureRect = $"../PlayerCar"
@onready var left_button: Button = $"../TouchControls/LeftButton"
@onready var forward_button: Button = $"../TouchControls/ForwardButton"
@onready var right_button: Button = $"../TouchControls/RightButton"
@onready var status_label: Label = $"../StatusLabel"


func _ready() -> void:
	left_button.pressed.connect(_turn_left)
	forward_button.pressed.connect(_move_forward)
	right_button.pressed.connect(_turn_right)

	car_base_position = player_car.position
	player_screen_center = player_car.position + player_car.size * 0.5
	player_car.pivot_offset = player_car.size * 0.5

	_enter_neighborhood()
	_update_car_visual()
	status_label.text = "TAP START"
	call_deferred("_refresh_mobile_layout")


func _refresh_mobile_layout() -> void:
	# Web/mobile Control layout can settle one frame after _ready(). Keep the
	# procedural road camera aligned to the actual canvas and car at that point.
	player_screen_center = size * 0.5
	car_base_position = player_screen_center - player_car.size * 0.5
	player_car.position = car_base_position
	queue_redraw()


func _process(delta: float) -> void:
	if drive_complete:
		return

	if started:
		drive_time += delta

	match current_road_kind:
		"neighborhood", "city":
			_process_street(delta)
		"connector_out":
			_process_connector_out(delta)
		"highway":
			_process_highway(delta)
		"exit_connector":
			_process_exit_connector(delta)
		"parking_widen":
			_process_parking_widen(delta)
		"parking":
			_process_parking(delta)

	camera_world_position = player_world_position
	_update_car_visual()
	queue_redraw()


func _enter_neighborhood() -> void:
	current_road_kind = "neighborhood"
	active_stage_id = current_road_kind
	camera_zoom = NETWORK.NEIGHBORHOOD_ZOOM
	street_nodes = NETWORK.neighborhood_nodes()
	street_edges = NETWORK.neighborhood_edges()
	street_adjacency = _build_adjacency(street_nodes, street_edges)
	street_current = "n0"
	street_target = ""
	street_previous = ""
	street_goal = "n7"
	street_heading = Vector2.UP
	street_driving = false
	waiting_for_turn = false
	player_world_position = street_nodes[street_current]
	shortest_route = _find_route(street_current, street_goal)


func _enter_city() -> void:
	current_road_kind = "city"
	active_stage_id = current_road_kind
	camera_zoom = NETWORK.CITY_ZOOM
	street_nodes = NETWORK.city_nodes()
	street_edges = NETWORK.city_edges()
	street_adjacency = _build_adjacency(street_nodes, street_edges)
	street_current = "c0"
	street_target = ""
	street_previous = ""
	street_goal = "c8"
	street_heading = NETWORK.exit_curve_tangent(1.0)
	street_driving = false
	waiting_for_turn = false
	player_world_position = street_nodes[street_current]
	shortest_route = _find_route(street_current, street_goal)
	_continue_street_along_route(true)


func _move_forward() -> void:
	if drive_complete:
		return

	if not started:
		started = true
		forward_button.hide()
		status_label.text = ""
		_continue_street_along_route(true)
		return

	if (
		(current_road_kind == "neighborhood" or current_road_kind == "city")
		and waiting_for_turn
	):
		# START is intentionally not a second driving verb.
		return


func _turn_left() -> void:
	if drive_complete:
		return

	if current_road_kind == "neighborhood" or current_road_kind == "city":
		if waiting_for_turn:
			_take_relative_turn(-1)
		return

	if current_road_kind == "highway":
		target_lane = maxi(0, target_lane - 1)
	elif current_road_kind == "parking":
		target_lane = maxi(0, target_lane - 1)


func _turn_right() -> void:
	if drive_complete:
		return

	if current_road_kind == "neighborhood" or current_road_kind == "city":
		if waiting_for_turn:
			_take_relative_turn(1)
		return

	if current_road_kind == "highway":
		target_lane = mini(lane_count - 1, target_lane + 1)
	elif current_road_kind == "parking":
		target_lane = mini(1, target_lane + 1)


func _process_street(delta: float) -> void:
	if not started or not street_driving:
		return

	var target_position: Vector2 = street_nodes[street_target]
	player_world_position = player_world_position.move_toward(
		target_position,
		_street_speed() * delta
	)

	if not player_world_position.is_equal_approx(target_position):
		return

	player_world_position = target_position
	var arrived_from := street_current
	street_previous = arrived_from
	street_current = street_target
	street_target = ""
	street_driving = false

	if street_current == street_goal:
		if current_road_kind == "neighborhood":
			_enter_connector_out()
		else:
			_enter_parking_widen()
		return

	shortest_route = _find_route(street_current, street_goal)
	_continue_street_along_route(false)


func _continue_street_along_route(force_first: bool) -> void:
	if shortest_route.size() < 2:
		return

	var desired: String = shortest_route[1]
	var desired_direction := (
		(street_nodes[desired] as Vector2)
		- (street_nodes[street_current] as Vector2)
	).normalized()

	if force_first or _is_straight(street_heading, desired_direction):
		_start_street_segment(desired)
		return

	waiting_for_turn = true
	status_label.text = "TURN"


func _start_street_segment(next_node: String) -> void:
	var from_position: Vector2 = street_nodes[street_current]
	var to_position: Vector2 = street_nodes[next_node]
	street_heading = (to_position - from_position).normalized()
	street_target = next_node
	street_driving = true
	waiting_for_turn = false
	status_label.text = ""


func _take_relative_turn(side: int) -> void:
	var candidates: Array[String] = []

	for neighbor in street_adjacency.get(street_current, []):
		var neighbor_id := str(neighbor)
		if neighbor_id == street_previous:
			continue

		var direction := (
			(street_nodes[neighbor_id] as Vector2)
			- (street_nodes[street_current] as Vector2)
		).normalized()
		var cross := street_heading.cross(direction)

		if side < 0 and cross < -0.25:
			candidates.append(neighbor_id)
		elif side > 0 and cross > 0.25:
			candidates.append(neighbor_id)

	if candidates.is_empty():
		return

	# Prefer the route road when it exists on the requested side; otherwise the
	# button still takes the physical road the player chose and GPS can reroute.
	var chosen := candidates[0]
	if shortest_route.size() >= 2 and candidates.has(shortest_route[1]):
		chosen = shortest_route[1]

	if shortest_route.size() >= 2 and chosen != shortest_route[1]:
		missed_turns += 1

	_start_street_segment(chosen)
	shortest_route = _find_route(chosen, street_goal)


func _enter_connector_out() -> void:
	current_road_kind = "connector_out"
	active_stage_id = current_road_kind
	connector_progress = 0.0
	street_driving = false
	waiting_for_turn = false
	status_label.text = ""
	player_world_position = NETWORK.CONNECTOR_OUT_START


func _process_connector_out(delta: float) -> void:
	if not started:
		return

	connector_progress = minf(
		NETWORK.CONNECTOR_OUT_LENGTH,
		connector_progress + NETWORK.CONNECTOR_SPEED * delta
	)
	var t := connector_progress / NETWORK.CONNECTOR_OUT_LENGTH
	var eased := smoothstep(0.0, 1.0, t)

	# Micro-pass: the car simply follows one physical connector road.
	player_world_position = NETWORK.connector_out_curve(t)

	# Keep the existing zoom behavior untouched for this pass.
	camera_zoom = lerpf(
		NETWORK.NEIGHBORHOOD_ZOOM,
		NETWORK.HIGHWAY_ZOOM,
		eased
	)

	if connector_progress >= NETWORK.CONNECTOR_OUT_LENGTH:
		_enter_highway()


func _enter_highway() -> void:
	current_road_kind = "highway"
	active_stage_id = current_road_kind
	camera_zoom = NETWORK.HIGHWAY_ZOOM
	lane_count = 4
	current_lane = 1
	target_lane = 1
	highway_after_fork = false
	player_world_position = Vector2(
		NETWORK.highway_lane_center(1, 4),
		NETWORK.HIGHWAY_START_Y
	)
	status_label.text = ""


func _process_highway(delta: float) -> void:
	if not started:
		return

	var lane_x := _highway_lane_x(target_lane)
	player_world_position.x = move_toward(
		player_world_position.x,
		lane_x,
		360.0 * delta
	)
	player_world_position.y -= NETWORK.HIGHWAY_SPEED * delta
	current_lane = _nearest_highway_lane(player_world_position.x)

	var remaining := player_world_position.y - NETWORK.HIGHWAY_FORK_Y
	if not highway_after_fork and remaining < 1150.0 and remaining > 0.0:
		status_label.text = "EXIT  >"

	if not highway_after_fork and player_world_position.y <= NETWORK.HIGHWAY_FORK_Y:
		var exit_x := NETWORK.highway_lane_center(3, 4)
		if current_lane == 3 and absf(player_world_position.x - exit_x) < 28.0:
			_enter_exit_connector()
			return

		missed_turns += 1
		highway_after_fork = true
		lane_count = 3
		target_lane = clampi(target_lane, 0, 2)
		current_lane = clampi(current_lane, 0, 2)
		status_label.text = "MISSED EXIT"

	if highway_after_fork and player_world_position.y < NETWORK.HIGHWAY_FORK_Y - 900.0:
		status_label.text = ""


func _enter_exit_connector() -> void:
	current_road_kind = "exit_connector"
	active_stage_id = current_road_kind
	exit_progress = 0.0
	player_world_position = NETWORK.EXIT_START
	status_label.text = ""


func _process_exit_connector(delta: float) -> void:
	var curve_length := 1450.0
	exit_progress = minf(
		curve_length,
		exit_progress + NETWORK.CONNECTOR_SPEED * delta
	)
	var t := exit_progress / curve_length
	player_world_position = NETWORK.exit_curve(t)
	camera_zoom = lerpf(
		NETWORK.HIGHWAY_ZOOM,
		NETWORK.CITY_ZOOM,
		smoothstep(0.0, 1.0, t)
	)

	if exit_progress >= curve_length:
		_enter_city()


func _enter_parking_widen() -> void:
	current_road_kind = "parking_widen"
	active_stage_id = current_road_kind
	parking_widen_progress = 0.0
	street_driving = false
	waiting_for_turn = false
	player_world_position = NETWORK.city_nodes()["c8"]
	status_label.text = ""


func _process_parking_widen(delta: float) -> void:
	var start: Vector2 = NETWORK.city_nodes()["c8"]
	var finish := NETWORK.PARK_WIDEN_END
	var length := start.distance_to(finish)

	parking_widen_progress = minf(
		length,
		parking_widen_progress + NETWORK.CITY_SPEED * delta
	)
	var t := parking_widen_progress / length
	player_world_position = start.lerp(finish, t)
	camera_zoom = NETWORK.CITY_ZOOM

	if parking_widen_progress >= length:
		_enter_parking()


func _enter_parking() -> void:
	current_road_kind = "parking"
	active_stage_id = current_road_kind
	lane_count = 2
	current_lane = 0
	target_lane = 0
	parking_spot_y = NETWORK.FIRST_PARKING_SPOT_Y
	player_world_position = Vector2(
		_parking_lane_x(0),
		NETWORK.PARK_WIDEN_END.y
	)
	status_label.text = ""


func _process_parking(delta: float) -> void:
	player_world_position.x = move_toward(
		player_world_position.x,
		_parking_lane_x(target_lane),
		300.0 * delta
	)
	player_world_position.y -= NETWORK.PARK_SPEED * delta
	current_lane = _nearest_parking_lane(player_world_position.x)

	var remaining := player_world_position.y - parking_spot_y
	if remaining < 750.0 and remaining > 0.0:
		status_label.text = "PARK  >"

	if player_world_position.y <= parking_spot_y:
		if (
			current_lane == 1
			and absf(player_world_position.x - _parking_lane_x(1)) < 34.0
		):
			_finish_drive()
			return

		missed_turns += 1
		parking_spot_y -= 620.0
		status_label.text = "NEXT SPOT  >"


func _street_speed() -> float:
	return (
		NETWORK.NEIGHBORHOOD_SPEED
		if current_road_kind == "neighborhood"
		else NETWORK.CITY_SPEED
	)


func _highway_lane_x(lane: int) -> float:
	if highway_after_fork:
		return (
			-39.0
			+ (float(lane) - 1.0) * NETWORK.HIGHWAY_LANE_WIDTH
		)
	return NETWORK.highway_lane_center(lane, 4)


func _nearest_highway_lane(x: float) -> int:
	var best_lane := 0
	var best_distance := INF
	for lane in range(lane_count):
		var distance := absf(x - _highway_lane_x(lane))
		if distance < best_distance:
			best_distance = distance
			best_lane = lane
	return best_lane


func _parking_lane_x(lane: int) -> float:
	return 2100.0 + float(lane) * NETWORK.PARK_LANE_WIDTH


func _nearest_parking_lane(x: float) -> int:
	return 0 if absf(x - _parking_lane_x(0)) <= absf(x - _parking_lane_x(1)) else 1


func _build_adjacency(nodes: Dictionary, edges: Array) -> Dictionary:
	var adjacency: Dictionary = {}
	for key in nodes:
		adjacency[key] = []

	for edge in edges:
		var a := str(edge[0])
		var b := str(edge[1])
		adjacency[a].append(b)
		adjacency[b].append(a)

	return adjacency


func _find_route(start_node: String, end_node: String) -> Array[String]:
	var queue: Array[String] = [start_node]
	var came_from: Dictionary = {start_node: start_node}

	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == end_node:
			break

		for neighbor in street_adjacency.get(current, []):
			var neighbor_id := str(neighbor)
			if not came_from.has(neighbor_id):
				came_from[neighbor_id] = current
				queue.append(neighbor_id)

	var route: Array[String] = []
	if not came_from.has(end_node):
		return route

	var cursor := end_node
	while cursor != start_node:
		route.push_front(cursor)
		cursor = str(came_from[cursor])
	route.push_front(start_node)
	return route


func _is_straight(a: Vector2, b: Vector2) -> bool:
	return a.normalized().dot(b.normalized()) > 0.92


func _update_car_visual() -> void:
	player_car.position = car_base_position
	player_car.scale = Vector2.ONE * camera_zoom

	var direction := Vector2.UP
	match current_road_kind:
		"neighborhood", "city":
			direction = street_heading
		"connector_out":
			direction = NETWORK.connector_out_tangent(
				connector_progress / NETWORK.CONNECTOR_OUT_LENGTH
			)
		"exit_connector":
			direction = NETWORK.exit_curve_tangent(
				exit_progress / 1450.0
			)
		_:
			direction = Vector2.UP

	player_car.rotation = direction.angle() + PI / 2.0


func _draw() -> void:
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color(0.11, 0.11, 0.11),
		true
	)

	_draw_street_graph(
		NETWORK.neighborhood_nodes(),
		NETWORK.neighborhood_edges(),
		NETWORK.STREET_WIDTH
	)
	_draw_connector_out()
	_draw_highway()
	_draw_exit_connector()
	_draw_street_graph(
		NETWORK.city_nodes(),
		NETWORK.city_edges(),
		NETWORK.STREET_WIDTH
	)
	_draw_parking_widen()
	_draw_parking_street()
	_draw_minimap()


func _draw_street_graph(
	nodes: Dictionary,
	edges: Array,
	width: float
) -> void:
	for edge in edges:
		var a: Vector2 = nodes[str(edge[0])]
		var b: Vector2 = nodes[str(edge[1])]
		_draw_world_road_line(a, b, width)


func _draw_connector_out() -> void:
	# Micro-pass: one plain road between the existing neighborhood and highway.
	# No widening, lane-emergence polish, or additional transition behavior yet.
	var points := PackedVector2Array()
	for index in range(17):
		var t := float(index) / 16.0
		points.append(_world_to_screen(NETWORK.connector_out_curve(t)))

	_draw_screen_polyline_road(
		points,
		NETWORK.STREET_WIDTH * camera_zoom
	)


func _draw_highway() -> void:
	var pre_start := Vector2(
		NETWORK.HIGHWAY_CENTER_X,
		NETWORK.HIGHWAY_START_Y
	)
	var fork_center := Vector2(
		NETWORK.HIGHWAY_CENTER_X,
		NETWORK.HIGHWAY_FORK_Y
	)
	_draw_world_road_line(
		pre_start,
		fork_center,
		NETWORK.HIGHWAY_LANE_WIDTH * 4.0
	)

	# After the split the left three lanes continue exactly where they already
	# were. Their shared center is x = -39.
	var post_center_x := -39.0
	_draw_world_road_line(
		Vector2(post_center_x, NETWORK.HIGHWAY_FORK_Y),
		Vector2(post_center_x, NETWORK.HIGHWAY_END_Y),
		NETWORK.HIGHWAY_LANE_WIDTH * 3.0
	)

	for x in [-78.0, 0.0, 78.0]:
		_draw_world_dashed_line(
			Vector2(x, NETWORK.HIGHWAY_START_Y),
			Vector2(x, NETWORK.HIGHWAY_FORK_Y),
			3.0,
			Color(0.82, 0.80, 0.70)
		)

	for x in [-78.0, 0.0]:
		_draw_world_dashed_line(
			Vector2(x, NETWORK.HIGHWAY_FORK_Y),
			Vector2(x, NETWORK.HIGHWAY_END_Y),
			3.0,
			Color(0.82, 0.80, 0.70)
		)


func _draw_exit_connector() -> void:
	var points := PackedVector2Array()
	for index in range(17):
		var t := float(index) / 16.0
		points.append(_world_to_screen(NETWORK.exit_curve(t)))

	_draw_screen_polyline_road(
		points,
		NETWORK.HIGHWAY_LANE_WIDTH * camera_zoom
	)


func _draw_parking_widen() -> void:
	var start: Vector2 = NETWORK.city_nodes()["c8"]
	var finish := NETWORK.PARK_WIDEN_END

	# The left edge stays fixed so the existing city lane remains the travel
	# lane while a new curb lane physically grows on its right.
	var direction := (finish - start).normalized()
	var side := Vector2(-direction.y, direction.x)
	var left_edge_start := start - side * NETWORK.STREET_WIDTH * 0.5
	var right_edge_start := start + side * NETWORK.STREET_WIDTH * 0.5
	var left_edge_end := finish - side * NETWORK.PARK_LANE_WIDTH * 0.5
	var right_edge_end := finish + side * NETWORK.PARK_LANE_WIDTH * 1.5

	_draw_world_polygon(
		PackedVector2Array([
			left_edge_start,
			right_edge_start,
			right_edge_end,
			left_edge_end,
		]),
		Color(0.50, 0.49, 0.44)
	)

	var inset := 7.0
	_draw_world_polygon(
		PackedVector2Array([
			left_edge_start + side * inset,
			right_edge_start - side * inset,
			right_edge_end - side * inset,
			left_edge_end + side * inset,
		]),
		Color(0.15, 0.16, 0.16)
	)


func _draw_parking_street() -> void:
	var start := NETWORK.PARK_WIDEN_END
	var end := Vector2(start.x + NETWORK.PARK_LANE_WIDTH * 0.5, parking_spot_y - 1600.0)
	var center_x := 2100.0 + NETWORK.PARK_LANE_WIDTH * 0.5

	_draw_world_road_line(
		Vector2(center_x, start.y),
		Vector2(center_x, end.y),
		NETWORK.PARK_LANE_WIDTH * 2.0
	)
	_draw_world_dashed_line(
		Vector2(2100.0 + NETWORK.PARK_LANE_WIDTH * 0.5, start.y),
		Vector2(2100.0 + NETWORK.PARK_LANE_WIDTH * 0.5, end.y),
		3.0,
		Color(0.82, 0.80, 0.70)
	)

	# Current available curb space. Missing it simply reveals the next one
	# further up the same physical street.
	var spot_center := Vector2(_parking_lane_x(1), parking_spot_y)
	var spot_size := Vector2(
		NETWORK.PARK_LANE_WIDTH * 0.72,
		160.0
	)
	var screen_center := _world_to_screen(spot_center)
	var scaled_size := spot_size * camera_zoom
	draw_rect(
		Rect2(screen_center - scaled_size * 0.5, scaled_size),
		Color(0.84, 0.82, 0.74),
		false,
		4.0
	)


func _draw_world_road_line(a: Vector2, b: Vector2, width: float) -> void:
	var sa := _world_to_screen(a)
	var sb := _world_to_screen(b)
	draw_line(
		sa,
		sb,
		Color(0.50, 0.49, 0.44),
		(width + 16.0) * camera_zoom,
		true
	)
	draw_line(
		sa,
		sb,
		Color(0.15, 0.16, 0.16),
		width * camera_zoom,
		true
	)


func _draw_tapered_road(
	a: Vector2,
	b: Vector2,
	width_a: float,
	width_b: float
) -> void:
	var direction := (b - a).normalized()
	var side := Vector2(-direction.y, direction.x)

	var outer := PackedVector2Array([
		a - side * (width_a + 16.0) * 0.5,
		a + side * (width_a + 16.0) * 0.5,
		b + side * (width_b + 16.0) * 0.5,
		b - side * (width_b + 16.0) * 0.5,
	])
	_draw_world_polygon(outer, Color(0.50, 0.49, 0.44))

	var inner := PackedVector2Array([
		a - side * width_a * 0.5,
		a + side * width_a * 0.5,
		b + side * width_b * 0.5,
		b - side * width_b * 0.5,
	])
	_draw_world_polygon(inner, Color(0.15, 0.16, 0.16))


func _draw_world_polygon(points: PackedVector2Array, color: Color) -> void:
	var screen_points := PackedVector2Array()
	for point in points:
		screen_points.append(_world_to_screen(point))
	draw_colored_polygon(screen_points, color)


func _draw_screen_polyline_road(
	points: PackedVector2Array,
	width: float
) -> void:
	draw_polyline(
		points,
		Color(0.50, 0.49, 0.44),
		width + 16.0 * camera_zoom,
		true
	)
	draw_polyline(
		points,
		Color(0.15, 0.16, 0.16),
		width,
		true
	)


func _draw_world_dashed_line(
	a: Vector2,
	b: Vector2,
	width: float,
	color: Color
) -> void:
	var distance := a.distance_to(b)
	var direction := (b - a).normalized()
	var dash := 54.0
	var gap := 42.0
	var cursor := 0.0

	while cursor < distance:
		var start := a + direction * cursor
		var finish := a + direction * minf(cursor + dash, distance)
		draw_line(
			_world_to_screen(start),
			_world_to_screen(finish),
			color,
			width * camera_zoom,
			true
		)
		cursor += dash + gap


func _world_to_screen(world_point: Vector2) -> Vector2:
	return (
		player_screen_center
		+ (world_point - player_world_position) * camera_zoom
	)


func _draw_minimap() -> void:
	var rect := Rect2(
		Vector2(size.x - 118.0, 14.0),
		Vector2(104.0, 104.0)
	)
	draw_rect(rect, Color(0.06, 0.065, 0.06, 0.90), true)
	draw_rect(rect, Color(0.75, 0.74, 0.69, 0.75), false, 1.5)

	if current_road_kind == "neighborhood" or current_road_kind == "city":
		_draw_street_minimap(rect)
	elif current_road_kind == "highway":
		_draw_highway_minimap(rect)
	else:
		draw_line(
			rect.position + Vector2(52.0, 88.0),
			rect.position + Vector2(52.0, 16.0),
			Color(0.12, 0.48, 1.0),
			3.0
		)
		draw_circle(
			rect.position + Vector2(52.0, 74.0),
			4.0,
			Color(0.14, 0.86, 0.43)
		)


func _draw_street_minimap(rect: Rect2) -> void:
	if street_nodes.is_empty():
		return

	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for key in street_nodes:
		var point: Vector2 = street_nodes[key]
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)

	var span := max_point - min_point
	var usable := rect.size - Vector2(18.0, 18.0)
	var scale := minf(
		usable.x / maxf(span.x, 1.0),
		usable.y / maxf(span.y, 1.0)
	)
	var origin := rect.position + Vector2(9.0, 9.0)

	for edge in street_edges:
		var a: Vector2 = street_nodes[str(edge[0])]
		var b: Vector2 = street_nodes[str(edge[1])]
		draw_line(
			origin + (a - min_point) * scale,
			origin + (b - min_point) * scale,
			Color(0.55, 0.55, 0.51),
			2.0
		)

	for index in range(shortest_route.size() - 1):
		var a: Vector2 = street_nodes[shortest_route[index]]
		var b: Vector2 = street_nodes[shortest_route[index + 1]]
		draw_line(
			origin + (a - min_point) * scale,
			origin + (b - min_point) * scale,
			Color(0.12, 0.48, 1.0),
			3.0
		)

	draw_circle(
		origin + (player_world_position - min_point) * scale,
		4.0,
		Color(0.14, 0.86, 0.43)
	)


func _draw_highway_minimap(rect: Rect2) -> void:
	var x := rect.position.x + 48.0
	draw_line(
		Vector2(x, rect.end.y - 12.0),
		Vector2(x, rect.position.y + 12.0),
		Color(0.55, 0.55, 0.51),
		7.0
	)
	draw_line(
		Vector2(x, rect.position.y + 48.0),
		Vector2(rect.end.x - 12.0, rect.position.y + 20.0),
		Color(0.55, 0.55, 0.51),
		5.0
	)
	draw_circle(
		Vector2(x, rect.position.y + 72.0),
		4.0,
		Color(0.14, 0.86, 0.43)
	)


func _finish_drive() -> void:
	if drive_complete:
		return

	drive_complete = true
	started = false
	status_label.text = "ARRIVED"
	left_button.disabled = true
	forward_button.disabled = true
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
		KEY_A, KEY_LEFT:
			_turn_left()
		KEY_D, KEY_RIGHT:
			_turn_right()
		KEY_W, KEY_UP, KEY_SPACE:
			_move_forward()
