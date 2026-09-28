class_name GridWorldGenerator
extends RefCounted

## COMEDIAN road-authoring prototype.
##
## One 500 x 500 logical grid contains every road system.
## Generation order:
## 1. Place Point A / home neighborhood.
## 2. Place Point B / city and reserve one full city block as the venue.
## 3. Choose the closest useful gateways between those two road systems.
## 4. Build the shortest practical connecting corridor.
## 5. Use a sparse highway corridor only when the geography actually needs it.
##
## The road classes are different generation rules inside one graph, not
## separate gameplay scenes or scale changes.

enum RoadClass {
	NEIGHBORHOOD,
	CITY,
	CONNECTOR,
	HIGHWAY,
}

const GRID_SIZE := 500
const WORLD_RECT := Rect2i(0, 0, GRID_SIZE, GRID_SIZE)

const NEIGHBORHOOD_COLUMNS := 10
const NEIGHBORHOOD_ROWS := 10
const NEIGHBORHOOD_SPACING := 10
const NEIGHBORHOOD_INTERSECTIONS := (
	NEIGHBORHOOD_COLUMNS * NEIGHBORHOOD_ROWS
)
const NEIGHBORHOOD_PRUNE_ATTEMPTS := 26

const CITY_COLUMNS := 7
const CITY_ROWS := 7
const CITY_SPACING := 30
const CITY_INTERSECTIONS := CITY_COLUMNS * CITY_ROWS
const CITY_PRUNE_ATTEMPTS := 14

const HIGHWAY_MIN_GATEWAY_DISTANCE := 115.0
const HIGHWAY_MAX_MAJOR_NODES := 10
const CONNECTOR_STEP := 10

const WORLD_MARGIN := 20

var seed := 0
var nodes: Array = []
var adjacency: Array = []
var edge_classes: Dictionary = {}
var coordinate_to_node: Dictionary = {}

var neighborhood_nodes: Array = []
var neighborhood_grid: Array = []
var city_nodes: Array = []
var city_grid: Array = []
var connector_nodes: Array = []
var highway_nodes: Array = []

var neighborhood_rect := Rect2i()
var city_rect := Rect2i()
var venue_block := Rect2i()

var home_node := -1
var venue_access_node := -1
var neighborhood_gateway := -1
var city_gateway := -1

var uses_highway := false
var gateway_distance := 0.0

var _rng := RandomNumberGenerator.new()


func generate(seed_value: int) -> void:
	seed = seed_value
	_rng.seed = seed_value

	nodes.clear()
	adjacency.clear()
	edge_classes.clear()
	coordinate_to_node.clear()

	neighborhood_nodes.clear()
	neighborhood_grid.clear()
	city_nodes.clear()
	city_grid.clear()
	connector_nodes.clear()
	highway_nodes.clear()

	home_node = -1
	venue_access_node = -1
	neighborhood_gateway = -1
	city_gateway = -1
	uses_highway = false
	gateway_distance = 0.0

	var placements := _choose_region_origins()
	var neighborhood_origin: Vector2i = placements["neighborhood"]
	var city_origin: Vector2i = placements["city"]

	neighborhood_grid = _generate_grid(
		neighborhood_origin,
		NEIGHBORHOOD_ROWS,
		NEIGHBORHOOD_COLUMNS,
		NEIGHBORHOOD_SPACING,
		RoadClass.NEIGHBORHOOD,
		neighborhood_nodes
	)
	city_grid = _generate_grid(
		city_origin,
		CITY_ROWS,
		CITY_COLUMNS,
		CITY_SPACING,
		RoadClass.CITY,
		city_nodes
	)

	neighborhood_rect = Rect2i(
		neighborhood_origin,
		Vector2i(
			(NEIGHBORHOOD_COLUMNS - 1) * NEIGHBORHOOD_SPACING,
			(NEIGHBORHOOD_ROWS - 1) * NEIGHBORHOOD_SPACING
		)
	)
	city_rect = Rect2i(
		city_origin,
		Vector2i(
			(CITY_COLUMNS - 1) * CITY_SPACING,
			(CITY_ROWS - 1) * CITY_SPACING
		)
	)

	_prune_zone(
		neighborhood_nodes,
		NEIGHBORHOOD_PRUNE_ATTEMPTS,
		RoadClass.NEIGHBORHOOD
	)
	_prune_zone(
		city_nodes,
		CITY_PRUNE_ATTEMPTS,
		RoadClass.CITY
	)

	_choose_home()
	_choose_venue_block()

	var farthest_gateways: Dictionary = _farthest_boundary_pair(
		neighborhood_grid,
		city_grid
	)
	neighborhood_gateway = int(farthest_gateways["neighborhood"])
	city_gateway = int(farthest_gateways["city"])
	gateway_distance = float(farthest_gateways["distance"])

	uses_highway = gateway_distance >= HIGHWAY_MIN_GATEWAY_DISTANCE

	if uses_highway:
		_generate_highway_connection()
	else:
		_generate_surface_connection()

	# Re-bake these two after the connection exists. If a connector happened
	# to meet a local grid coordinate it should be a real shared intersection.
	home_node = _nearest_usable_node(
		neighborhood_nodes,
		Vector2i(nodes[home_node])
	)
	venue_access_node = _nearest_venue_access_node()


func edge_class(a: int, b: int) -> int:
	var key := _edge_key(a, b)
	if not edge_classes.has(key):
		return -1
	return int(edge_classes[key])


func shortest_path(from_id: int, to_id: int) -> Array:
	if from_id == to_id:
		return [from_id]
	if from_id < 0 or to_id < 0:
		return []

	var distances: Dictionary = {}
	var previous: Dictionary = {}
	var unvisited: Array = []

	for node_id in range(nodes.size()):
		distances[node_id] = INF
		previous[node_id] = -1
		unvisited.append(node_id)

	distances[from_id] = 0.0

	while not unvisited.is_empty():
		var best_slot := 0
		var current: int = int(unvisited[0])
		var best_distance: float = float(distances[current])

		for slot in range(1, unvisited.size()):
			var candidate: int = int(unvisited[slot])
			var candidate_distance: float = float(distances[candidate])
			if candidate_distance < best_distance:
				best_slot = slot
				current = candidate
				best_distance = candidate_distance

		unvisited.remove_at(best_slot)

		if current == to_id:
			break
		if is_inf(best_distance):
			break

		for neighbor_value in adjacency[current]:
			var neighbor: int = int(neighbor_value)
			if not unvisited.has(neighbor):
				continue

			var weight := Vector2(nodes[current]).distance_to(
				Vector2(nodes[neighbor])
			)
			var alternate := best_distance + weight
			if alternate < float(distances[neighbor]):
				distances[neighbor] = alternate
				previous[neighbor] = current

	if int(previous[to_id]) == -1:
		return []

	var path: Array = [to_id]
	var cursor := to_id

	while cursor != from_id:
		cursor = int(previous[cursor])
		if cursor < 0:
			return []
		path.push_front(cursor)

	return path


func all_nodes_reachable_from(start_id: int) -> Array:
	if start_id < 0 or start_id >= nodes.size():
		return []

	var visited: Array = [start_id]
	var queue: Array = [start_id]

	while not queue.is_empty():
		var current: int = int(queue.pop_front())

		for neighbor_value in adjacency[current]:
			var neighbor: int = int(neighbor_value)
			if visited.has(neighbor):
				continue
			visited.append(neighbor)
			queue.append(neighbor)

	return visited


func _choose_region_origins() -> Dictionary:
	var neighborhood_span := Vector2i(
		(NEIGHBORHOOD_COLUMNS - 1) * NEIGHBORHOOD_SPACING,
		(NEIGHBORHOOD_ROWS - 1) * NEIGHBORHOOD_SPACING
	)
	var city_span := Vector2i(
		(CITY_COLUMNS - 1) * CITY_SPACING,
		(CITY_ROWS - 1) * CITY_SPACING
	)

	# Put each generated region in a corner of the 500x500 world, but never
	# the same corner. This keeps them distinct while allowing adjacent-corner
	# and opposite-corner trips.
	var neighborhood_corner: int = _rng.randi_range(0, 3)
	var city_corner: int = _rng.randi_range(0, 2)
	if city_corner >= neighborhood_corner:
		city_corner += 1

	var neighborhood_origin := _corner_origin_for_span(
		neighborhood_span,
		neighborhood_corner,
		NEIGHBORHOOD_SPACING,
		30
	)
	var city_origin := _corner_origin_for_span(
		city_span,
		city_corner,
		CONNECTOR_STEP,
		30
	)

	return {
		"neighborhood": neighborhood_origin,
		"city": city_origin,
	}


func _corner_origin_for_span(
	span: Vector2i,
	corner: int,
	snap_step: int,
	max_jitter: int
) -> Vector2i:
	var max_x: int = GRID_SIZE - WORLD_MARGIN - span.x
	var max_y: int = GRID_SIZE - WORLD_MARGIN - span.y

	var jitter_x: int = _snap_int(
		_rng.randi_range(0, max_jitter),
		snap_step
	)
	var jitter_y: int = _snap_int(
		_rng.randi_range(0, max_jitter),
		snap_step
	)

	var use_right: bool = corner == 1 or corner == 3
	var use_bottom: bool = corner == 2 or corner == 3

	var origin_x: int = (
		max_x - jitter_x
		if use_right
		else WORLD_MARGIN + jitter_x
	)
	var origin_y: int = (
		max_y - jitter_y
		if use_bottom
		else WORLD_MARGIN + jitter_y
	)

	return Vector2i(
		clampi(_snap_int(origin_x, snap_step), WORLD_MARGIN, max_x),
		clampi(_snap_int(origin_y, snap_step), WORLD_MARGIN, max_y)
	)


func _random_origin_for_span(
	span: Vector2i,
	snap_step: int
) -> Vector2i:
	var max_x := GRID_SIZE - WORLD_MARGIN - span.x
	var max_y := GRID_SIZE - WORLD_MARGIN - span.y

	var raw_x := _rng.randi_range(WORLD_MARGIN, max_x)
	var raw_y := _rng.randi_range(WORLD_MARGIN, max_y)

	return Vector2i(
		_snap_int(raw_x, snap_step),
		_snap_int(raw_y, snap_step)
	)


func _generate_grid(
	origin: Vector2i,
	rows: int,
	columns: int,
	spacing: int,
	road_class: int,
	zone_nodes: Array
) -> Array:
	var grid: Array = []

	for row in range(rows):
		var grid_row: Array = []

		for column in range(columns):
			var position := origin + Vector2i(
				column * spacing,
				row * spacing
			)
			var node_id := _add_node(position)
			grid_row.append(node_id)

			if not zone_nodes.has(node_id):
				zone_nodes.append(node_id)

		grid.append(grid_row)

	for row in range(rows):
		for column in range(columns):
			var node_id: int = int(grid[row][column])

			if column + 1 < columns:
				_add_edge(
					node_id,
					int(grid[row][column + 1]),
					road_class
				)

			if row + 1 < rows:
				_add_edge(
					node_id,
					int(grid[row + 1][column]),
					road_class
				)

	return grid


func _prune_zone(
	zone_nodes: Array,
	attempts: int,
	road_class: int
) -> void:
	var zone_lookup: Dictionary = {}
	for node_value in zone_nodes:
		zone_lookup[int(node_value)] = true

	var candidates: Array = []

	for a_value in zone_nodes:
		var a: int = int(a_value)
		for b_value in adjacency[a]:
			var b: int = int(b_value)

			if b <= a:
				continue
			if not zone_lookup.has(b):
				continue
			if edge_class(a, b) != road_class:
				continue

			candidates.append([a, b])

	_seeded_shuffle(candidates)

	var removed := 0

	for candidate in candidates:
		if removed >= attempts:
			break

		var a: int = int(candidate[0])
		var b: int = int(candidate[1])

		if _zone_degree(a, zone_lookup) <= 2:
			continue
		if _zone_degree(b, zone_lookup) <= 2:
			continue

		var old_class := edge_class(a, b)
		_remove_edge(a, b)

		if not _zone_is_connected(zone_nodes, zone_lookup):
			_add_edge(a, b, old_class)
			continue

		removed += 1


func _choose_home() -> void:
	var interior: Array = []

	for row in range(1, NEIGHBORHOOD_ROWS - 1):
		for column in range(1, NEIGHBORHOOD_COLUMNS - 1):
			var node_id: int = int(
				neighborhood_grid[row][column]
			)
			if adjacency[node_id].size() >= 3:
				interior.append(node_id)

	if interior.is_empty():
		home_node = int(
			neighborhood_grid[
				NEIGHBORHOOD_ROWS / 2
			][
				NEIGHBORHOOD_COLUMNS / 2
			]
		)
		return

	home_node = int(
		interior[_rng.randi_range(0, interior.size() - 1)]
	)


func _choose_venue_block() -> void:
	# B is one whole city block, never a point sitting in the road.
	var row := _rng.randi_range(1, CITY_ROWS - 3)
	var column := _rng.randi_range(1, CITY_COLUMNS - 3)

	var top_left_id: int = int(city_grid[row][column])
	var top_right_id: int = int(city_grid[row][column + 1])
	var bottom_left_id: int = int(city_grid[row + 1][column])
	var bottom_right_id: int = int(
		city_grid[row + 1][column + 1]
	)

	# Whatever pruning did elsewhere, the venue must remain a real complete
	# city block with roads on all four sides.
	_add_edge(top_left_id, top_right_id, RoadClass.CITY)
	_add_edge(top_left_id, bottom_left_id, RoadClass.CITY)
	_add_edge(top_right_id, bottom_right_id, RoadClass.CITY)
	_add_edge(bottom_left_id, bottom_right_id, RoadClass.CITY)

	var origin := Vector2i(nodes[top_left_id])
	venue_block = Rect2i(
		origin,
		Vector2i(CITY_SPACING, CITY_SPACING)
	)

	venue_access_node = _nearest_venue_access_node()


func _nearest_venue_access_node() -> int:
	if venue_block.size == Vector2i.ZERO:
		return -1

	var corners := [
		venue_block.position,
		venue_block.position + Vector2i(venue_block.size.x, 0),
		venue_block.position + Vector2i(0, venue_block.size.y),
		venue_block.end,
	]

	var best := -1
	var best_distance := INF
	var approach := Vector2i.ZERO

	if neighborhood_gateway >= 0:
		approach = Vector2i(nodes[neighborhood_gateway])
	elif home_node >= 0:
		approach = Vector2i(nodes[home_node])

	for corner in corners:
		var node_id := _node_at(Vector2i(corner))
		if node_id < 0:
			continue

		var distance := Vector2(corner).distance_to(Vector2(approach))
		if distance < best_distance:
			best_distance = distance
			best = node_id

	return best


func _farthest_boundary_pair(
	first_grid: Array,
	second_grid: Array
) -> Dictionary:
	var first_boundary: Array = _boundary_nodes(first_grid)
	var second_boundary: Array = _boundary_nodes(second_grid)

	var best_first: int = -1
	var best_second: int = -1
	var best_distance: float = -1.0

	for first_value in first_boundary:
		var first_id: int = int(first_value)
		var first_position: Vector2 = Vector2(nodes[first_id])

		for second_value in second_boundary:
			var second_id: int = int(second_value)
			var distance: float = first_position.distance_to(
				Vector2(nodes[second_id])
			)

			if distance > best_distance:
				best_distance = distance
				best_first = first_id
				best_second = second_id

	return {
		"neighborhood": best_first,
		"city": best_second,
		"distance": best_distance,
	}


func _boundary_nodes(grid: Array) -> Array:
	var result: Array = []
	var rows: int = grid.size()
	if rows == 0:
		return result

	var columns: int = grid[0].size()

	for row in range(rows):
		for column in range(columns):
			var on_boundary: bool = (
				row == 0
				or column == 0
				or row == rows - 1
				or column == columns - 1
			)
			if not on_boundary:
				continue

			var node_id: int = int(grid[row][column])
			if not result.has(node_id):
				result.append(node_id)

	return result


func _closest_boundary_node(
	grid: Array,
	target: Vector2i
) -> int:
	var rows := grid.size()
	if rows == 0:
		return -1

	var columns: int = grid[0].size()
	var best := -1
	var best_distance := INF

	for row in range(rows):
		for column in range(columns):
			var on_boundary: bool = (
				row == 0
				or column == 0
				or row == rows - 1
				or column == columns - 1
			)
			if not on_boundary:
				continue

			var node_id: int = int(grid[row][column])
			var distance := Vector2(nodes[node_id]).distance_to(
				Vector2(target)
			)

			if distance < best_distance:
				best_distance = distance
				best = node_id

	return best


func _generate_surface_connection() -> void:
	var start := Vector2i(nodes[neighborhood_gateway])
	var finish := Vector2i(nodes[city_gateway])

	_add_grid_path(
		start,
		finish,
		RoadClass.CONNECTOR,
		CONNECTOR_STEP,
		true
	)


func _generate_highway_connection() -> void:
	var start := Vector2i(nodes[neighborhood_gateway])
	var finish := Vector2i(nodes[city_gateway])
	var delta := finish - start

	var dominant_horizontal: bool = abs(delta.x) >= abs(delta.y)
	var entry := start
	var exit := finish

	if dominant_horizontal:
		var direction_x := 1 if delta.x >= 0 else -1
		var highway_y: int = _snap_int(
			int(round((float(start.y) + float(finish.y)) * 0.5)),
			20
		)

		entry = Vector2i(
			start.x + direction_x * 30,
			highway_y
		)
		exit = Vector2i(
			finish.x - direction_x * 30,
			highway_y
		)
	else:
		var direction_y := 1 if delta.y >= 0 else -1
		var highway_x: int = _snap_int(
			int(round((float(start.x) + float(finish.x)) * 0.5)),
			20
		)

		entry = Vector2i(
			highway_x,
			start.y + direction_y * 30
		)
		exit = Vector2i(
			highway_x,
			finish.y - direction_y * 30
		)

	entry = _clamp_to_world(_snap_point(entry, CONNECTOR_STEP))
	exit = _clamp_to_world(_snap_point(exit, CONNECTOR_STEP))

	_add_grid_path(
		start,
		entry,
		RoadClass.CONNECTOR,
		CONNECTOR_STEP,
		true
	)
	_add_grid_path(
		exit,
		finish,
		RoadClass.CONNECTOR,
		CONNECTOR_STEP,
		true
	)

	# Highway is one uninterrupted straight run. Any turns required to reach
	# it belong to the connectors, not the highway itself.
	var entry_id: int = _add_node(entry)
	var exit_id: int = _add_node(exit)

	highway_nodes.append(entry_id)
	if exit_id != entry_id:
		highway_nodes.append(exit_id)
		_add_edge(
			entry_id,
			exit_id,
			RoadClass.HIGHWAY
		)


func _add_grid_path(
	start: Vector2i,
	finish: Vector2i,
	road_class: int,
	step: int,
	randomize_axis_order: bool
) -> void:
	var current := start
	var horizontal_first := true

	if randomize_axis_order:
		horizontal_first = _rng.randf() < 0.5

	if horizontal_first:
		current = _walk_axis(
			current,
			Vector2i(finish.x, current.y),
			road_class,
			step
		)
		_walk_axis(
			current,
			finish,
			road_class,
			step
		)
	else:
		current = _walk_axis(
			current,
			Vector2i(current.x, finish.y),
			road_class,
			step
		)
		_walk_axis(
			current,
			finish,
			road_class,
			step
		)


func _walk_axis(
	start: Vector2i,
	finish: Vector2i,
	road_class: int,
	step: int
) -> Vector2i:
	var current := start
	var current_id := _add_node(current)

	while current != finish:
		var next := current

		if current.x != finish.x:
			var remaining_x := finish.x - current.x
			var move_x := mini(step, abs(remaining_x))
			next.x += move_x if remaining_x > 0 else -move_x
		elif current.y != finish.y:
			var remaining_y := finish.y - current.y
			var move_y := mini(step, abs(remaining_y))
			next.y += move_y if remaining_y > 0 else -move_y

		next = _clamp_to_world(next)

		var next_id := _add_node(next)

		if road_class == RoadClass.CONNECTOR:
			if not connector_nodes.has(current_id):
				connector_nodes.append(current_id)
			if not connector_nodes.has(next_id):
				connector_nodes.append(next_id)

		_add_edge(current_id, next_id, road_class)

		current = next
		current_id = next_id

	return current


func _nearest_usable_node(
	candidates: Array,
	target: Vector2i
) -> int:
	var best := -1
	var best_distance := INF

	for candidate_value in candidates:
		var candidate: int = int(candidate_value)
		if adjacency[candidate].size() < 2:
			continue

		var distance := Vector2(nodes[candidate]).distance_to(
			Vector2(target)
		)
		if distance < best_distance:
			best_distance = distance
			best = candidate

	return best


func _zone_degree(
	node_id: int,
	zone_lookup: Dictionary
) -> int:
	var degree := 0

	for neighbor_value in adjacency[node_id]:
		var neighbor: int = int(neighbor_value)
		if zone_lookup.has(neighbor):
			degree += 1

	return degree


func _zone_is_connected(
	zone_nodes: Array,
	zone_lookup: Dictionary
) -> bool:
	if zone_nodes.is_empty():
		return true

	var start: int = int(zone_nodes[0])
	var visited: Array = [start]
	var queue: Array = [start]

	while not queue.is_empty():
		var current: int = int(queue.pop_front())

		for neighbor_value in adjacency[current]:
			var neighbor: int = int(neighbor_value)
			if not zone_lookup.has(neighbor):
				continue
			if visited.has(neighbor):
				continue

			visited.append(neighbor)
			queue.append(neighbor)

	return visited.size() == zone_nodes.size()


func _seeded_shuffle(values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary


func _add_node(position: Vector2i) -> int:
	var clamped := _clamp_to_world(position)
	var key := _coordinate_key(clamped)

	if coordinate_to_node.has(key):
		return int(coordinate_to_node[key])

	var node_id := nodes.size()
	nodes.append(clamped)
	adjacency.append([])
	coordinate_to_node[key] = node_id
	return node_id


func _node_at(position: Vector2i) -> int:
	var key := _coordinate_key(position)
	if not coordinate_to_node.has(key):
		return -1
	return int(coordinate_to_node[key])


func _add_edge(a: int, b: int, road_class: int) -> void:
	if a < 0 or b < 0 or a == b:
		return

	var key := _edge_key(a, b)

	if not adjacency[a].has(b):
		adjacency[a].append(b)
		adjacency[b].append(a)

	if not edge_classes.has(key):
		edge_classes[key] = road_class
		return

	edge_classes[key] = maxi(
		int(edge_classes[key]),
		road_class
	)


func _remove_edge(a: int, b: int) -> void:
	adjacency[a].erase(b)
	adjacency[b].erase(a)
	edge_classes.erase(_edge_key(a, b))


func _snap_point(
	point: Vector2i,
	step: int
) -> Vector2i:
	return Vector2i(
		_snap_int(point.x, step),
		_snap_int(point.y, step)
	)


func _snap_int(value: int, step: int) -> int:
	return int(round(float(value) / float(step))) * step


func _clamp_to_world(point: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(point.x, 0, GRID_SIZE - 1),
		clampi(point.y, 0, GRID_SIZE - 1)
	)


func _append_unique_point(
	points: Array,
	point: Vector2i
) -> void:
	point = _clamp_to_world(
		_snap_point(point, CONNECTOR_STEP)
	)

	if points.is_empty() or Vector2i(points[-1]) != point:
		points.append(point)


func _coordinate_key(point: Vector2i) -> String:
	return "%d,%d" % [point.x, point.y]


func _edge_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]
