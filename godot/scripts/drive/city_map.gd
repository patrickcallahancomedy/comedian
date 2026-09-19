extends Control

const WORLD_CONFIG = preload("res://scripts/drive/drive_world_config.gd")

const WORLD_SIZE: int = WORLD_CONFIG.WORLD_SIZE
const MAP_SIZE: Vector2 = WORLD_CONFIG.MAP_SIZE
const NEIGHBORHOOD_ROADS_TO_REMOVE := 8
const CITY_ONE_WAY_COUNT := 12
const DRIVE_SPEED := 1.05
const HIGHWAY_SPEED := 1.65

@export var block_size: float = 110.0
@export var road_width: float = 56.0
@export var minimap_size: float = 142.0

var world_size: int = WORLD_SIZE
var minimap_world_size: Vector2 = MAP_SIZE
var intersections: Array[Vector2i] = []
var intersection_positions: Dictionary = {}
var roads: Array = []
var rng := RandomNumberGenerator.new()

var region_ids: Array[String] = WORLD_CONFIG.get_region_ids()

var parking_slots: Array[Vector2i] = []
var open_parking_slots: Array[Vector2i] = []
var blocked_parking_slots: Array[Vector2i] = []

var start_intersection: Vector2i = WORLD_CONFIG.START
var destination_intersection := Vector2i.ZERO
var shortest_route: Array[Vector2i] = []

var current_intersection: Vector2i = WORLD_CONFIG.START
var target_intersection: Vector2i = WORLD_CONFIG.START
var camera_world_position := Vector2.ZERO
var is_driving: bool = false
var drive_complete: bool = false

var heading := Vector2i.UP
var view_rotation: float = 0.0
var target_view_rotation: float = 0.0

var wrong_turns: int = 0
var wrong_way_tickets: int = 0
var drive_time: float = 0.0

var current_segment_off_route: bool = false
var current_segment_wrong_way: bool = false

var stop_sign_intersections: Array[Vector2i] = []

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

	_build_world()
	_reset_drive_position()

	print("DRIVE intersections: ", intersections.size())
	print("DRIVE roads: ", roads.size())
	print("Whole trip route found: ", not shortest_route.is_empty())


func _build_world() -> void:
	intersections.clear()
	intersection_positions.clear()
	roads.clear()
	parking_slots.clear()
	open_parking_slots.clear()
	blocked_parking_slots.clear()

	_build_neighborhood()
	_build_highway()
	_build_city()
	_build_parking_lot()
	_build_region_connectors()

	_collect_intersections_from_roads()
	_add_city_one_ways(CITY_ONE_WAY_COUNT)
	_collect_intersections_from_roads()
	_assign_intersection_positions()
	_build_stop_signs()


func _build_neighborhood() -> void:
	var region := WORLD_CONFIG.get_region("neighborhood")
	var origin: Vector2i = region["origin"]
	var region_size: Vector2i = region["size"]

	_add_region_grid(
		"neighborhood",
		origin,
		region_size,
		"neighborhood",
		25
	)

	_remove_region_roads(
		"neighborhood",
		NEIGHBORHOOD_ROADS_TO_REMOVE,
		_region_nodes(origin, region_size)
	)


func _build_highway() -> void:
	_add_road(Vector2i(5, 12), Vector2i(5, 11), "ramp", 40, "highway")
	_add_road(Vector2i(5, 11), Vector2i(5, 10), "ramp", 40, "highway")

	_add_road(Vector2i(5, 10), Vector2i(6, 10), "highway", 65, "highway")
	_add_road(Vector2i(6, 10), Vector2i(7, 10), "highway", 65, "highway")
	_add_road(Vector2i(7, 10), Vector2i(8, 10), "highway", 65, "highway")
	_add_road(Vector2i(8, 10), Vector2i(9, 10), "highway", 65, "highway")


func _build_city() -> void:
	var region := WORLD_CONFIG.get_region("city")

	_add_region_grid(
		"city",
		region["origin"],
		region["size"],
		"city",
		30
	)


func _build_parking_lot() -> void:
	_add_road(Vector2i(15, 4), Vector2i(16, 4), "parking", 10, "parking")
	_add_road(Vector2i(16, 4), Vector2i(17, 4), "parking", 10, "parking")

	_add_road(Vector2i(17, 4), Vector2i(17, 5), "parking", 10, "parking")
	_add_road(Vector2i(17, 5), Vector2i(17, 6), "parking", 10, "parking")
	_add_road(Vector2i(17, 6), Vector2i(17, 7), "parking", 10, "parking")
	_add_road(Vector2i(17, 7), Vector2i(17, 8), "parking", 10, "parking")

	_add_road(Vector2i(15, 5), Vector2i(16, 5), "parking", 10, "parking")
	_add_road(Vector2i(16, 5), Vector2i(17, 5), "parking", 10, "parking")
	_add_road(Vector2i(17, 5), Vector2i(18, 5), "parking", 10, "parking")
	_add_road(Vector2i(18, 5), Vector2i(19, 5), "parking", 10, "parking")

	_add_road(Vector2i(15, 7), Vector2i(16, 7), "parking", 10, "parking")
	_add_road(Vector2i(16, 7), Vector2i(17, 7), "parking", 10, "parking")
	_add_road(Vector2i(17, 7), Vector2i(18, 7), "parking", 10, "parking")
	_add_road(Vector2i(18, 7), Vector2i(19, 7), "parking", 10, "parking")

	parking_slots = [
		Vector2i(15, 5),
		Vector2i(19, 5),
		Vector2i(15, 7),
		Vector2i(19, 7),
	]

	var first_open_index := rng.randi_range(0, parking_slots.size() - 1)
	var second_open_index := first_open_index

	while second_open_index == first_open_index:
		second_open_index = rng.randi_range(0, parking_slots.size() - 1)

	open_parking_slots = [
		parking_slots[first_open_index],
		parking_slots[second_open_index],
	]

	destination_intersection = open_parking_slots[0]

	for slot in parking_slots:
		if open_parking_slots.has(slot):
			continue

		blocked_parking_slots.append(slot)

		var aisle_neighbor := Vector2i(16, slot.y)

		if slot.x == 19:
			aisle_neighbor = Vector2i(18, slot.y)

		var blocked_road = _get_road_between(slot, aisle_neighbor)

		if blocked_road != null:
			blocked_road["blocked"] = true


func _build_region_connectors() -> void:
	_add_road(Vector2i(4, 12), Vector2i(5, 12), "ramp", 35, "highway")

	_add_road(Vector2i(9, 10), Vector2i(10, 10), "arterial", 40, "city")
	_add_road(Vector2i(10, 10), Vector2i(10, 9), "arterial", 40, "city")
	_add_road(Vector2i(10, 9), Vector2i(10, 8), "arterial", 40, "city")

	_add_road(Vector2i(14, 4), Vector2i(15, 4), "parking", 10, "parking")


func _add_region_grid(
	region_id: String,
	origin: Vector2i,
	region_size: Vector2i,
	road_type: String,
	speed_limit: int
) -> void:
	for local_y in range(region_size.y):
		for local_x in range(region_size.x):
			var point := origin + Vector2i(local_x, local_y)

			if local_x < region_size.x - 1:
				_add_road(
					point,
					point + Vector2i.RIGHT,
					road_type,
					speed_limit,
					region_id
				)

			if local_y < region_size.y - 1:
				_add_road(
					point,
					point + Vector2i.DOWN,
					road_type,
					speed_limit,
					region_id
				)


func _add_road(
	from_intersection: Vector2i,
	to_intersection: Vector2i,
	road_type: String,
	speed_limit: int,
	region_id: String,
	one_way: bool = false,
	blocked: bool = false
) -> void:
	roads.append({
		"from": from_intersection,
		"to": to_intersection,
		"road_type": road_type,
		"speed_limit": speed_limit,
		"region": region_id,
		"one_way": one_way,
		"blocked": blocked,
	})


func _region_nodes(
	origin: Vector2i,
	region_size: Vector2i
) -> Array[Vector2i]:
	var nodes: Array[Vector2i] = []

	for y in range(region_size.y):
		for x in range(region_size.x):
			nodes.append(origin + Vector2i(x, y))

	return nodes


func _remove_region_roads(
	region_id: String,
	target_count: int,
	region_nodes: Array[Vector2i]
) -> void:
	var removed_count := 0
	var attempts := 0

	while removed_count < target_count and attempts < 3000:
		attempts += 1

		var candidate_indices: Array[int] = []

		for index in range(roads.size()):
			if str(roads[index].get("region", "")) == region_id:
				candidate_indices.append(index)

		if candidate_indices.is_empty():
			break

		var road_index := candidate_indices[
			rng.randi_range(0, candidate_indices.size() - 1)
		]
		var removed_road = roads[road_index]

		roads.remove_at(road_index)

		if _region_is_connected(region_id, region_nodes):
			removed_count += 1
		else:
			roads.insert(road_index, removed_road)


func _region_is_connected(
	region_id: String,
	region_nodes: Array[Vector2i]
) -> bool:
	if region_nodes.is_empty():
		return true

	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [region_nodes[0]]
	visited[region_nodes[0]] = true

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()

		for road in roads:
			if str(road.get("region", "")) != region_id:
				continue

			var a: Vector2i = _road_start(road)
			var b: Vector2i = _road_end(road)
			var neighbor := Vector2i.ZERO
			var found_neighbor := false

			if a == current:
				neighbor = b
				found_neighbor = true
			elif b == current:
				neighbor = a
				found_neighbor = true

			if (
				found_neighbor
				and region_nodes.has(neighbor)
				and not visited.has(neighbor)
			):
				visited[neighbor] = true
				queue.append(neighbor)

	return visited.size() == region_nodes.size()


func _collect_intersections_from_roads() -> void:
	intersections.clear()
	var seen: Dictionary = {}

	for road in roads:
		seen[_road_start(road)] = true
		seen[_road_end(road)] = true

	for intersection in seen.keys():
		intersections.append(intersection)


func _assign_intersection_positions() -> void:
	intersection_positions.clear()

	for intersection in intersections:
		var assigned := false

		for region_id in region_ids:
			var region := WORLD_CONFIG.get_region(region_id)

			if _point_is_in_region(intersection, region):
				var origin: Vector2i = region["origin"]
				var physical_origin: Vector2 = region["physical_origin"]
				var spacing: float = region["spacing"]
				var local := Vector2(intersection - origin)

				intersection_positions[intersection] = (
					physical_origin + local * spacing
				)
				assigned = true
				break

		if assigned:
			continue

		if intersection == Vector2i(10, 10):
			intersection_positions[intersection] = Vector2(31.4, 14.2)
		elif intersection == Vector2i(10, 9):
			intersection_positions[intersection] = Vector2(31.4, 13.2)
		else:
			intersection_positions[intersection] = Vector2(intersection)


func _point_is_in_region(
	point: Vector2i,
	region: Dictionary
) -> bool:
	var origin: Vector2i = region["origin"]
	var region_size: Vector2i = region["size"]

	return (
		point.x >= origin.x
		and point.y >= origin.y
		and point.x < origin.x + region_size.x
		and point.y < origin.y + region_size.y
	)


func _intersection_world_position(intersection: Vector2i) -> Vector2:
	return intersection_positions.get(
		intersection,
		Vector2(intersection)
	)


func _add_city_one_ways(target_count: int) -> void:
	var added := 0
	var attempts := 0

	while added < target_count and attempts < 500:
		attempts += 1

		var city_indices: Array[int] = []

		for index in range(roads.size()):
			var road = roads[index]

			if (
				str(road.get("region", "")) == "city"
				and str(road.get("road_type", "")) == "city"
				and not bool(road.get("one_way", false))
			):
				city_indices.append(index)

		if city_indices.is_empty():
			break

		var road_index := city_indices[
			rng.randi_range(0, city_indices.size() - 1)
		]
		var road: Dictionary = roads[road_index]

		var original_from: Vector2i = _road_start(road)
		var original_to: Vector2i = _road_end(road)

		if rng.randi_range(0, 1) == 1:
			road["from"] = original_to
			road["to"] = original_from

		road["one_way"] = true

		if _find_shortest_route(
			start_intersection,
			destination_intersection
		).is_empty():
			road["from"] = original_from
			road["to"] = original_to
			road["one_way"] = false
		else:
			added += 1


func _reset_drive_position() -> void:
	current_intersection = start_intersection
	target_intersection = start_intersection
	camera_world_position = _intersection_world_position(start_intersection)

	is_driving = false
	drive_complete = false
	wrong_turns = 0
	wrong_way_tickets = 0
	drive_time = 0.0
	current_segment_off_route = false
	current_segment_wrong_way = false

	shortest_route = _find_shortest_route(
		current_intersection,
		destination_intersection
	)

	if shortest_route.size() >= 2:
		heading = shortest_route[1] - shortest_route[0]
	else:
		heading = Vector2i.UP

	view_rotation = _rotation_for_heading(heading)
	target_view_rotation = view_rotation

	_update_region_label("neighborhood")
	status_label.text = "PRESS GO"

	forward_button.disabled = false
	left_button.disabled = false
	right_button.disabled = false

	queue_redraw()


func _process(delta: float) -> void:
	if not is_equal_approx(view_rotation, target_view_rotation):
		view_rotation = lerp_angle(
			view_rotation,
			target_view_rotation,
			minf(1.0, delta * 10.0)
		)

	if is_driving:
		drive_time += delta

		var target_position := _intersection_world_position(
			target_intersection
		)

		var current_road = _get_road_between(
			current_intersection,
			target_intersection
		)

		camera_world_position = camera_world_position.move_toward(
			target_position,
			_drive_speed_for_road(current_road) * delta
		)

		if camera_world_position.is_equal_approx(target_position):
			camera_world_position = target_position
			current_intersection = target_intersection

			if open_parking_slots.has(current_intersection):
				_finish_drive()
				queue_redraw()
				return

			shortest_route = _find_shortest_route(
				current_intersection,
				destination_intersection
			)

			var next_intersection := current_intersection + heading

			if not _commit_to_segment(next_intersection):
				is_driving = false
				current_segment_off_route = false
				current_segment_wrong_way = false
				status_label.text = "NO ROAD - TURN AND GO"

	queue_redraw()


func _commit_to_segment(next_intersection: Vector2i) -> bool:
	if not intersections.has(next_intersection):
		return false

	var road = _get_road_between(current_intersection, next_intersection)

	if road == null:
		return false

	if bool(road.get("blocked", false)):
		status_label.text = "BLOCKED SPACE"
		return false

	current_segment_wrong_way = _is_wrong_way(
		road,
		current_intersection,
		next_intersection
	)

	current_segment_off_route = false

	if shortest_route.size() >= 2:
		current_segment_off_route = next_intersection != shortest_route[1]

	if current_segment_wrong_way:
		current_segment_off_route = true
		wrong_way_tickets += 1

	if current_segment_off_route:
		wrong_turns += 1

	target_intersection = next_intersection

	shortest_route = _find_shortest_route(
		target_intersection,
		destination_intersection
	)

	_update_region_label(str(road.get("region", "neighborhood")))
	_update_status_label()

	return true


func _finish_drive() -> void:
	is_driving = false
	drive_complete = true
	current_segment_off_route = false
	current_segment_wrong_way = false

	forward_button.disabled = true
	left_button.disabled = true
	right_button.disabled = true

	map_label.text = "PARKED"
	status_label.text = "%.1f SEC  •  %d WRONG TURNS" % [
		drive_time,
		wrong_turns,
	]


func _move_forward() -> void:
	if drive_complete or is_driving:
		return

	var next_intersection := current_intersection + heading

	if _commit_to_segment(next_intersection):
		is_driving = true


func _turn_left() -> void:
	if drive_complete:
		return

	heading = Vector2i(heading.y, -heading.x)
	target_view_rotation += PI / 2.0


func _turn_right() -> void:
	if drive_complete:
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


func _find_shortest_route(
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

		for neighbor in _legal_neighbors_from(current):
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


func _legal_neighbors_from(current: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []

	for road in roads:
		if bool(road.get("blocked", false)):
			continue

		var a: Vector2i = _road_start(road)
		var b: Vector2i = _road_end(road)

		if bool(road.get("one_way", false)):
			if a == current:
				neighbors.append(b)
		else:
			if a == current:
				neighbors.append(b)
			elif b == current:
				neighbors.append(a)

	return neighbors


func _draw() -> void:
	_draw_main_ground()
	_draw_region_surfaces()
	_draw_world_roads()
	_draw_stop_signs()
	_draw_parking_spaces()
	_draw_minimap()


func _draw_main_ground() -> void:
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color(0.67, 0.72, 0.58)
	)


func _draw_region_surfaces() -> void:
	for region_id in ["neighborhood", "city", "parking"]:
		var region := WORLD_CONFIG.get_region(region_id)
		var origin: Vector2i = region["origin"]
		var region_size: Vector2i = region["size"]

		for y in range(region_size.y - 1):
			for x in range(region_size.x - 1):
				var cell := origin + Vector2i(x, y)
				var top_left := _intersection_world_position(cell)
				var bottom_right := _intersection_world_position(
					cell + Vector2i.ONE
				)

				_draw_region_cell(
					region_id,
					Rect2(top_left, bottom_right - top_left)
				)


func _draw_region_cell(
	region_id: String,
	world_rect: Rect2
) -> void:
	var fill_color := Color(0.68, 0.74, 0.60)

	if region_id == "city":
		fill_color = Color(0.58, 0.59, 0.58)
	elif region_id == "parking":
		fill_color = Color(0.25, 0.26, 0.26)

	_draw_world_rect(world_rect, fill_color)

	var p := world_rect.position
	var s := world_rect.size

	if region_id == "neighborhood":
		_draw_world_rect(
			Rect2(
				p + Vector2(s.x * 0.22, s.y * 0.20),
				Vector2(s.x * 0.52, s.y * 0.36)
			),
			Color(0.66, 0.50, 0.38)
		)

		_draw_world_rect(
			Rect2(
				p + Vector2(s.x * 0.45, s.y * 0.56),
				Vector2(s.x * 0.10, s.y * 0.34)
			),
			Color(0.55, 0.55, 0.51)
		)

	elif region_id == "city":
		_draw_world_rect(
			Rect2(
				p + Vector2(s.x * 0.14, s.y * 0.14),
				Vector2(s.x * 0.72, s.y * 0.72)
			),
			Color(0.38, 0.40, 0.42)
		)

	elif region_id == "parking":
		for line_index in range(1, 4):
			var line_x := float(line_index) * 0.25

			_draw_world_line(
				p + Vector2(s.x * line_x, s.y * 0.12),
				p + Vector2(s.x * line_x, s.y * 0.88),
				Color(0.55, 0.55, 0.50),
				1.5
			)


func _draw_world_roads() -> void:
	for road in roads:
		var road_start := _world_to_main(
			_intersection_world_position(_road_start(road))
		)
		var road_end := _world_to_main(
			_intersection_world_position(_road_end(road))
		)
		var road_type := str(road.get("road_type", "neighborhood"))

		draw_line(
			road_start,
			road_end,
			Color(0.20, 0.21, 0.21),
			road_width,
			true
		)

		if bool(road.get("one_way", false)):
			_draw_one_way_arrow(road_start, road_end)

		if bool(road.get("blocked", false)):
			_draw_blocked_gate(road_start, road_end)



func _build_stop_signs() -> void:
	stop_sign_intersections.clear()

	var region := WORLD_CONFIG.get_region("neighborhood")
	var origin: Vector2i = region["origin"]
	var region_size: Vector2i = region["size"]

	for point in _region_nodes(origin, region_size):
		if point == start_intersection:
			continue

		if _intersection_degree(point) >= 3:
			stop_sign_intersections.append(point)


func _intersection_degree(point: Vector2i) -> int:
	var degree := 0

	for road in roads:
		if _road_start(road) == point or _road_end(road) == point:
			degree += 1

	return degree


func _draw_stop_signs() -> void:
	for intersection in stop_sign_intersections:
		_draw_stop_sign(intersection)


func _draw_stop_sign(intersection: Vector2i) -> void:
	var world_position := _intersection_world_position(intersection)
	var center := _world_to_main(
		world_position + Vector2(0.22, 0.22)
	)
	var radius := 7.0
	var points := PackedVector2Array()

	for index in range(8):
		var angle := PI / 8.0 + TAU * float(index) / 8.0
		points.append(
			center + Vector2(cos(angle), sin(angle)) * radius
		)

	draw_colored_polygon(points, Color(0.80, 0.08, 0.07))

	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color.WHITE, 1.5, true)


func _drive_speed_for_road(road) -> float:
	if road != null and str(road.get("road_type", "")) == "highway":
		return HIGHWAY_SPEED

	return DRIVE_SPEED


func _draw_one_way_arrow(
	road_start: Vector2,
	road_end: Vector2
) -> void:
	var direction := (road_end - road_start).normalized()
	var side := Vector2(-direction.y, direction.x)
	var midpoint := road_start.lerp(road_end, 0.5)
	var tip := midpoint + direction * 9.0

	draw_colored_polygon(
		PackedVector2Array([
			tip,
			midpoint - direction * 7.0 + side * 6.0,
			midpoint - direction * 7.0 - side * 6.0,
		]),
		Color(0.92, 0.92, 0.88)
	)


func _draw_blocked_gate(
	road_start: Vector2,
	road_end: Vector2
) -> void:
	var direction := (road_end - road_start).normalized()
	var side := Vector2(-direction.y, direction.x)
	var gate_center := road_start.lerp(road_end, 0.22)

	draw_line(
		gate_center - side * 18.0,
		gate_center + side * 18.0,
		Color(0.78, 0.10, 0.08),
		5.0,
		true
	)


func _draw_parking_spaces() -> void:
	for slot in parking_slots:
		var slot_point := _world_to_main(
			_intersection_world_position(slot)
		)
		var slot_color := Color(0.74, 0.74, 0.68)

		if blocked_parking_slots.has(slot):
			slot_color = Color(0.58, 0.18, 0.16)
		elif slot == destination_intersection:
			slot_color = Color(0.15, 0.42, 0.90)
		elif open_parking_slots.has(slot):
			slot_color = Color(0.22, 0.60, 0.30)

		draw_rect(
			Rect2(
				slot_point - Vector2(18, 28),
				Vector2(36, 56)
			),
			slot_color,
			false,
			4.0
		)


func _draw_minimap() -> void:
	var map_rect := _minimap_rect()

	draw_rect(
		map_rect,
		Color(0.76, 0.80, 0.66, 0.96),
		true
	)

	_draw_minimap_geography()

	for road in roads:
		var line_color := Color(0.31, 0.32, 0.31)

		if bool(road.get("blocked", false)):
			line_color = Color(0.62, 0.18, 0.16)

		draw_line(
			_world_to_minimap(
				_intersection_world_position(_road_start(road))
			),
			_world_to_minimap(
				_intersection_world_position(_road_end(road))
			),
			line_color,
			1.5,
			true
		)

	if is_driving:
		var current_color := Color(0.98, 0.78, 0.06)

		if current_segment_off_route:
			current_color = Color(0.98, 0.34, 0.05)

		if current_segment_wrong_way:
			current_color = Color(0.90, 0.06, 0.05)

		draw_line(
			_world_to_minimap(camera_world_position),
			_world_to_minimap(
				_intersection_world_position(target_intersection)
			),
			current_color,
			3.0,
			true
		)

	for index in range(shortest_route.size() - 1):
		draw_line(
			_world_to_minimap(
				_intersection_world_position(shortest_route[index])
			),
			_world_to_minimap(
				_intersection_world_position(shortest_route[index + 1])
			),
			Color(0.98, 0.78, 0.06),
			2.5,
			true
		)

	draw_circle(
		_world_to_minimap(camera_world_position),
		4.0,
		Color(0.16, 0.88, 0.46)
	)

	draw_circle(
		_world_to_minimap(
			_intersection_world_position(destination_intersection)
		),
		4.0,
		Color(0.16, 0.42, 0.98)
	)

	draw_rect(
		map_rect,
		Color(0.82, 0.82, 0.78),
		false,
		2.0
	)


func _draw_minimap_geography() -> void:
	var lake := PackedVector2Array([
		_world_to_minimap(Vector2(2.0, 3.0)),
		_world_to_minimap(Vector2(8.0, 1.5)),
		_world_to_minimap(Vector2(14.0, 4.0)),
		_world_to_minimap(Vector2(13.0, 8.0)),
		_world_to_minimap(Vector2(7.0, 9.0)),
		_world_to_minimap(Vector2(2.5, 6.5)),
	])
	draw_colored_polygon(lake, Color(0.38, 0.63, 0.72))

	var woods := PackedVector2Array([
		_world_to_minimap(Vector2(16.0, 23.0)),
		_world_to_minimap(Vector2(28.0, 21.5)),
		_world_to_minimap(Vector2(31.0, 31.0)),
		_world_to_minimap(Vector2(18.0, 33.0)),
	])
	draw_colored_polygon(woods, Color(0.49, 0.62, 0.39))

	var fields := PackedVector2Array([
		_world_to_minimap(Vector2(0.5, 11.0)),
		_world_to_minimap(Vector2(12.5, 10.5)),
		_world_to_minimap(Vector2(13.0, 18.0)),
		_world_to_minimap(Vector2(1.0, 19.0)),
	])
	draw_colored_polygon(fields, Color(0.82, 0.78, 0.55))

	_draw_minimap_region_patch("neighborhood", Color(0.67, 0.75, 0.58, 0.55))
	_draw_minimap_region_patch("city", Color(0.55, 0.56, 0.57, 0.72))
	_draw_minimap_region_patch("parking", Color(0.35, 0.36, 0.36, 0.78))

	for tree in [
		Vector2(18.0, 25.0),
		Vector2(20.0, 29.0),
		Vector2(23.0, 24.0),
		Vector2(25.0, 28.0),
		Vector2(28.0, 25.0),
		Vector2(29.0, 30.0),
	]:
		draw_circle(
			_world_to_minimap(tree),
			1.4,
			Color(0.26, 0.43, 0.25)
		)


func _draw_minimap_region_patch(
	region_id: String,
	color: Color
) -> void:
	var region := WORLD_CONFIG.get_region(region_id)
	var origin: Vector2 = region["physical_origin"]
	var region_size: Vector2i = region["size"]
	var spacing: float = region["spacing"]
	var end := origin + Vector2(
		float(region_size.x - 1) * spacing,
		float(region_size.y - 1) * spacing
	)

	var top_left := _world_to_minimap(origin)
	var bottom_right := _world_to_minimap(end)

	draw_rect(
		Rect2(top_left, bottom_right - top_left),
		color,
		true
	)


func _world_to_main(world_point: Vector2) -> Vector2:
	var world_offset := world_point - camera_world_position
	var pixel_offset := world_offset * block_size
	var rotated_offset := pixel_offset.rotated(view_rotation)

	return size * 0.5 + rotated_offset


func _draw_world_rect(
	world_rect: Rect2,
	color: Color
) -> void:
	var top_left := _world_to_main(world_rect.position)
	var top_right := _world_to_main(
		world_rect.position + Vector2(world_rect.size.x, 0.0)
	)
	var bottom_right := _world_to_main(
		world_rect.position + world_rect.size
	)
	var bottom_left := _world_to_main(
		world_rect.position + Vector2(0.0, world_rect.size.y)
	)

	draw_colored_polygon(
		PackedVector2Array([
			top_left,
			top_right,
			bottom_right,
			bottom_left,
		]),
		color
	)


func _draw_world_line(
	world_start: Vector2,
	world_end: Vector2,
	color: Color,
	width: float
) -> void:
	draw_line(
		_world_to_main(world_start),
		_world_to_main(world_end),
		color,
		width,
		true
	)


func _minimap_rect() -> Rect2:
	return Rect2(
		Vector2(size.x - minimap_size - 10.0, 10.0),
		Vector2(minimap_size, minimap_size)
	)


func _world_to_minimap(world_point: Vector2) -> Vector2:
	var map_rect := _minimap_rect()
	var padding := 7.0
	var usable := map_rect.size - Vector2.ONE * padding * 2.0
	var scale := minf(
		usable.x / MAP_SIZE.x,
		usable.y / MAP_SIZE.y
	)
	var drawn_size := MAP_SIZE * scale
	var map_origin := (
		map_rect.position
		+ (map_rect.size - drawn_size) * 0.5
	)

	return map_origin + world_point * scale


func _update_region_label(region_id: String) -> void:
	var region := WORLD_CONFIG.get_region(region_id)
	map_label.text = str(region.get("name", region_id.to_upper()))


func _update_status_label() -> void:
	if current_segment_wrong_way:
		status_label.text = "WRONG WAY  •  TICKET"
	elif current_segment_off_route:
		status_label.text = "MISSED TURN  •  REROUTING"
	else:
		status_label.text = ""


func _road_start(road) -> Vector2i:
	return road["from"]


func _road_end(road) -> Vector2i:
	return road["to"]


func _get_road_between(
	a: Vector2i,
	b: Vector2i
):
	for road in roads:
		var road_a: Vector2i = _road_start(road)
		var road_b: Vector2i = _road_end(road)

		if (
			(road_a == a and road_b == b)
			or (road_a == b and road_b == a)
		):
			return road

	return null


func _is_wrong_way(
	road,
	travel_from: Vector2i,
	travel_to: Vector2i
) -> bool:
	if not bool(road.get("one_way", false)):
		return false

	return (
		travel_from != _road_start(road)
		or travel_to != _road_end(road)
	)


func _rotation_for_heading(direction: Vector2i) -> float:
	if direction == Vector2i.RIGHT:
		return -PI / 2.0

	if direction == Vector2i.DOWN:
		return PI

	if direction == Vector2i.LEFT:
		return PI / 2.0

	return 0.0
