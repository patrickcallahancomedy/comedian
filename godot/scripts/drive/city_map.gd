extends Control

const WORLD_CONFIG = preload("res://scripts/drive/drive_world_config.gd")

#constants
# DRIVE is one continuous 20x20 road world.
# The main view is intentionally close while the minimap shows the whole trip.
const WORLD_SIZE: int = WORLD_CONFIG.WORLD_SIZE
const NEIGHBORHOOD_ROADS_TO_REMOVE := 16
const CITY_ONE_WAY_COUNT := 12

# Main-view scale.
# Roughly 2-3 intersections fit across the phone screen at this spacing.
@export var block_size: float = 160.0
@export var road_width: float = 56.0

# Whole-world minimap size in the top-right corner.
@export var minimap_size: float = 132.0


#variables
#world data
# Every region contributes roads into these same arrays.
# There are no map loads or position resets during the drive.
# world_size mirrors the config constant so tests/debug tools can inspect it.
var world_size: int = WORLD_SIZE
var intersections: Array[Vector2i] = []

#physical world positions
# Intersections still use simple Vector2i IDs for pathfinding,
# but their actual visual position is stored separately.
# For now these positions exactly match the old grid coordinates.
# Later neighborhood/highway/city can use different spacing without
# changing the road graph or GPS logic.
var intersection_positions: Dictionary = {}

var roads: Array = []
var rng := RandomNumberGenerator.new()

#region data
# Region definitions are fixed placement/tuning data from drive_world_config.gd.
var region_ids: Array[String] = WORLD_CONFIG.get_region_ids()

#parking data
# Two spaces are open each run. Blocked spaces use the same road-access flag
# that can later support gates or other restricted roads.
var parking_slots: Array[Vector2i] = []
var open_parking_slots: Array[Vector2i] = []
var blocked_parking_slots: Array[Vector2i] = []

#route data
# GPS is calculated across the entire 20x20 world from Darren's current position
# to the final open parking space.
var start_intersection: Vector2i = WORLD_CONFIG.START
var destination_intersection := Vector2i.ZERO
var shortest_route: Array[Vector2i] = []

#drive position
# current_intersection is exact logic.
# camera_position moves smoothly between intersections while the car sprite stays still.
var current_intersection: Vector2i = WORLD_CONFIG.START
var target_intersection: Vector2i = WORLD_CONFIG.START
var camera_position := Vector2(WORLD_CONFIG.START)
# Physical position used by the close driving view.
# This can eventually move through long neighborhood blocks and short city blocks
# while current_intersection still stays a simple graph ID.
var camera_world_position := Vector2(WORLD_CONFIG.START)
var is_driving: bool = false
var drive_complete: bool = false

#turning
# Heading changes immediately when LEFT/RIGHT is pressed.
# The view rotation eases toward it, preserving the queued-turn behavior.
var heading := Vector2i.UP
var view_rotation: float = 0.0
var target_view_rotation: float = 0.0

#drive stats
var wrong_turns: int = 0
var wrong_way_tickets: int = 0
var drive_time: float = 0.0

#gps feedback
var current_segment_off_route: bool = false
var current_segment_wrong_way: bool = false


#touch / keyboard controls
@onready var left_button: Button = $"../TouchControls/LeftButton"
@onready var forward_button: Button = $"../TouchControls/ForwardButton"
@onready var right_button: Button = $"../TouchControls/RightButton"
@onready var map_label: Label = $"../MapLabel"
@onready var status_label: Label = $"../StatusLabel"


#functions
# Scene setup.
# Build one continuous world, calculate one whole-trip GPS route,
# then connect the same controls used on desktop and phone.
func _ready() -> void:
	rng.randomize()

	left_button.pressed.connect(_turn_left)
	forward_button.pressed.connect(_move_forward)
	right_button.pressed.connect(_turn_right)

	_build_world()
	_reset_drive_position()

	print("DRIVE world intersections: ", intersections.size())
	print("DRIVE world roads: ", roads.size())
	print("Whole trip route found: ", not shortest_route.is_empty())
#end ready


# Build the full 20x20 world in one pass.
# The four 5x5 regions are physically connected, so Darren never teleports
# or resets between neighborhood, highway, city, and parking.
func _build_world() -> void:
	intersections.clear()
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

	# One-way streets are added only after the final destination exists,
	# so every candidate can be checked against the complete trip.
	_add_city_one_ways(CITY_ONE_WAY_COUNT)

	# Recollect in case future road-generation edits add/remove endpoints.
	_collect_intersections_from_roads()
#end build world


# Build a full 5x5 neighborhood grid, then safely remove 16 road connections.
# This creates winding residential streets while keeping every neighborhood
# intersection reachable.
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

	var neighborhood_nodes := _region_nodes(origin, region_size)

	_remove_region_roads(
		"neighborhood",
		NEIGHBORHOOD_ROADS_TO_REMOVE,
		neighborhood_nodes
	)
#end build neighborhood


# Build the highway inside its 5x5 region.
# It is mostly a straight route with one optional exit loop.
# We are deliberately not inventing a lane-changing mechanic yet.
func _build_highway() -> void:
	# Entry ramp from the bottom-left edge of the highway region.
	_add_road(Vector2i(5, 12), Vector2i(5, 11), "ramp", 40, "highway")
	_add_road(Vector2i(5, 11), Vector2i(5, 10), "ramp", 40, "highway")

	# Main highway spine.
	_add_road(Vector2i(5, 10), Vector2i(6, 10), "highway", 65, "highway")
	_add_road(Vector2i(6, 10), Vector2i(7, 10), "highway", 65, "highway")
	_add_road(Vector2i(7, 10), Vector2i(8, 10), "highway", 65, "highway")
	_add_road(Vector2i(8, 10), Vector2i(9, 10), "highway", 65, "highway")

	# Optional off-ramp loop creates the highway's small navigation choice.
	_add_road(Vector2i(7, 10), Vector2i(7, 9), "ramp", 45, "highway")
	_add_road(Vector2i(7, 9), Vector2i(8, 9), "ramp", 45, "highway")
	_add_road(Vector2i(8, 9), Vector2i(8, 10), "ramp", 45, "highway")
#end build highway


# Build the full 5x5 downtown grid.
# No streets are removed. One-way directions are assigned later after the
# complete world exists so GPS can verify that the trip remains possible.
func _build_city() -> void:
	var region := WORLD_CONFIG.get_region("city")

	_add_region_grid(
		"city",
		region["origin"],
		region["size"],
		"city",
		30
	)
#end build city


# Build a compact parking lot inside its own 5x5 region.
# Four endpoint nodes act as spaces. Two are open each run and two are blocked.
func _build_parking_lot() -> void:
	# Entrance lane.
	_add_road(Vector2i(15, 4), Vector2i(16, 4), "parking", 10, "parking")
	_add_road(Vector2i(16, 4), Vector2i(17, 4), "parking", 10, "parking")

	# Center travel lane.
	_add_road(Vector2i(17, 4), Vector2i(17, 5), "parking", 10, "parking")
	_add_road(Vector2i(17, 5), Vector2i(17, 6), "parking", 10, "parking")
	_add_road(Vector2i(17, 6), Vector2i(17, 7), "parking", 10, "parking")
	_add_road(Vector2i(17, 7), Vector2i(17, 8), "parking", 10, "parking")

	# Upper parking aisle.
	_add_road(Vector2i(15, 5), Vector2i(16, 5), "parking", 10, "parking")
	_add_road(Vector2i(16, 5), Vector2i(17, 5), "parking", 10, "parking")
	_add_road(Vector2i(17, 5), Vector2i(18, 5), "parking", 10, "parking")
	_add_road(Vector2i(18, 5), Vector2i(19, 5), "parking", 10, "parking")

	# Lower parking aisle.
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

	# Pick two unique open spaces.
	var first_open_index := rng.randi_range(0, parking_slots.size() - 1)
	var second_open_index := first_open_index

	while second_open_index == first_open_index:
		second_open_index = rng.randi_range(0, parking_slots.size() - 1)

	open_parking_slots = [
		parking_slots[first_open_index],
		parking_slots[second_open_index],
	]

	# GPS chooses one of the open spaces, but parking in either one completes DRIVE.
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
#end build parking lot


# Physically connect the four regions inside the 20x20 coordinate system.
# These are normal road objects, not scene transitions.
func _build_region_connectors() -> void:
	# Neighborhood exit -> highway entry.
	_add_road(Vector2i(4, 12), Vector2i(5, 12), "ramp", 35, "highway")

	# Highway exit -> downtown entry.
	_add_road(Vector2i(9, 10), Vector2i(10, 10), "arterial", 40, "city")
	_add_road(Vector2i(10, 10), Vector2i(10, 9), "arterial", 40, "city")
	_add_road(Vector2i(10, 9), Vector2i(10, 8), "arterial", 40, "city")

	# Downtown exit -> parking lot entrance.
	_add_road(Vector2i(14, 4), Vector2i(15, 4), "parking", 10, "parking")
#end build region connectors


# Add a normal square grid inside one region.
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
#end add region grid


# Add one road dictionary.
# Every road carries the same small set of readable properties.
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
#end add road


# Return all intersection coordinates inside a rectangular region.
func _region_nodes(
	origin: Vector2i,
	region_size: Vector2i
) -> Array[Vector2i]:
	var nodes: Array[Vector2i] = []

	for y in range(region_size.y):
		for x in range(region_size.x):
			nodes.append(origin + Vector2i(x, y))

	return nodes
#end region nodes


# Safely remove roads only from one region.
# A removal is kept only if all 25 region nodes remain connected.
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

	print(region_id, " roads removed: ", removed_count, "/", target_count)
#end remove region roads


# Check physical connectivity inside one named region.
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
#end region is connected


# Collect unique road endpoints after the world graph is generated.
# Each intersection gets a separate physical world position.
# For this first refactor step, position still matches the old grid coordinate
# so gameplay and visuals should remain unchanged.
func _collect_intersections_from_roads() -> void:
	intersections.clear()
	intersection_positions.clear()

	var seen: Dictionary = {}

	for road in roads:
		var road_start: Vector2i = _road_start(road)
		var road_end: Vector2i = _road_end(road)

		seen[road_start] = true
		seen[road_end] = true

	for intersection in seen.keys():
		intersections.append(intersection)

		intersection_positions[intersection] = Vector2(
			intersection.x,
			intersection.y
		)

#end collect intersections


# Convert some downtown roads to one-way streets.
# Each candidate is reverted if it would destroy the legal GPS path from Darren's
# house to the final parking space.
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

		# Randomize which direction is legal.
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

	print("City one-way roads: ", added)
#end add city one ways


# Put Darren at the house and aim him down the first GPS road.
func _reset_drive_position() -> void:
	current_intersection = start_intersection
	target_intersection = start_intersection
	camera_position = Vector2(start_intersection)
	camera_world_position = intersection_positions.get(
		start_intersection,
		Vector2(start_intersection)
	)
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

	_update_region_label("neighborhood", 25)
	status_label.text = "PRESS GO"

	forward_button.disabled = false
	left_button.disabled = false
	right_button.disabled = false

	queue_redraw()
#end reset drive position


# Runs every frame.
# The car stays visually fixed while the continuous 20x20 world slides/rotates below it.
func _process(delta: float) -> void:
	if not is_equal_approx(view_rotation, target_view_rotation):
		view_rotation = lerp_angle(
			view_rotation,
			target_view_rotation,
			minf(1.0, delta * 10.0)
		)

	if is_driving:
		drive_time += delta

		var target_position := Vector2(target_intersection)
		var current_road = _get_road_between(
			current_intersection,
			target_intersection
		)

		var movement_speed := _movement_speed_for_road(current_road)

		camera_position = camera_position.move_toward(
			target_position,
			movement_speed * delta
		)

		if camera_position.is_equal_approx(target_position):
			camera_position = target_position
			current_intersection = target_intersection

			# Either open parking space is a valid finish.
			if open_parking_slots.has(current_intersection):
				_finish_drive()
				queue_redraw()
				return

			shortest_route = _find_shortest_route(
				current_intersection,
				destination_intersection
			)

			# Keep travelling in whichever direction the player has queued.
			var next_intersection := current_intersection + heading

			if not _commit_to_segment(next_intersection):
				is_driving = false
				current_segment_off_route = false
				current_segment_wrong_way = false
				status_label.text = "NO ROAD - TURN AND GO"

	queue_redraw()
#end process


# Commit Darren to one road.
# The player can physically drive against a one-way street, but it is marked
# as a wrong-way ticket and the GPS never recommends it.
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
		print("Wrong-way ticket: ", wrong_way_tickets)

	if current_segment_off_route:
		wrong_turns += 1
		print("Wrong turns: ", wrong_turns)

	target_intersection = next_intersection

	# GPS reroutes from the intersection Darren is approaching.
	shortest_route = _find_shortest_route(
		target_intersection,
		destination_intersection
	)

	_update_region_label(
		str(road.get("region", "neighborhood")),
		int(road.get("speed_limit", 25))
	)
	_update_status_label()

	return true
#end commit segment


# Finish DRIVE when Darren reaches either open parking space.
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

	print("DRIVE COMPLETE")
	print("Drive time: ", snappedf(drive_time, 0.1), " seconds")
	print("Wrong turns: ", wrong_turns)
	print("Wrong-way tickets: ", wrong_way_tickets)
#end finish drive


#movement controls
# GO only starts/restarts movement. Once Darren is rolling, LEFT/RIGHT are the
# actual driving verb.
func _move_forward() -> void:
	if drive_complete or is_driving:
		return

	var next_intersection := current_intersection + heading

	if _commit_to_segment(next_intersection):
		is_driving = true
#end move forward


# Queue a left turn and rotate the world under the fixed car.
func _turn_left() -> void:
	if drive_complete:
		return

	heading = Vector2i(heading.y, -heading.x)
	target_view_rotation += PI / 2.0
#end turn left


# Queue a right turn and rotate the world under the fixed car.
func _turn_right() -> void:
	if drive_complete:
		return

	heading = Vector2i(-heading.y, heading.x)
	target_view_rotation -= PI / 2.0
#end turn right


# Desktop controls mirror the phone buttons.
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


#pathfinding
# GPS runs across the same master graph shown by the minimap.
# One-way and blocked roads are respected.
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


# Return every road Darren's GPS may legally use from one intersection.
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


#drawing
# Draw the close main view first, then draw a north-up minimap of the same world.
func _draw() -> void:
	_draw_main_ground()
	_draw_region_surfaces()
	_draw_world_roads()
	_draw_main_gps()
	_draw_parking_spaces()
	_draw_destination_marker()
	_draw_minimap()
#end draw


# Neutral ground outside the four authored regions.
func _draw_main_ground() -> void:
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color(0.69, 0.72, 0.62)
	)
#end draw main ground


# Give the spaces between roads enough texture that motion and location are readable.
# These are simple procedural prototype surfaces, not final art assets.
func _draw_region_surfaces() -> void:
	for region_id in region_ids:
		var region := WORLD_CONFIG.get_region(region_id)
		var origin: Vector2i = region["origin"]
		var region_size: Vector2i = region["size"]

		for y in range(region_size.y - 1):
			for x in range(region_size.x - 1):
				var cell := origin + Vector2i(x, y)
				_draw_region_cell(region_id, cell)
#end draw region surfaces


# Draw one textured block between four intersection coordinates.
func _draw_region_cell(region_id: String, cell: Vector2i) -> void:
	var fill_color := Color(0.67, 0.72, 0.58)

	match region_id:
		"highway":
			fill_color = Color(0.57, 0.66, 0.48)
		"city":
			fill_color = Color(0.58, 0.59, 0.58)
		"parking":
			fill_color = Color(0.25, 0.26, 0.26)

	_draw_world_rect(
		Rect2(Vector2(cell), Vector2.ONE),
		fill_color
	)

	# Neighborhood: simple house + driveway footprints.
	if region_id == "neighborhood":
		_draw_world_rect(
			Rect2(
				Vector2(cell) + Vector2(0.24, 0.22),
				Vector2(0.48, 0.34)
			),
			Color(0.66, 0.50, 0.38)
		)

		_draw_world_rect(
			Rect2(
				Vector2(cell) + Vector2(0.44, 0.56),
				Vector2(0.10, 0.34)
			),
			Color(0.55, 0.55, 0.51)
		)

	# Highway: alternating grass bands provide obvious motion reference.
	elif region_id == "highway":
		for stripe in range(3):
			var stripe_x := 0.10 + float(stripe) * 0.30

			_draw_world_rect(
				Rect2(
					Vector2(cell) + Vector2(stripe_x, 0.08),
					Vector2(0.10, 0.84)
				),
				Color(0.53, 0.62, 0.44)
			)

	# City: large building footprints make blocks read immediately.
	elif region_id == "city":
		_draw_world_rect(
			Rect2(
				Vector2(cell) + Vector2(0.15, 0.14),
				Vector2(0.70, 0.72)
			),
			Color(0.38, 0.40, 0.42)
		)

		_draw_world_rect(
			Rect2(
				Vector2(cell) + Vector2(0.28, 0.26),
				Vector2(0.18, 0.16)
			),
			Color(0.48, 0.50, 0.52)
		)

	# Parking: subtle painted divider bands.
	elif region_id == "parking":
		for line_index in range(1, 4):
			var line_x := float(line_index) * 0.25
			_draw_world_line(
				Vector2(cell) + Vector2(line_x, 0.12),
				Vector2(cell) + Vector2(line_x, 0.88),
				Color(0.55, 0.55, 0.50),
				1.5
			)
#end draw region cell


# Draw every road in the master graph, including simple road markings.
func _draw_world_roads() -> void:
	for road in roads:
		var road_start_world: Vector2 = intersection_positions.get(
			_road_start(road),
			Vector2(_road_start(road))
		)

		var road_end_world: Vector2 = intersection_positions.get(
			_road_end(road),
			Vector2(_road_end(road))
		)

		var road_start := _world_to_main(road_start_world)
		var road_end := _world_to_main(road_end_world)
		var road_type := str(road.get("road_type", "neighborhood"))

		var current_width := road_width
		var road_color := Color(0.20, 0.21, 0.21)

		match road_type:
			"highway":
				current_width = road_width * 1.25
				road_color = Color(0.15, 0.16, 0.17)
			"ramp", "arterial":
				current_width = road_width * 1.05
				road_color = Color(0.18, 0.19, 0.20)
			"city":
				current_width = road_width * 0.92
				road_color = Color(0.22, 0.23, 0.24)
			"parking":
				current_width = road_width * 0.70
				road_color = Color(0.27, 0.28, 0.28)

		draw_line(
			road_start,
			road_end,
			road_color,
			current_width,
			true
		)

		# Simple center markings make speed/direction easier to read.
		if road_type == "highway":
			draw_dashed_line(
				road_start,
				road_end,
				Color(0.88, 0.88, 0.82),
				2.0,
				14.0,
				true
			)
		elif road_type != "parking":
			draw_dashed_line(
				road_start,
				road_end,
				Color(0.78, 0.67, 0.24),
				2.0,
				12.0,
				true
			)

		if bool(road.get("one_way", false)):
			_draw_one_way_arrow(road_start, road_end)

		if bool(road.get("blocked", false)):
			_draw_blocked_gate(road_start, road_end)
#end draw world roads


# Draw a small directional arrow on one-way city roads.
func _draw_one_way_arrow(road_start: Vector2, road_end: Vector2) -> void:
	var direction := (road_end - road_start).normalized()
	var side := Vector2(-direction.y, direction.x)
	var midpoint := road_start.lerp(road_end, 0.5)
	var tip := midpoint + direction * 9.0

	var arrow := PackedVector2Array([
		tip,
		midpoint - direction * 7.0 + side * 6.0,
		midpoint - direction * 7.0 - side * 6.0,
	])

	draw_colored_polygon(
		arrow,
		Color(0.92, 0.92, 0.88)
	)
#end draw one way arrow


# Draw a red parking gate across a blocked parking-space connection.
func _draw_blocked_gate(road_start: Vector2, road_end: Vector2) -> void:
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
#end draw blocked gate


# Main-view GPS.
# Current committed road is colored independently from the corrected route ahead.
func _draw_main_gps() -> void:
	if is_driving:
		var car_point := size * 0.5
		var next_point := _world_to_main(Vector2(target_intersection))
		var current_route_color := Color(0.95, 0.78, 0.08)

		if current_segment_off_route:
			current_route_color = Color(0.95, 0.32, 0.06)

		if current_segment_wrong_way:
			current_route_color = Color(0.86, 0.07, 0.06)

		draw_line(
			car_point,
			next_point,
			current_route_color,
			7.0,
			true
		)

	for index in range(shortest_route.size() - 1):
		draw_line(
			_world_to_main(Vector2(shortest_route[index])),
			_world_to_main(Vector2(shortest_route[index + 1])),
			Color(0.95, 0.78, 0.08),
			7.0,
			true
		)
#end draw main gps


# Draw parking spaces clearly in the close view.
func _draw_parking_spaces() -> void:
	for slot in parking_slots:
		var slot_point := _world_to_main(Vector2(slot))
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
#end draw parking spaces


# Final destination marker remains visible in the close view.
func _draw_destination_marker() -> void:
	var destination_point := _world_to_main(
		Vector2(destination_intersection)
	)

	draw_circle(
		destination_point,
		8.0,
		Color(0.13, 0.38, 0.92)
	)
#end draw destination marker


# Draw the entire 20x20 master world in the top-right corner.
# This is the exact same road/route data as the main view, just north-up and scaled down.
func _draw_minimap() -> void:
	var map_rect := _minimap_rect()

	draw_rect(
		map_rect,
		Color(0.08, 0.09, 0.09, 0.88),
		true
	)
	draw_rect(
		map_rect,
		Color(0.82, 0.82, 0.78),
		false,
		2.0
	)

	# Region footprints help the player understand the shape of the whole trip.
	for region_id in region_ids:
		var region := WORLD_CONFIG.get_region(region_id)
		var origin: Vector2i = region["origin"]
		var region_size: Vector2i = region["size"]

		var region_start := _world_to_minimap(Vector2(origin))
		var region_end := _world_to_minimap(
			Vector2(origin + region_size - Vector2i.ONE)
		)

		var region_color := Color(0.28, 0.34, 0.27, 0.55)

		match region_id:
			"highway":
				region_color = Color(0.24, 0.30, 0.22, 0.55)
			"city":
				region_color = Color(0.34, 0.34, 0.36, 0.55)
			"parking":
				region_color = Color(0.22, 0.23, 0.24, 0.70)

		draw_rect(
			Rect2(
				region_start,
				region_end - region_start
			),
			region_color,
			true
		)

	# Whole road graph.
	for road in roads:
		var line_color := Color(0.72, 0.72, 0.68)

		if bool(road.get("blocked", false)):
			line_color = Color(0.62, 0.18, 0.16)

		draw_line(
			_world_to_minimap(Vector2(_road_start(road))),
			_world_to_minimap(Vector2(_road_end(road))),
			line_color,
			1.5,
			true
		)

	# Current committed segment.
	if is_driving:
		var current_color := Color(0.98, 0.78, 0.06)

		if current_segment_off_route:
			current_color = Color(0.98, 0.34, 0.05)

		if current_segment_wrong_way:
			current_color = Color(0.90, 0.06, 0.05)

		draw_line(
			_world_to_minimap(camera_position),
			_world_to_minimap(Vector2(target_intersection)),
			current_color,
			3.0,
			true
		)

	# Corrected whole-trip GPS route.
	for index in range(shortest_route.size() - 1):
		draw_line(
			_world_to_minimap(Vector2(shortest_route[index])),
			_world_to_minimap(Vector2(shortest_route[index + 1])),
			Color(0.98, 0.78, 0.06),
			2.5,
			true
		)

	# Darren + destination.
	draw_circle(
		_world_to_minimap(camera_position),
		4.0,
		Color(0.16, 0.88, 0.46)
	)
	draw_circle(
		_world_to_minimap(Vector2(destination_intersection)),
		4.0,
		Color(0.16, 0.42, 0.98)
	)
#end draw minimap


#drawing helpers
# Convert any world-grid point to the close rotating main view.
func _world_to_main(world_point: Vector2) -> Vector2:
	var grid_offset := world_point - camera_position
	var pixel_offset := grid_offset * block_size
	var rotated_offset := pixel_offset.rotated(view_rotation)

	return size * 0.5 + rotated_offset
#end world to main


# Draw a rectangle defined in grid coordinates so it rotates with the world.
func _draw_world_rect(world_rect: Rect2, color: Color) -> void:
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
#end draw world rect


# Draw a line whose endpoints are written in world-grid coordinates.
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
#end draw world line


# Minimap rectangle.
func _minimap_rect() -> Rect2:
	return Rect2(
		Vector2(size.x - minimap_size - 10.0, 10.0),
		Vector2(minimap_size, minimap_size)
	)
#end minimap rect


# Convert a world-grid position into the north-up minimap.
func _world_to_minimap(world_point: Vector2) -> Vector2:
	var map_rect := _minimap_rect()
	var padding := 8.0
	var usable_size := minimap_size - padding * 2.0
	var scale := usable_size / float(WORLD_SIZE - 1)

	return (
		map_rect.position
		+ Vector2(padding, padding)
		+ world_point * scale
	)
#end world to minimap


#ui helpers
# Label the environment of the road Darren is currently travelling.
func _update_region_label(
	region_id: String,
	speed_limit: int
) -> void:
	var region := WORLD_CONFIG.get_region(region_id)
	var region_name := str(region.get("name", region_id.to_upper()))

	map_label.text = "%s  •  %d MPH" % [
		region_name,
		speed_limit,
	]
#end update region label


# Keep rerouting feedback readable without another gameplay mechanic.
func _update_status_label() -> void:
	if current_segment_wrong_way:
		status_label.text = "WRONG WAY  •  TICKET"
	elif current_segment_off_route:
		status_label.text = "MISSED TURN  •  REROUTING"
	else:
		status_label.text = ""
#end update status label


#helper functions
# Give each road environment a readable gameplay speed.
# MPH remains thematic UI information; these values are tuned for reaction time.
func _movement_speed_for_road(road) -> float:
	if road == null:
		return 0.48

	match str(road.get("road_type", "neighborhood")):
		"highway":
			return 0.72
		"ramp", "arterial":
			return 0.58
		"city":
			return 0.52
		"parking":
			return 0.36
		_:
			return 0.48
#end movement speed for road


# Return the starting intersection stored inside a road.
func _road_start(road) -> Vector2i:
	return road["from"]
#end road start


# Return the ending intersection stored inside a road.
func _road_end(road) -> Vector2i:
	return road["to"]
#end road end


# Find the actual road connecting two intersections.
# This ignores legal direction on purpose so the player can physically make
# a wrong-way choice and receive feedback for it.
func _get_road_between(a: Vector2i, b: Vector2i):
	for road in roads:
		var road_a: Vector2i = _road_start(road)
		var road_b: Vector2i = _road_end(road)

		if (
			(road_a == a and road_b == b)
			or (road_a == b and road_b == a)
		):
			return road

	return null
#end get road between


# Check whether Darren is travelling against a one-way road.
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
#end is wrong way


# Convert logical heading into the world rotation that keeps Darren visually
# facing toward the top of the screen.
func _rotation_for_heading(direction: Vector2i) -> float:
	if direction == Vector2i.RIGHT:
		return -PI / 2.0

	if direction == Vector2i.DOWN:
		return PI

	if direction == Vector2i.LEFT:
		return PI / 2.0

	return 0.0
#end rotation for heading
