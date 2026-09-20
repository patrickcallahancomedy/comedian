extends Control

const DRIVE_PROFILES = preload("res://scripts/drive/drive_profiles.gd")

@export var minimap_size := 142.0

var active_stage_id := ""
var active_profile: Dictionary = {}
var stage_index := 0

var steering_mode := "turn"
var lane_count := 1
var car_scale := 1.0
var drive_speed := DRIVE_PROFILES.BASE_SPEED
var lane_width := DRIVE_PROFILES.BASE_LANE_WIDTH
var road_width := DRIVE_PROFILES.BASE_LANE_WIDTH
var intersection_spacing := DRIVE_PROFILES.BASE_BLOCK_SPACING
var stop_signs_enabled := false
var auto_stop_time := 0.0
var one_way_enabled := false

var section_started := false
var drive_complete := false
var drive_time := 0.0
var wrong_turns := 0
var wrong_way_tickets := 0

var turn_intersections: Array[Vector2i] = []
var turn_positions: Dictionary = {}
var turn_roads: Array = []
var stop_sign_intersections: Array[Vector2i] = []
var entry_intersection := Vector2i.ZERO
var exit_intersection := Vector2i.ZERO
var current_intersection := Vector2i.ZERO
var target_intersection := Vector2i.ZERO
var camera_world_position := Vector2.ZERO
var shortest_route: Array[Vector2i] = []
var heading := Vector2i.UP
var view_rotation := 0.0
var target_view_rotation := 0.0
var is_driving := false
var auto_stop_remaining := 0.0
var current_segment_off_route := false
var current_segment_wrong_way := false

var lane_distance := 0.0
var lane_gate_distance := 0.0
var current_lane := 0
var target_lane := 0
var lane_visual_offset := 0.0
var lane_traffic: Array = []

var rng := RandomNumberGenerator.new()
var car_base_position := Vector2.ZERO

@onready var player_car: TextureRect = $"../PlayerCar"
@onready var left_button: Button = $"../TouchControls/LeftButton"
@onready var forward_button: Button = $"../TouchControls/ForwardButton"
@onready var right_button: Button = $"../TouchControls/RightButton"
@onready var map_label: Label = $"../MapLabel"
@onready var status_label: Label = $"../StatusLabel"


func _ready() -> void:
	rng.randomize()

	left_button.pressed.connect(_turn_left)
	forward_button.pressed.connect(_move_forward)
	right_button.pressed.connect(_turn_right)

	car_base_position = player_car.position
	player_car.pivot_offset = player_car.size * 0.5

	_load_stage(0, false)


func apply_drive_profile(profile: Dictionary) -> void:
	active_profile = profile
	steering_mode = str(profile.get("mode", "turn"))
	lane_count = int(profile.get("lane_count", 1))
	car_scale = float(profile.get("car_scale", 1.0))
	drive_speed = (
		DRIVE_PROFILES.BASE_SPEED
		* float(profile.get("speed_scale", 1.0))
	)
	lane_width = (
		DRIVE_PROFILES.BASE_LANE_WIDTH
		* float(profile.get("road_scale", 1.0))
	)
	road_width = lane_width * lane_count
	intersection_spacing = (
		DRIVE_PROFILES.BASE_BLOCK_SPACING
		* float(profile.get("block_scale", 1.0))
	)
	stop_signs_enabled = bool(profile.get("stop_signs", false))
	auto_stop_time = float(profile.get("auto_stop_time", 0.0))
	one_way_enabled = bool(profile.get("one_way", false))

	player_car.scale = Vector2.ONE * car_scale
	player_car.position = car_base_position
	map_label.text = str(profile.get("name", active_stage_id.to_upper()))


func _load_stage(index: int, auto_start: bool) -> void:
	if index >= DRIVE_PROFILES.ORDER.size():
		_finish_drive()
		return

	stage_index = index
	active_stage_id = DRIVE_PROFILES.ORDER[stage_index]
	apply_drive_profile(
		DRIVE_PROFILES.get_profile(active_stage_id)
	)

	section_started = false
	is_driving = false
	auto_stop_remaining = 0.0
	current_segment_off_route = false
	current_segment_wrong_way = false
	status_label.text = ""

	if steering_mode == "turn":
		_build_turn_stage()
	else:
		_build_lane_stage()

	if auto_start:
		_start_current_stage()
	else:
		status_label.text = "PRESS GO"

	queue_redraw()


func _advance_stage() -> void:
	_load_stage(stage_index + 1, true)


func _start_current_stage() -> void:
	if drive_complete or section_started:
		return

	section_started = true
	status_label.text = ""

	if steering_mode == "turn":
		var next_intersection := current_intersection + heading

		if _commit_turn_segment(next_intersection):
			is_driving = true
		else:
			status_label.text = "TURN"


func _build_turn_stage() -> void:
	turn_intersections.clear()
	turn_positions.clear()
	turn_roads.clear()
	stop_sign_intersections.clear()

	var grid_size: Vector2i = active_profile.get(
		"grid_size",
		Vector2i(4, 4)
	)

	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var point := Vector2i(x, y)
			turn_intersections.append(point)
			turn_positions[point] = Vector2(
				float(x) * intersection_spacing,
				float(y) * intersection_spacing
			)

			if x < grid_size.x - 1:
				_add_turn_road(point, point + Vector2i.RIGHT)

			if y < grid_size.y - 1:
				_add_turn_road(point, point + Vector2i.DOWN)

	entry_intersection = active_profile.get(
		"entry",
		Vector2i(0, grid_size.y - 1)
	)
	exit_intersection = active_profile.get(
		"exit",
		Vector2i(grid_size.x - 1, 0)
	)

	if one_way_enabled:
		_add_turn_one_ways()

	if stop_signs_enabled:
		for point in turn_intersections:
			if point != entry_intersection and point != exit_intersection:
				stop_sign_intersections.append(point)

	current_intersection = entry_intersection
	target_intersection = entry_intersection
	camera_world_position = _turn_world_position(entry_intersection)
	shortest_route = _find_turn_route(
		current_intersection,
		exit_intersection
	)

	if shortest_route.size() >= 2:
		heading = shortest_route[1] - shortest_route[0]
	else:
		heading = Vector2i.UP

	view_rotation = _rotation_for_heading(heading)
	target_view_rotation = view_rotation
	player_car.position = car_base_position


func _add_turn_road(
	from_intersection: Vector2i,
	to_intersection: Vector2i
) -> void:
	turn_roads.append({
		"from": from_intersection,
		"to": to_intersection,
		"one_way": false,
	})


func _add_turn_one_ways() -> void:
	var target_count := mini(
		7,
		int(turn_roads.size() / 3)
	)
	var added := 0
	var attempts := 0

	while added < target_count and attempts < 300:
		attempts += 1
		var index := rng.randi_range(0, turn_roads.size() - 1)
		var road: Dictionary = turn_roads[index]

		if bool(road.get("one_way", false)):
			continue

		var original_from: Vector2i = road["from"]
		var original_to: Vector2i = road["to"]

		if rng.randi_range(0, 1) == 1:
			road["from"] = original_to
			road["to"] = original_from

		road["one_way"] = true

		if not _all_turn_nodes_reach_exit():
			road["from"] = original_from
			road["to"] = original_to
			road["one_way"] = false
		else:
			added += 1


func _all_turn_nodes_reach_exit() -> bool:
	for point in turn_intersections:
		if _find_turn_route(point, exit_intersection).is_empty():
			return false

	return true


func _process(delta: float) -> void:
	if drive_complete:
		return

	drive_time += delta

	if steering_mode == "turn":
		_process_turn_mode(delta)
	else:
		_process_lane_mode(delta)

	queue_redraw()


func _process_turn_mode(delta: float) -> void:
	if not is_equal_approx(view_rotation, target_view_rotation):
		view_rotation = lerp_angle(
			view_rotation,
			target_view_rotation,
			minf(1.0, delta * 9.0)
		)

	if not section_started:
		return

	if auto_stop_remaining > 0.0:
		auto_stop_remaining = maxf(
			0.0,
			auto_stop_remaining - delta
		)

		if auto_stop_remaining <= 0.0:
			status_label.text = ""
			var next_intersection := current_intersection + heading

			if _commit_turn_segment(next_intersection):
				is_driving = true
			else:
				status_label.text = "TURN"

		return

	if not is_driving:
		return

	var target_position := _turn_world_position(target_intersection)

	camera_world_position = camera_world_position.move_toward(
		target_position,
		drive_speed * delta
	)

	if not camera_world_position.is_equal_approx(target_position):
		return

	camera_world_position = target_position
	current_intersection = target_intersection

	if current_intersection == exit_intersection:
		_advance_stage()
		return

	shortest_route = _find_turn_route(
		current_intersection,
		exit_intersection
	)

	if stop_signs_enabled:
		is_driving = false
		auto_stop_remaining = auto_stop_time
		status_label.text = "STOP"
		return

	var next_intersection := current_intersection + heading

	if not _commit_turn_segment(next_intersection):
		is_driving = false
		status_label.text = "TURN"


func _commit_turn_segment(next_intersection: Vector2i) -> bool:
	if not turn_intersections.has(next_intersection):
		return false

	var road = _get_turn_road_between(
		current_intersection,
		next_intersection
	)

	if road == null:
		return false

	current_segment_wrong_way = _turn_is_wrong_way(
		road,
		current_intersection,
		next_intersection
	)
	current_segment_off_route = false

	if shortest_route.size() >= 2:
		current_segment_off_route = (
			next_intersection != shortest_route[1]
		)

	if current_segment_wrong_way:
		current_segment_off_route = true
		wrong_way_tickets += 1

	if current_segment_off_route:
		wrong_turns += 1

	target_intersection = next_intersection
	shortest_route = _find_turn_route(
		target_intersection,
		exit_intersection
	)

	if current_segment_wrong_way:
		status_label.text = "WRONG WAY"
	elif current_segment_off_route:
		status_label.text = "REROUTING"
	else:
		status_label.text = ""

	return true


func _build_lane_stage() -> void:
	lane_distance = 0.0
	lane_gate_distance = float(
		active_profile.get("section_length", 6000.0)
	)
	current_lane = clampi(
		int(active_profile.get("start_lane", lane_count - 1)),
		0,
		lane_count - 1
	)
	target_lane = current_lane
	lane_visual_offset = _lane_center_offset(current_lane)
	player_car.position = (
		car_base_position
		+ Vector2(lane_visual_offset, 0.0)
	)

	view_rotation = 0.0
	target_view_rotation = 0.0
	_build_lane_traffic()


func _build_lane_traffic() -> void:
	lane_traffic.clear()

	var count := int(active_profile.get("traffic_count", 0))
	var section_length := float(
		active_profile.get("section_length", 6000.0)
	)

	for index in range(count):
		var lane := index % lane_count
		var distance := (
			900.0
			+ float(index) * section_length / float(maxi(1, count))
			+ rng.randf_range(-180.0, 180.0)
		)

		lane_traffic.append({
			"lane": lane,
			"distance": distance,
			"speed_factor": rng.randf_range(0.58, 0.80),
		})


func _process_lane_mode(delta: float) -> void:
	lane_visual_offset = move_toward(
		lane_visual_offset,
		_lane_center_offset(target_lane),
		delta * 420.0
	)

	player_car.position = (
		car_base_position
		+ Vector2(lane_visual_offset, 0.0)
	)

	if not section_started:
		return

	var effective_speed := drive_speed

	for index in range(lane_traffic.size()):
		var traffic: Dictionary = lane_traffic[index]
		var traffic_speed := (
			drive_speed
			* float(traffic.get("speed_factor", 0.70))
		)

		traffic["distance"] = (
			float(traffic.get("distance", 0.0))
			+ traffic_speed * delta
		)

		var gap := float(traffic["distance"]) - lane_distance

		if (
			int(traffic.get("lane", -1)) == current_lane
			and gap > 0.0
			and gap < 430.0
		):
			effective_speed = minf(
				effective_speed,
				traffic_speed
			)

		if float(traffic["distance"]) < lane_distance - 900.0:
			traffic["distance"] = (
				lane_distance
				+ rng.randf_range(1800.0, 3600.0)
			)
			traffic["lane"] = rng.randi_range(
				0,
				lane_count - 1
			)

		lane_traffic[index] = traffic

	lane_distance += effective_speed * delta

	if effective_speed < drive_speed * 0.92:
		status_label.text = "SLOW CAR"
	elif status_label.text == "SLOW CAR":
		status_label.text = ""

	if lane_distance < lane_gate_distance:
		return

	var exit_lane := int(active_profile.get("exit_lane", -1))

	if exit_lane < 0 or current_lane == exit_lane:
		_advance_stage()
		return

	wrong_turns += 1
	status_label.text = "MISSED EXIT"
	lane_gate_distance += float(
		active_profile.get("section_length", 6000.0)
	)


func _lane_center_offset(lane: int) -> float:
	return (
		(float(lane) - float(lane_count - 1) * 0.5)
		* lane_width
	)


func _move_forward() -> void:
	if drive_complete:
		return

	if not section_started:
		_start_current_stage()
		return

	if (
		steering_mode == "turn"
		and not is_driving
		and auto_stop_remaining <= 0.0
	):
		var next_intersection := current_intersection + heading

		if _commit_turn_segment(next_intersection):
			is_driving = true


func _turn_left() -> void:
	if drive_complete:
		return

	if steering_mode == "lane":
		target_lane = maxi(0, target_lane - 1)
		current_lane = target_lane
		return

	heading = Vector2i(heading.y, -heading.x)
	target_view_rotation += PI / 2.0


func _turn_right() -> void:
	if drive_complete:
		return

	if steering_mode == "lane":
		target_lane = mini(lane_count - 1, target_lane + 1)
		current_lane = target_lane
		return

	heading = Vector2i(-heading.y, heading.x)
	target_view_rotation -= PI / 2.0


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	if not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_A:
			_turn_left()
		KEY_D:
			_turn_right()
		KEY_W:
			_move_forward()


func _find_turn_route(
	start_node: Vector2i,
	end_node: Vector2i
) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start_node]
	var came_from: Dictionary = {}
	came_from[start_node] = start_node

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()

		if current == end_node:
			break

		for neighbor in _legal_turn_neighbors(current):
			if not came_from.has(neighbor):
				came_from[neighbor] = current
				queue.append(neighbor)

	var route: Array[Vector2i] = []

	if not came_from.has(end_node):
		return route

	var current := end_node

	while current != start_node:
		route.push_front(current)
		current = came_from[current]

	route.push_front(start_node)
	return route


func _legal_turn_neighbors(
	current: Vector2i
) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []

	for road in turn_roads:
		var a: Vector2i = road["from"]
		var b: Vector2i = road["to"]

		if bool(road.get("one_way", false)):
			if a == current:
				neighbors.append(b)
		else:
			if a == current:
				neighbors.append(b)
			elif b == current:
				neighbors.append(a)

	return neighbors


func _get_turn_road_between(
	a: Vector2i,
	b: Vector2i
):
	for road in turn_roads:
		var road_a: Vector2i = road["from"]
		var road_b: Vector2i = road["to"]

		if (
			(road_a == a and road_b == b)
			or (road_a == b and road_b == a)
		):
			return road

	return null


func _turn_is_wrong_way(
	road,
	travel_from: Vector2i,
	travel_to: Vector2i
) -> bool:
	if not bool(road.get("one_way", false)):
		return false

	return (
		travel_from != road["from"]
		or travel_to != road["to"]
	)


func _draw() -> void:
	if steering_mode == "turn":
		_draw_turn_scene()
	else:
		_draw_lane_scene()

	_draw_minimap()


func _draw_turn_scene() -> void:
	var ground_color := Color(0.66, 0.73, 0.57)

	if active_stage_id == "downtown":
		ground_color = Color(0.56, 0.57, 0.57)
	elif active_stage_id == "parking":
		ground_color = Color(0.25, 0.26, 0.26)

	draw_rect(Rect2(Vector2.ZERO, size), ground_color, true)

	if active_stage_id == "neighborhood":
		_draw_neighborhood_houses()
	elif active_stage_id == "downtown":
		_draw_downtown_blocks()
	elif active_stage_id == "parking":
		_draw_parking_lot_texture()

	for road in turn_roads:
		var a := _world_to_main(
			_turn_world_position(road["from"])
		)
		var b := _world_to_main(
			_turn_world_position(road["to"])
		)

		draw_line(
			a,
			b,
			Color(0.20, 0.21, 0.21),
			road_width,
			true
		)

		if bool(road.get("one_way", false)):
			_draw_one_way_arrow(a, b)

	if stop_signs_enabled:
		for point in stop_sign_intersections:
			_draw_stop_sign(point)

	if active_stage_id == "parking":
		_draw_parking_destination()


func _draw_neighborhood_houses() -> void:
	for road in turn_roads:
		var a := _turn_world_position(road["from"])
		var b := _turn_world_position(road["to"])
		var midpoint := a.lerp(b, 0.5)

		if midpoint.distance_to(camera_world_position) > 3200.0:
			continue

		var direction := (b - a).normalized()
		var side := Vector2(-direction.y, direction.x)
		var length := a.distance_to(b)
		var house_count := maxi(1, int(length / 175.0))

		for index in range(1, house_count):
			var t := float(index) / float(house_count)
			var road_point := a.lerp(b, t)

			for side_sign in [-1.0, 1.0]:
				var center: Vector2 = (
					road_point
					+ side * float(side_sign) * (road_width * 0.5 + 88.0)
				)

				_draw_world_box(
					center,
					Vector2(105.0, 72.0),
					Color(0.65, 0.49, 0.37)
				)


func _draw_downtown_blocks() -> void:
	var grid_size: Vector2i = active_profile.get(
		"grid_size",
		Vector2i(4, 4)
	)

	for y in range(grid_size.y - 1):
		for x in range(grid_size.x - 1):
			var top_left := _turn_world_position(Vector2i(x, y))
			var center := (
				top_left
				+ Vector2.ONE * intersection_spacing * 0.5
			)

			_draw_world_box(
				center,
				Vector2.ONE * intersection_spacing * 0.70,
				Color(0.36, 0.38, 0.40)
			)

			_draw_world_box(
				center + Vector2(
					intersection_spacing * 0.16,
					-intersection_spacing * 0.12
				),
				Vector2.ONE * intersection_spacing * 0.20,
				Color(0.46, 0.48, 0.49)
			)


func _draw_parking_lot_texture() -> void:
	var grid_size: Vector2i = active_profile.get(
		"grid_size",
		Vector2i(3, 3)
	)

	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var point := _turn_world_position(Vector2i(x, y))
			var screen_point := _world_to_main(point)

			draw_rect(
				Rect2(
					screen_point - Vector2(35.0, 55.0),
					Vector2(70.0, 110.0)
				),
				Color(0.66, 0.66, 0.60),
				false,
				2.0
			)


func _draw_parking_destination() -> void:
	var destination := _world_to_main(
		_turn_world_position(exit_intersection)
	)

	draw_rect(
		Rect2(
			destination - Vector2(31.0, 48.0),
			Vector2(62.0, 96.0)
		),
		Color(0.18, 0.42, 0.92),
		false,
		5.0
	)


func _draw_stop_sign(intersection: Vector2i) -> void:
	var world_position := (
		_turn_world_position(intersection)
		+ Vector2(road_width * 0.80, road_width * 0.80)
	)
	var center := _world_to_main(world_position)
	var radius := 11.0
	var points := PackedVector2Array()

	for index in range(8):
		var angle := PI / 8.0 + TAU * float(index) / 8.0
		points.append(
			center + Vector2(cos(angle), sin(angle)) * radius
		)

	draw_colored_polygon(points, Color(0.82, 0.07, 0.06))

	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color.WHITE, 1.5, true)


func _draw_one_way_arrow(
	road_start: Vector2,
	road_end: Vector2
) -> void:
	var direction := (road_end - road_start).normalized()
	var side := Vector2(-direction.y, direction.x)
	var midpoint := road_start.lerp(road_end, 0.5)
	var tip := midpoint + direction * 10.0

	draw_colored_polygon(
		PackedVector2Array([
			tip,
			midpoint - direction * 8.0 + side * 6.0,
			midpoint - direction * 8.0 - side * 6.0,
		]),
		Color(0.90, 0.90, 0.86)
	)


func _draw_lane_scene() -> void:
	var ground_color := Color(0.52, 0.63, 0.45)

	if active_stage_id == "highway":
		ground_color = Color(0.46, 0.57, 0.40)

	draw_rect(Rect2(Vector2.ZERO, size), ground_color, true)

	var road_left := size.x * 0.5 - road_width * 0.5

	draw_rect(
		Rect2(
			Vector2(road_left, -40.0),
			Vector2(road_width, size.y + 80.0)
		),
		Color(0.19, 0.20, 0.20),
		true
	)

	_draw_lane_scenery()

	if active_stage_id == "highway":
		_draw_highway_exit()

	_draw_lane_traffic()


func _draw_lane_scenery() -> void:
	var visual_scroll := fmod(lane_distance * 0.36, 230.0)
	var marker_count := int(size.y / 230.0) + 4
	var road_left := size.x * 0.5 - road_width * 0.5
	var road_right := size.x * 0.5 + road_width * 0.5

	for index in range(marker_count):
		var y := (
			float(index) * 230.0
			- visual_scroll
			- 100.0
		)

		if active_stage_id == "main_road":
			draw_rect(
				Rect2(
					Vector2(road_left - 78.0, y),
					Vector2(52.0, 74.0)
				),
				Color(0.52, 0.44, 0.35),
				true
			)
			draw_rect(
				Rect2(
					Vector2(road_right + 26.0, y + 70.0),
					Vector2(58.0, 64.0)
				),
				Color(0.47, 0.49, 0.44),
				true
			)
		else:
			draw_rect(
				Rect2(
					Vector2(road_left - 28.0, y),
					Vector2(10.0, 88.0)
				),
				Color(0.70, 0.70, 0.66),
				true
			)
			draw_rect(
				Rect2(
					Vector2(road_right + 18.0, y),
					Vector2(10.0, 88.0)
				),
				Color(0.70, 0.70, 0.66),
				true
			)


func _draw_highway_exit() -> void:
	var remaining := lane_gate_distance - lane_distance

	if remaining < 0.0 or remaining > 1500.0:
		return

	var branch_y := (
		player_car.position.y
		+ player_car.size.y * 0.5
		- remaining * 0.36
	)

	if branch_y < -120.0 or branch_y > size.y + 120.0:
		return

	var road_right := size.x * 0.5 + road_width * 0.5

	draw_colored_polygon(
		PackedVector2Array([
			Vector2(road_right - 8.0, branch_y - 42.0),
			Vector2(size.x + 30.0, branch_y - 95.0),
			Vector2(size.x + 30.0, branch_y + 95.0),
			Vector2(road_right - 8.0, branch_y + 42.0),
		]),
		Color(0.19, 0.20, 0.20)
	)


func _draw_lane_traffic() -> void:
	var player_center_y := (
		player_car.position.y
		+ player_car.size.y * 0.5
	)
	var traffic_width := lane_width * 0.58
	var traffic_height := traffic_width * 1.55

	for traffic in lane_traffic:
		var gap := float(traffic.get("distance", 0.0)) - lane_distance
		var y := player_center_y - gap * 0.36

		if y < -120.0 or y > size.y + 120.0:
			continue

		var x := (
			size.x * 0.5
			+ _lane_center_offset(int(traffic.get("lane", 0)))
		)

		draw_rect(
			Rect2(
				Vector2(
					x - traffic_width * 0.5,
					y - traffic_height * 0.5
				),
				Vector2(traffic_width, traffic_height)
			),
			Color(0.32, 0.35, 0.38),
			true
		)


func _draw_minimap() -> void:
	var map_rect := _minimap_rect()

	draw_rect(
		map_rect,
		Color(0.75, 0.80, 0.66, 0.96),
		true
	)

	if steering_mode == "turn":
		_draw_turn_minimap(map_rect)
	else:
		_draw_lane_minimap(map_rect)

	draw_rect(
		map_rect,
		Color(0.86, 0.86, 0.82),
		false,
		2.0
	)


func _draw_turn_minimap(map_rect: Rect2) -> void:
	if active_stage_id == "downtown":
		draw_rect(
			map_rect.grow(-5.0),
			Color(0.57, 0.58, 0.58),
			true
		)
	elif active_stage_id == "parking":
		draw_rect(
			map_rect.grow(-5.0),
			Color(0.33, 0.34, 0.34),
			true
		)
	else:
		draw_circle(
			map_rect.position + Vector2(35.0, 36.0),
			17.0,
			Color(0.39, 0.63, 0.72)
		)

	for road in turn_roads:
		draw_line(
			_turn_to_minimap(
				_turn_world_position(road["from"]),
				map_rect
			),
			_turn_to_minimap(
				_turn_world_position(road["to"]),
				map_rect
			),
			Color(0.30, 0.31, 0.30),
			2.0,
			true
		)

	if is_driving:
		draw_line(
			_turn_to_minimap(camera_world_position, map_rect),
			_turn_to_minimap(
				_turn_world_position(target_intersection),
				map_rect
			),
			Color(0.98, 0.78, 0.06),
			3.0,
			true
		)

	for index in range(shortest_route.size() - 1):
		draw_line(
			_turn_to_minimap(
				_turn_world_position(shortest_route[index]),
				map_rect
			),
			_turn_to_minimap(
				_turn_world_position(shortest_route[index + 1]),
				map_rect
			),
			Color(0.98, 0.78, 0.06),
			2.5,
			true
		)

	draw_circle(
		_turn_to_minimap(camera_world_position, map_rect),
		4.0,
		Color(0.14, 0.86, 0.43)
	)

	draw_circle(
		_turn_to_minimap(
			_turn_world_position(exit_intersection),
			map_rect
		),
		4.5,
		Color(0.15, 0.42, 0.95)
	)


func _draw_lane_minimap(map_rect: Rect2) -> void:
	var center_x := map_rect.position.x + map_rect.size.x * 0.5
	var road_half_width := 15.0
	var top_y := map_rect.position.y + 10.0
	var bottom_y := map_rect.end.y - 10.0

	draw_rect(
		Rect2(
			Vector2(center_x - road_half_width, top_y),
			Vector2(road_half_width * 2.0, bottom_y - top_y)
		),
		Color(0.28, 0.29, 0.29),
		true
	)

	var section_length := float(
		active_profile.get("section_length", 6000.0)
	)
	var section_start := lane_gate_distance - section_length
	var progress := clampf(
		(lane_distance - section_start) / section_length,
		0.0,
		1.0
	)
	var player_y := lerpf(bottom_y, top_y, progress)
	var route_end := Vector2(center_x, top_y)

	if int(active_profile.get("exit_lane", -1)) >= 0:
		route_end = Vector2(
			map_rect.end.x - 10.0,
			top_y + 7.0
		)

		draw_line(
			Vector2(center_x, top_y + 15.0),
			route_end,
			Color(0.98, 0.78, 0.06),
			2.5,
			true
		)

	draw_line(
		Vector2(center_x, player_y),
		Vector2(center_x, top_y + 15.0),
		Color(0.98, 0.78, 0.06),
		2.5,
		true
	)

	draw_circle(
		Vector2(center_x, player_y),
		4.0,
		Color(0.14, 0.86, 0.43)
	)

	draw_circle(
		route_end,
		4.5,
		Color(0.15, 0.42, 0.95)
	)


func _turn_world_position(
	intersection: Vector2i
) -> Vector2:
	return turn_positions.get(intersection, Vector2(intersection))


func _world_to_main(world_point: Vector2) -> Vector2:
	var world_offset := world_point - camera_world_position
	var rotated_offset := world_offset.rotated(view_rotation)

	return size * 0.5 + rotated_offset


func _draw_world_box(
	center: Vector2,
	box_size: Vector2,
	color: Color
) -> void:
	var half := box_size * 0.5
	var corners := PackedVector2Array([
		_world_to_main(center + Vector2(-half.x, -half.y)),
		_world_to_main(center + Vector2(half.x, -half.y)),
		_world_to_main(center + Vector2(half.x, half.y)),
		_world_to_main(center + Vector2(-half.x, half.y)),
	])

	draw_colored_polygon(corners, color)


func _turn_to_minimap(
	world_point: Vector2,
	map_rect: Rect2
) -> Vector2:
	var grid_size: Vector2i = active_profile.get(
		"grid_size",
		Vector2i(4, 4)
	)
	var world_size := Vector2(
		float(maxi(1, grid_size.x - 1)) * intersection_spacing,
		float(maxi(1, grid_size.y - 1)) * intersection_spacing
	)
	var padding := 9.0
	var usable := map_rect.size - Vector2.ONE * padding * 2.0
	var scale := minf(
		usable.x / maxf(world_size.x, 1.0),
		usable.y / maxf(world_size.y, 1.0)
	)
	var drawn_size := world_size * scale
	var origin := (
		map_rect.position
		+ (map_rect.size - drawn_size) * 0.5
	)

	return origin + world_point * scale


func _minimap_rect() -> Rect2:
	return Rect2(
		Vector2(size.x - minimap_size - 10.0, 10.0),
		Vector2(minimap_size, minimap_size)
	)


func _rotation_for_heading(direction: Vector2i) -> float:
	if direction == Vector2i.RIGHT:
		return -PI / 2.0

	if direction == Vector2i.DOWN:
		return PI

	if direction == Vector2i.LEFT:
		return PI / 2.0

	return 0.0


func _finish_drive() -> void:
	drive_complete = true
	is_driving = false
	section_started = false

	left_button.disabled = true
	forward_button.disabled = true
	right_button.disabled = true

	map_label.text = "PARKED"
	status_label.text = "%.1f SEC  •  %d WRONG TURNS" % [
		drive_time,
		wrong_turns,
	]
