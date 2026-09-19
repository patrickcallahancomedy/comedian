extends Control

const DRIVE_MAP_CONFIGS = preload("res://scripts/drive/drive_map_configs.gd")

#constants
# These are the main tuning values for the current DRIVE prototype.
# They are exposed in the Inspector so we can change feel/scale without rewriting code.
@export var block_size: float = 650.0
@export var road_width: float = 320.0

# Base movement speed at 25 MPH.
# Individual road speed limits scale this up/down without changing the controls.
@export var drive_speed: float = 1.0


#variables
#map sequence
# DRIVE is one microgame made from four small maps.
# Reaching a map's destination loads the next map and stops the car until GO is pressed.
var map_configs: Array[Dictionary] = DRIVE_MAP_CONFIGS.get_maps()
var current_map_index: int = 0
var current_map: Dictionary = {}
var drive_complete: bool = false

#build map
# The generated map lives in these collections.
# intersections = every possible point Darren can reach.
# roads = the actual connections between those points.
var grid_size: int = 5
var roads_to_remove: int = 0
var intersections: Array[Vector2i] = []
var roads: Array = []
var rng := RandomNumberGenerator.new()

#block size variation
# These control how physically long each column and row of blocks is.
# Using shared lengths keeps every connected intersection lined up correctly.
var column_lengths: Array[float] = []
var row_lengths: Array[float] = []

#parking lot data
# Parking reuses the same road graph, but some final slot connections are blocked.
var parking_slots: Array[Vector2i] = []
var open_parking_slots: Array[Vector2i] = []
var blocked_parking_slots: Array[Vector2i] = []

#shortest route calc
# These values describe where Darren starts, where he is going,
# and the current GPS route between those two points.
var start_intersection := Vector2i.ZERO
var destination_intersection := Vector2i.ZERO
var shortest_route: Array[Vector2i] = []

#drive position
# current_intersection is exact game logic.
# camera_position can sit between intersections so the world can slide smoothly
# underneath the stationary car.
var current_intersection := Vector2i.ZERO
var target_intersection := Vector2i.ZERO
var camera_position := Vector2.ZERO
var is_driving: bool = false
var heading := Vector2i.UP
var view_rotation: float = 0.0
var target_view_rotation: float = 0.0

#drive stats
# These are result values we can eventually hand back to the larger COMEDIAN game.
var wrong_turns: int = 0
var wrong_way_tickets: int = 0
var drive_time: float = 0.0

#gps feedback
# off_route = Darren chose a road other than the GPS recommendation.
# wrong_way = Darren is travelling against a one-way street.
var current_segment_off_route: bool = false
var current_segment_wrong_way: bool = false


#touch / keyboard controls
# The buttons and keyboard both call the same movement functions below.
@onready var left_button: Button = $"../TouchControls/LeftButton"
@onready var forward_button: Button = $"../TouchControls/ForwardButton"
@onready var right_button: Button = $"../TouchControls/RightButton"
@onready var map_label: Label = $"../MapLabel"
@onready var status_label: Label = $"../StatusLabel"


#functions
# Scene setup.
# Creates the first map and connects the shared controls.
func _ready() -> void:
	rng.randomize()

	left_button.pressed.connect(_turn_left)
	forward_button.pressed.connect(_move_forward)
	right_button.pressed.connect(_turn_right)

	_load_map(0)
#end of ready()


# Load one of the four DRIVE maps.
# Every map resets position/heading, but the total drive timer and mistake stats
# continue across the full trip.
func _load_map(map_index: int) -> void:
	current_map_index = map_index
	current_map = map_configs[current_map_index]

	grid_size = int(current_map.get("grid_size", 5))
	roads_to_remove = int(current_map.get("roads_to_remove", 0))
	start_intersection = current_map.get("start", Vector2i.ZERO)
	destination_intersection = current_map.get("destination", Vector2i.ZERO)

	intersections.clear()
	roads.clear()
	parking_slots.clear()
	open_parking_slots.clear()
	blocked_parking_slots.clear()

	_build_block_lengths()

	var generator := str(current_map.get("generator", "grid"))

	match generator:
		"highway":
			_build_highway_map()
		"parking":
			_build_parking_map()
		_:
			_build_intersections()
			_build_grid_roads(
				str(current_map.get("road_type", "neighborhood")),
				int(current_map.get("speed_limit", 25))
			)
			_remove_random_roads()

			if int(current_map.get("one_way_count", 0)) > 0:
				_add_city_one_ways(int(current_map.get("one_way_count", 0)))

	current_intersection = start_intersection
	target_intersection = start_intersection
	camera_position = Vector2(start_intersection)
	is_driving = false
	current_segment_off_route = false
	current_segment_wrong_way = false

	shortest_route = _find_shortest_route(
		current_intersection,
		destination_intersection
	)

	# Face the first GPS road so every map begins in a readable orientation.
	if shortest_route.size() >= 2:
		heading = shortest_route[1] - shortest_route[0]
	else:
		heading = Vector2i.UP

	view_rotation = _rotation_for_heading(heading)
	target_view_rotation = view_rotation

	forward_button.disabled = false
	left_button.disabled = false
	right_button.disabled = false

	_update_map_label()
	status_label.text = "PRESS GO"

	print(
		"DRIVE MAP: ",
		str(current_map.get("name", "MAP")),
		" | connected: ",
		_city_is_connected(false),
		" | roads: ",
		roads.size()
	)

	queue_redraw()
#end load map


# Build every possible intersection in a square grid.
# Example: grid_size 5 creates coordinates from (0,0) through (4,4).
func _build_intersections() -> void:
	intersections.clear()

	for y in range(grid_size):
		for x in range(grid_size):
			intersections.append(Vector2i(x, y))
#end build intersections


# Build a normal square street grid.
# Neighborhood and city both use this base, then change it differently:
# neighborhood removes many roads; city keeps the grid dense and adds one-ways.
func _build_grid_roads(road_type: String, speed_limit: int) -> void:
	roads.clear()

	for y in range(grid_size):
		for x in range(grid_size):
			# Connect to the intersection on the right.
			if x < grid_size - 1:
				_add_road(
					Vector2i(x, y),
					Vector2i(x + 1, y),
					road_type,
					speed_limit
				)

			# Connect to the intersection below.
			if y < grid_size - 1:
				_add_road(
					Vector2i(x, y),
					Vector2i(x, y + 1),
					road_type,
					speed_limit
				)
#end build grid roads


# Build the highway as a mostly straight route with two optional exit/detour loops.
# This intentionally has far fewer decisions than neighborhood/city driving.
func _build_highway_map() -> void:
	roads.clear()

	# Main highway spine.
	_add_road(Vector2i(2, 4), Vector2i(2, 3), "highway", 65)
	_add_road(Vector2i(2, 3), Vector2i(2, 2), "highway", 65)
	_add_road(Vector2i(2, 2), Vector2i(2, 1), "highway", 65)
	_add_road(Vector2i(2, 1), Vector2i(2, 0), "highway", 65)

	# First optional exit loop.
	_add_road(Vector2i(2, 3), Vector2i(1, 3), "ramp", 45)
	_add_road(Vector2i(1, 3), Vector2i(1, 2), "ramp", 45)
	_add_road(Vector2i(1, 2), Vector2i(2, 2), "ramp", 45)

	# Second optional exit loop.
	_add_road(Vector2i(2, 1), Vector2i(3, 1), "ramp", 45)
	_add_road(Vector2i(3, 1), Vector2i(3, 0), "ramp", 45)
	_add_road(Vector2i(3, 0), Vector2i(2, 0), "ramp", 45)

	_collect_intersections_from_roads()
#end build highway map


# Build the parking lot from two parking aisles plus one center entrance lane.
# Four edge nodes act as parking spaces. Two are open each run and the others
# are blocked using the same road-access logic that later supports gates.
func _build_parking_map() -> void:
	roads.clear()

	# Center entrance / travel lane.
	_add_road(Vector2i(2, 4), Vector2i(2, 3), "parking", 10)
	_add_road(Vector2i(2, 3), Vector2i(2, 2), "parking", 10)
	_add_road(Vector2i(2, 2), Vector2i(2, 1), "parking", 10)
	_add_road(Vector2i(2, 1), Vector2i(2, 0), "parking", 10)

	# Lower parking aisle.
	for x in range(grid_size - 1):
		_add_road(Vector2i(x, 3), Vector2i(x + 1, 3), "parking", 10)

	# Upper parking aisle.
	for x in range(grid_size - 1):
		_add_road(Vector2i(x, 1), Vector2i(x + 1, 1), "parking", 10)

	parking_slots = [
		Vector2i(0, 3),
		Vector2i(4, 3),
		Vector2i(0, 1),
		Vector2i(4, 1),
	]

	# Pick two open spaces. GPS prefers the first one, but either open space
	# completes the final parking map.
	var first_open_index := rng.randi_range(0, parking_slots.size() - 1)
	open_parking_slots.append(parking_slots[first_open_index])

	var second_open_index := first_open_index
	while second_open_index == first_open_index:
		second_open_index = rng.randi_range(0, parking_slots.size() - 1)
	open_parking_slots.append(parking_slots[second_open_index])

	destination_intersection = open_parking_slots[0]

	for slot in parking_slots:
		if open_parking_slots.has(slot):
			continue

		blocked_parking_slots.append(slot)

		var neighbor := Vector2i(1, slot.y)
		if slot.x == 4:
			neighbor = Vector2i(3, slot.y)

		var gate_road = _get_road_between(slot, neighbor)
		if gate_road != null:
			gate_road["blocked"] = true

	_collect_intersections_from_roads()
#end build parking map


# Add one road dictionary.
# Keeping road creation in one place makes future road properties easy to add.
func _add_road(
	from_intersection: Vector2i,
	to_intersection: Vector2i,
	road_type: String,
	speed_limit: int,
	one_way: bool = false,
	blocked: bool = false
) -> void:
	roads.append({
		"from": from_intersection,
		"to": to_intersection,
		"road_type": road_type,
		"speed_limit": speed_limit,
		"one_way": one_way,
		"blocked": blocked,
	})
#end add road


# Custom highway/parking maps do not use every point in the 5x5 grid.
# Build their intersection list directly from the roads they actually contain.
func _collect_intersections_from_roads() -> void:
	intersections.clear()
	var seen: Dictionary = {}

	for road in roads:
		seen[_road_start(road)] = true
		seen[_road_end(road)] = true

	for intersection in seen.keys():
		intersections.append(intersection)
#end collect intersections


# Build the physical spacing between rows/columns.
# Neighborhood roads are longer, highway stretches are longest,
# city blocks are short, and parking spaces are compact.
func _build_block_lengths() -> void:
	column_lengths.clear()
	row_lengths.clear()

	var minimum_length := int(current_map.get("block_min", 1))
	var maximum_length := int(current_map.get("block_max", minimum_length))

	for x in range(grid_size - 1):
		column_lengths.append(
			float(rng.randi_range(minimum_length, maximum_length))
		)

	for y in range(grid_size - 1):
		row_lengths.append(
			float(rng.randi_range(minimum_length, maximum_length))
		)
#end build block lengths


# Turn some CITY roads into one-way streets.
# A candidate is only kept if there is still a legal GPS route from the city's
# start to its destination.
func _add_city_one_ways(target_count: int) -> void:
	var added := 0
	var attempts := 0

	while added < target_count and attempts < 300:
		attempts += 1

		var road_index := rng.randi_range(0, roads.size() - 1)
		var road: Dictionary = roads[road_index]

		if bool(road.get("one_way", false)):
			continue

		var original_from: Vector2i = _road_start(road)
		var original_to: Vector2i = _road_end(road)

		# Randomize the legal direction.
		if rng.randi_range(0, 1) == 1:
			road["from"] = original_to
			road["to"] = original_from

		road["one_way"] = true

		if _find_shortest_route(start_intersection, destination_intersection).is_empty():
			road["from"] = original_from
			road["to"] = original_to
			road["one_way"] = false
		else:
			added += 1
#end add city one ways


# Runs every frame.
# 1. smoothly rotate the map when Darren turns,
# 2. slide the map underneath the fixed car,
# 3. detect intersections,
# 4. continue straight / take the queued turn,
# 5. transition to the next map at each destination.
func _process(delta: float) -> void:
	# Smoothly rotate the world underneath the stationary car.
	if not is_equal_approx(view_rotation, target_view_rotation):
		view_rotation = lerp_angle(
			view_rotation,
			target_view_rotation,
			minf(1.0, delta * 10.0)
		)

	if is_driving:
		drive_time += delta

		var target_position := Vector2(target_intersection)

		# Keep visual speed consistent across long/short blocks,
		# then scale it using the road's speed limit.
		var segment_length := _segment_length_units(
			current_intersection,
			target_intersection
		)
		var speed_limit := _segment_speed_limit(
			current_intersection,
			target_intersection
		)
		var speed_factor := float(speed_limit) / 25.0
		var grid_speed := (
			drive_speed
			* speed_factor
			/ maxf(segment_length, 0.001)
		)

		camera_position = camera_position.move_toward(
			target_position,
			grid_speed * delta
		)

		# Darren has reached the intersection.
		if camera_position.is_equal_approx(target_position):
			camera_position = target_position
			current_intersection = target_intersection

			shortest_route = _find_shortest_route(
				current_intersection,
				destination_intersection
			)

			# Reaching the map destination moves the trip into the next environment.
			if _destination_reached():
				_finish_current_map()
				queue_redraw()
				return

			# Heading can change while Darren is between intersections.
			# That preserves the fun accidental "queue/drift the turn" behavior:
			# be facing the road you want when you reach the intersection.
			var next_intersection := current_intersection + heading

			if not _commit_to_segment(next_intersection):
				is_driving = false
				current_segment_off_route = false
				current_segment_wrong_way = false
				status_label.text = "NO ROAD - TURN AND GO"

	queue_redraw()
#end process


# Commit Darren to the next road segment.
# This is shared by GO and automatic intersection-to-intersection driving.
func _commit_to_segment(next_intersection: Vector2i) -> bool:
	if not intersections.has(next_intersection):
		return false

	var road = _get_road_between(current_intersection, next_intersection)

	if road == null:
		return false

	if bool(road.get("blocked", false)):
		status_label.text = "BLOCKED"
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
		print("Wrong-way ticket: ", wrong_way_tickets)

	if current_segment_off_route:
		wrong_turns += 1
		print("Wrong turns: ", wrong_turns)

	target_intersection = next_intersection

	# Once Darren commits to a road, the GPS immediately shows the route from
	# the intersection he is approaching so the player can prepare the next turn.
	shortest_route = _find_shortest_route(
		target_intersection,
		destination_intersection
	)

	_update_status_label()
	return true
#end commit segment


# Complete one map and either load the next map or finish DRIVE.
func _finish_current_map() -> void:
	is_driving = false
	current_segment_off_route = false
	current_segment_wrong_way = false

	print("MAP COMPLETE: ", str(current_map.get("name", "MAP")))

	if current_map_index < map_configs.size() - 1:
		_load_map(current_map_index + 1)
		return

	drive_complete = true
	forward_button.disabled = true
	left_button.disabled = true
	right_button.disabled = true

	map_label.text = "4/4  PARKING LOT"
	status_label.text = "PARKED  •  %.1f SEC" % drive_time

	print("DRIVE COMPLETE")
	print("Drive time: ", snappedf(drive_time, 0.1), " seconds")
	print("Wrong turns: ", wrong_turns)
	print("Wrong-way tickets: ", wrong_way_tickets)
#end finish current map


# Parking has two open spaces. Either one counts as a successful park.
# All other maps have one normal destination intersection.
func _destination_reached() -> bool:
	if str(current_map.get("id", "")) == "parking":
		return open_parking_slots.has(current_intersection)

	return current_intersection == destination_intersection
#end destination reached


# Convert a grid position into a physical position in the generated map.
# Grid coordinates can contain decimals because camera_position moves smoothly.
func _grid_to_world(grid_position: Vector2) -> Vector2:
	var world_x := 0.0
	var world_y := 0.0

	var safe_x := clampf(
		grid_position.x,
		0.0,
		float(grid_size - 1)
	)
	var safe_y := clampf(
		grid_position.y,
		0.0,
		float(grid_size - 1)
	)

	var whole_x := int(floor(safe_x))

	for x in range(mini(whole_x, column_lengths.size())):
		world_x += column_lengths[x] * block_size

	if whole_x < column_lengths.size():
		var x_fraction := safe_x - float(whole_x)
		world_x += (
			column_lengths[whole_x]
			* block_size
			* x_fraction
		)

	var whole_y := int(floor(safe_y))

	for y in range(mini(whole_y, row_lengths.size())):
		world_y += row_lengths[y] * block_size

	if whole_y < row_lengths.size():
		var y_fraction := safe_y - float(whole_y)
		world_y += (
			row_lengths[whole_y]
			* block_size
			* y_fraction
		)

	return Vector2(world_x, world_y)
#end grid to world


# Convert a city intersection into an on-screen position.
# The car stays fixed; the generated map moves/rotates underneath it.
func _city_to_screen(intersection: Vector2i) -> Vector2:
	var intersection_world := _grid_to_world(Vector2(intersection))
	var camera_world := _grid_to_world(camera_position)

	var world_offset := intersection_world - camera_world
	var rotated_offset := world_offset.rotated(view_rotation)

	return size * 0.5 + rotated_offset
#end city to screen


# Draw the current map.
# This is still intentionally simple debug art; the graph/gameplay is the part
# being proved before production road/building assets are added.
func _draw() -> void:
	for road in roads:
		var road_start := _city_to_screen(_road_start(road))
		var road_end := _city_to_screen(_road_end(road))
		var road_type := str(road.get("road_type", "neighborhood"))

		var current_road_color := Color(0.20, 0.20, 0.20)
		var current_road_width := road_width

		match road_type:
			"highway":
				current_road_color = Color(0.16, 0.17, 0.19)
				current_road_width = road_width * 1.35
			"ramp":
				current_road_color = Color(0.20, 0.21, 0.23)
				current_road_width = road_width * 1.05
			"city":
				current_road_color = Color(0.24, 0.24, 0.24)
				current_road_width = road_width * 0.85
			"parking":
				current_road_color = Color(0.30, 0.30, 0.30)
				current_road_width = road_width * 0.60

		if bool(road.get("blocked", false)):
			current_road_color = Color(0.36, 0.12, 0.12)
			current_road_width *= 0.65

		draw_line(
			road_start,
			road_end,
			current_road_color,
			current_road_width
		)

	# Small intersection markers remain useful while the map generator is debug art.
	for intersection in intersections:
		var point := _city_to_screen(intersection)
		draw_circle(point, 5.0, Color.RED)

	# Parking spaces are simple outlines for now.
	if str(current_map.get("id", "")) == "parking":
		for slot in parking_slots:
			var slot_point := _city_to_screen(slot)
			var slot_color := Color(0.35, 0.35, 0.35)

			if blocked_parking_slots.has(slot):
				slot_color = Color(0.55, 0.16, 0.16)
			elif slot == destination_intersection:
				slot_color = Color(0.18, 0.42, 0.95)
			elif open_parking_slots.has(slot):
				slot_color = Color(0.20, 0.55, 0.28)

			draw_rect(
				Rect2(slot_point - Vector2(34, 52), Vector2(68, 104)),
				slot_color,
				false,
				7.0
			)

	# Draw the road Darren is physically travelling on.
	# Yellow = correct route.
	# Orange = missed GPS turn.
	# Red = wrong way on a one-way street.
	if is_driving:
		var car_point := size * 0.5
		var next_point := _city_to_screen(target_intersection)
		var current_route_color := Color.YELLOW

		if current_segment_off_route:
			current_route_color = Color(1.0, 0.35, 0.08)

		if current_segment_wrong_way:
			current_route_color = Color(0.90, 0.08, 0.08)

		draw_line(
			car_point,
			next_point,
			current_route_color,
			12.0
		)

	# Corrected GPS route ahead always stays yellow.
	for i in range(shortest_route.size() - 1):
		var a := _city_to_screen(shortest_route[i])
		var b := _city_to_screen(shortest_route[i + 1])

		draw_line(
			a,
			b,
			Color.YELLOW,
			12.0
		)

	# Normal map destination.
	if str(current_map.get("id", "")) != "parking":
		var destination_point := _city_to_screen(destination_intersection)
		draw_circle(destination_point, 14.0, Color.BLUE)
#end draw


# Safety check for procedural generation.
# obey_access = false checks physical connectivity only.
# obey_access = true also respects one-way/blocked roads.
func _city_is_connected(obey_access: bool = false) -> bool:
	if intersections.is_empty():
		return true

	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []

	var first_intersection: Vector2i = intersections[0]
	queue.append(first_intersection)
	visited[first_intersection] = true

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()

		for road in roads:
			if obey_access and bool(road.get("blocked", false)):
				continue

			var a: Vector2i = _road_start(road)
			var b: Vector2i = _road_end(road)

			var neighbors: Array[Vector2i] = []

			if bool(road.get("one_way", false)) and obey_access:
				if a == current:
					neighbors.append(b)
			else:
				if a == current:
					neighbors.append(b)
				elif b == current:
					neighbors.append(a)

			for neighbor in neighbors:
				if not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)

	return visited.size() == intersections.size()
#end city is connected


# Procedurally remove roads to make the neighborhood sparse.
# A road removal is only kept if every grid intersection stays physically connected.
func _remove_random_roads() -> void:
	var removed_count := 0
	var attempts := 0

	while removed_count < roads_to_remove and attempts < 2000:
		attempts += 1

		var road_index := rng.randi_range(0, roads.size() - 1)
		var removed_road = roads[road_index]

		roads.remove_at(road_index)

		if _city_is_connected(false):
			removed_count += 1
		else:
			roads.insert(road_index, removed_road)

	print("Roads removed: ", removed_count, "/", roads_to_remove)
#end remove random roads


# GPS / pathfinding.
# Uses breadth-first search because the current GPS optimizes for fewest road
# segments. One-way and blocked roads are respected by the GPS.
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
#end find shortest route


# Return every legal GPS neighbor from one intersection.
# The PLAYER can still physically drive the wrong way on a one-way street;
# this restriction is for GPS/pathfinding only.
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
#end legal neighbors


# Start the drive.
# GO is only a start/restart control; once moving, LEFT/RIGHT are the real verb.
func _move_forward() -> void:
	if drive_complete or is_driving:
		return

	var next_intersection := current_intersection + heading

	if _commit_to_segment(next_intersection):
		is_driving = true
#end move forward


# Turn Darren's logical heading left.
# The car sprite stays still; target_view_rotation rotates the map underneath it.
func _turn_left() -> void:
	if drive_complete:
		return

	heading = Vector2i(heading.y, -heading.x)
	target_view_rotation += PI / 2.0
#end turn left


# Turn Darren's logical heading right.
# The car sprite stays still; target_view_rotation rotates the map underneath it.
func _turn_right() -> void:
	if drive_complete:
		return

	heading = Vector2i(-heading.y, heading.x)
	target_view_rotation -= PI / 2.0
#end turn right


# Desktop test controls.
# A = left, D = right, W = start/restart.
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
#end unhandled key input


#ui helpers
# Show where the player is in the four-part trip.
func _update_map_label() -> void:
	var map_name := str(current_map.get("name", "MAP"))
	var speed_limit := int(current_map.get("speed_limit", 25))

	map_label.text = "%d/4  %s  •  %d MPH" % [
		current_map_index + 1,
		map_name,
		speed_limit,
	]
#end update map label


# Keep missed-turn feedback readable without adding more controls.
func _update_status_label() -> void:
	if current_segment_wrong_way:
		status_label.text = "WRONG WAY  •  TICKET"
	elif current_segment_off_route:
		status_label.text = "MISSED TURN  •  REROUTING"
	else:
		status_label.text = ""
#end update status label


#helper functions
# Return the generated physical length of one road segment in road-units.
func _segment_length_units(
	from_intersection: Vector2i,
	to_intersection: Vector2i
) -> float:
	if from_intersection.y == to_intersection.y:
		var column := mini(from_intersection.x, to_intersection.x)

		if column >= 0 and column < column_lengths.size():
			return column_lengths[column]

	if from_intersection.x == to_intersection.x:
		var row := mini(from_intersection.y, to_intersection.y)

		if row >= 0 and row < row_lengths.size():
			return row_lengths[row]

	return 1.0
#end segment length


# Return the current road's speed limit.
func _segment_speed_limit(
	from_intersection: Vector2i,
	to_intersection: Vector2i
) -> int:
	var road = _get_road_between(from_intersection, to_intersection)

	if road != null:
		return int(road.get("speed_limit", 25))

	return int(current_map.get("speed_limit", 25))
#end segment speed limit


# Return the starting intersection stored inside a road.
func _road_start(road) -> Vector2i:
	return road["from"]
#end road start


# Return the ending intersection stored inside a road.
func _road_end(road) -> Vector2i:
	return road["to"]
#end road end


# Find the actual road object connecting two intersections.
# Blocked roads are still returned here so other systems can inspect them.
func _get_road_between(a: Vector2i, b: Vector2i):
	for road in roads:
		var road_a: Vector2i = _road_start(road)
		var road_b: Vector2i = _road_end(road)

		if (road_a == a and road_b == b) or (road_a == b and road_b == a):
			return road

	return null
#end get road between


# Check whether Darren is travelling against a one-way road.
# Legal one-way travel is always road["from"] -> road["to"].
func _is_wrong_way(
	road,
	travel_from: Vector2i,
	travel_to: Vector2i
) -> bool:
	if not bool(road.get("one_way", false)):
		return false

	var legal_from: Vector2i = _road_start(road)
	var legal_to: Vector2i = _road_end(road)

	return travel_from != legal_from or travel_to != legal_to
#end is wrong way


# Convert a logical heading into the rotation needed to keep that direction
# visually pointing toward the top of the screen.
func _rotation_for_heading(direction: Vector2i) -> float:
	if direction == Vector2i.RIGHT:
		return -PI / 2.0
	if direction == Vector2i.DOWN:
		return PI
	if direction == Vector2i.LEFT:
		return PI / 2.0

	return 0.0
#end rotation for heading
