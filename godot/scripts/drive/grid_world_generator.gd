class_name GridWorldGenerator
extends RefCounted

## COMEDIAN road-authoring prototype.
##
## One 500 x 500 logical grid contains every road system.
## Generation order:
## 1. Place Point A / home neighborhood.
## 2. Place Point B / city and reserve one full city block as the venue.
## 3. Generate the longest clean straight highway corridor independently.
## 4. Build straight pink auxiliary lanes parallel to the highway.
## 5. Connect local streets to the pink endpoints with blue roads.
##
## The road classes are different generation rules inside one graph, not
## separate gameplay scenes or scale changes.

enum RoadClass {
	NEIGHBORHOOD,
	CITY,
	CONNECTOR,
	RAMP,
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

const CONNECTOR_STEP := 10
const HIGHWAY_EDGE_MARGIN := 10
const HIGHWAY_CLEARANCE := 50
const HIGHWAY_CORRIDOR_HALF_WIDTH := 50
const HIGHWAY_LANE_SPACING := 10
const HIGHWAY_LANE_CENTER_OFFSET := 5
const RAMP_STANDOFF := 15
const RAMP_RUN := 100

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
var auxiliary_merge_nodes: Array = []
var on_ramp_edges: Dictionary = {}

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
	auxiliary_merge_nodes.clear()
	on_ramp_edges.clear()

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

	# The highway is generated independently from A/B. It first claims the
	# longest clean straight corridor across the world, then each district
	# gets its own shortest practical connector to that corridor.
	uses_highway = true
	_generate_highway_connection()

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


func _generate_highway_connection() -> void:
	var corridor: Dictionary = _choose_longest_highway_corridor()
	var horizontal: bool = bool(corridor["horizontal"])
	var highway_start: Vector2i = corridor["start"]
	var highway_end: Vector2i = corridor["end"]

	var neighborhood_center := Vector2i(neighborhood_rect.get_center())
	var city_center := Vector2i(city_rect.get_center())
	var travel_sign := 1
	if horizontal:
		travel_sign = 1 if city_center.x >= neighborhood_center.x else -1
	else:
		travel_sign = 1 if city_center.y >= neighborhood_center.y else -1

	var neighborhood_access := _build_parallel_highway_access(
		neighborhood_rect,
		horizontal,
		highway_start,
		travel_sign,
		true
	)
	var city_access := _build_parallel_highway_access(
		city_rect,
		horizontal,
		highway_start,
		travel_sign,
		false
	)

	# Generation order is deliberate:
	# RED highway -> PINK auxiliary lanes -> nearest local road -> BLUE.
	# Access geometry is already planned above, but no pink/blue graph exists yet.
	_add_highway_with_merges(
		highway_start,
		highway_end,
		[
			neighborhood_access["merge"],
			city_access["merge"],
		],
		horizontal
	)

	_add_parallel_highway_access(neighborhood_access)
	_add_parallel_highway_access(city_access)

	var neighborhood_connector_target: Vector2i = (
		neighborhood_access["connector_target"]
	)
	var city_connector_target: Vector2i = (
		city_access["connector_target"]
	)

	# Only after each pink lane exists do local streets react to its endpoint.
	neighborhood_gateway = _closest_boundary_node(
		neighborhood_grid,
		neighborhood_connector_target
	)
	city_gateway = _closest_boundary_node(
		city_grid,
		city_connector_target
	)

	_add_connector_to_auxiliary_lane(
		Vector2i(nodes[neighborhood_gateway]),
		neighborhood_connector_target,
		horizontal,
		neighborhood_rect
	)
	_add_connector_to_auxiliary_lane(
		Vector2i(nodes[city_gateway]),
		city_connector_target,
		horizontal,
		city_rect
	)

	gateway_distance = Vector2(
		nodes[neighborhood_gateway]
	).distance_to(Vector2(nodes[city_gateway]))



func _add_connector_to_auxiliary_lane(
	start: Vector2i,
	target: Vector2i,
	horizontal_highway: bool,
	local_rect: Rect2i
) -> void:
	# Blue must meet the END of pink instead of overlapping the pink lane.
	# Force the final blue segment to approach perpendicular to the highway.
	var approach := target
	var center := Vector2i(local_rect.get_center())

	if horizontal_highway:
		approach.y = start.y
		if approach.y == target.y:
			var direction := signi(center.y - target.y)
			if direction == 0:
				direction = 1 if target.y < GRID_SIZE / 2 else -1
			approach.y = clampi(
				target.y + direction * CONNECTOR_STEP,
				0,
				GRID_SIZE - 1
			)
	else:
		approach.x = start.x
		if approach.x == target.x:
			var direction := signi(center.x - target.x)
			if direction == 0:
				direction = 1 if target.x < GRID_SIZE / 2 else -1
			approach.x = clampi(
				target.x + direction * CONNECTOR_STEP,
				0,
				GRID_SIZE - 1
			)

	_add_grid_path(
		start,
		approach,
		RoadClass.CONNECTOR,
		CONNECTOR_STEP,
		false
	)
	_add_grid_path(
		approach,
		target,
		RoadClass.CONNECTOR,
		CONNECTOR_STEP,
		false
	)


func _build_parallel_highway_access(
	rect: Rect2i,
	horizontal_highway: bool,
	highway_start: Vector2i,
	travel_sign: int,
	is_on_ramp: bool
) -> Dictionary:
	var center := Vector2i(rect.get_center())
	var merge := Vector2i.ZERO
	var lane_merge := Vector2i.ZERO
	var lane_highway_end := Vector2i.ZERO
	var lane_connector_end := Vector2i.ZERO
	var lane_side := 1

	# Pink is one auxiliary highway lane following A -> B travel.
	# Neighborhood is the on-ramp; city is the off-ramp.
	if horizontal_highway:
		var highway_y: int = highway_start.y
		var side: int = -1 if center.y < highway_y else 1
		lane_side = side
		var lane_y: int = highway_y + side * RAMP_STANDOFF
		var anchor_x: int = clampi(
			_snap_int(center.x, CONNECTOR_STEP),
			HIGHWAY_EDGE_MARGIN + RAMP_RUN,
			GRID_SIZE - HIGHWAY_EDGE_MARGIN - RAMP_RUN
		)

		if is_on_ramp:
			lane_connector_end = Vector2i(anchor_x, lane_y)
			lane_highway_end = Vector2i(
				anchor_x + travel_sign * RAMP_RUN,
				lane_y
			)
		else:
			lane_highway_end = Vector2i(anchor_x, lane_y)
			lane_connector_end = Vector2i(
				anchor_x + travel_sign * RAMP_RUN,
				lane_y
			)

		merge = Vector2i(lane_highway_end.x, highway_y)
	else:
		var highway_x: int = highway_start.x
		var side: int = -1 if center.x < highway_x else 1
		lane_side = side
		var lane_x: int = highway_x + side * RAMP_STANDOFF
		var anchor_y: int = clampi(
			_snap_int(center.y, CONNECTOR_STEP),
			HIGHWAY_EDGE_MARGIN + RAMP_RUN,
			GRID_SIZE - HIGHWAY_EDGE_MARGIN - RAMP_RUN
		)

		if is_on_ramp:
			lane_connector_end = Vector2i(lane_x, anchor_y)
			lane_highway_end = Vector2i(
				lane_x,
				anchor_y + travel_sign * RAMP_RUN
			)
		else:
			lane_highway_end = Vector2i(lane_x, anchor_y)
			lane_connector_end = Vector2i(
				lane_x,
				anchor_y + travel_sign * RAMP_RUN
			)

		merge = Vector2i(highway_x, lane_highway_end.y)

	merge = _clamp_to_world(_snap_point(merge, CONNECTOR_STEP))
	# Keep the 15-unit ramp centerline exact so its 10-unit width touches the
	# outer 10-unit highway lane instead of snapping back out to 20.
	lane_highway_end = _clamp_to_world(lane_highway_end)
	lane_connector_end = _clamp_to_world(lane_connector_end)

	# Pink may never occupy either local-road footprint. If the first
	# placement conflicts, slide the whole auxiliary lane along the highway
	# until the nearest clear 100-unit segment is found.
	var adjusted := _move_auxiliary_lane_clear_of_local_grids(
		lane_highway_end,
		lane_connector_end,
		merge,
		horizontal_highway
	)
	lane_highway_end = adjusted["highway_end"]
	lane_connector_end = adjusted["connector_end"]
	merge = adjusted["merge"]

	# The drivable merge point belongs to the outer red lane nearest pink,
	# not the center routing spine.
	if horizontal_highway:
		lane_merge = merge + Vector2i(
			0,
			lane_side * HIGHWAY_LANE_CENTER_OFFSET
		)
	else:
		lane_merge = merge + Vector2i(
			lane_side * HIGHWAY_LANE_CENTER_OFFSET,
			0
		)

	return {
		"merge": merge,
		"lane_merge": lane_merge,
		"lane_highway_end": lane_highway_end,
		"connector_target": lane_connector_end,
		"is_on_ramp": is_on_ramp,
	}


func _move_auxiliary_lane_clear_of_local_grids(
	highway_end: Vector2i,
	connector_end: Vector2i,
	merge: Vector2i,
	horizontal: bool
) -> Dictionary:
	if not _auxiliary_lane_overlaps_local_grid(highway_end, connector_end):
		return {
			"highway_end": highway_end,
			"connector_end": connector_end,
			"merge": merge,
		}

	var original_highway := highway_end
	var original_connector := connector_end
	var original_merge := merge

	for distance in range(CONNECTOR_STEP, GRID_SIZE, CONNECTOR_STEP):
		for direction in [-1, 1]:
			var delta := (
				Vector2i(distance * direction, 0)
				if horizontal
				else Vector2i(0, distance * direction)
			)
			var candidate_highway := original_highway + delta
			var candidate_connector := original_connector + delta
			var candidate_merge := original_merge + delta

			if not WORLD_RECT.has_point(candidate_highway):
				continue
			if not WORLD_RECT.has_point(candidate_connector):
				continue
			if not WORLD_RECT.has_point(candidate_merge):
				continue
			var merge_axis: int = candidate_merge.x if horizontal else candidate_merge.y
			if (
				merge_axis < HIGHWAY_EDGE_MARGIN
				or merge_axis > GRID_SIZE - HIGHWAY_EDGE_MARGIN
			):
				continue
			if _auxiliary_lane_overlaps_local_grid(
				candidate_highway,
				candidate_connector
			):
				continue

			return {
				"highway_end": candidate_highway,
				"connector_end": candidate_connector,
				"merge": candidate_merge,
			}

	return {
		"highway_end": highway_end,
		"connector_end": connector_end,
		"merge": merge,
	}


func _auxiliary_lane_overlaps_local_grid(
	start: Vector2i,
	finish: Vector2i
) -> bool:
	return (
		_segment_hits_rect_inclusive(start, finish, neighborhood_rect)
		or _segment_hits_rect_inclusive(start, finish, city_rect)
	)


func _segment_hits_rect_inclusive(
	start: Vector2i,
	finish: Vector2i,
	rect: Rect2i
) -> bool:
	var min_x := mini(start.x, finish.x)
	var max_x := maxi(start.x, finish.x)
	var min_y := mini(start.y, finish.y)
	var max_y := maxi(start.y, finish.y)

	return not (
		max_x < rect.position.x
		or min_x > rect.end.x
		or max_y < rect.position.y
		or min_y > rect.end.y
	)


func _add_parallel_highway_access(access: Dictionary) -> void:
	# Pink is one straight auxiliary lane. It never turns toward the highway.
	# The merge is a graph-only connection so the map stays visually straight.
	var connector_end: Vector2i = access["connector_target"]
	var highway_end: Vector2i = access["lane_highway_end"]
	var lane_merge: Vector2i = access["lane_merge"]
	var merge: Vector2i = access["merge"]

	_add_grid_path(
		connector_end,
		highway_end,
		RoadClass.RAMP,
		CONNECTOR_STEP,
		false
	)
	if bool(access["is_on_ramp"]):
		_mark_on_ramp_edges(connector_end, highway_end)
	# Pink first enters the adjacent outer red lane. The second hidden link
	# preserves the existing single-spine highway routing graph.
	_add_logical_link(highway_end, lane_merge)
	_add_logical_link(lane_merge, merge)

	var lane_merge_id := _node_at(lane_merge)
	if lane_merge_id >= 0 and not auxiliary_merge_nodes.has(lane_merge_id):
		auxiliary_merge_nodes.append(lane_merge_id)



func _mark_on_ramp_edges(start: Vector2i, finish: Vector2i) -> void:
	var current := start
	while current != finish:
		var next := current
		if current.x != finish.x:
			var remaining_x := finish.x - current.x
			var move_x := mini(CONNECTOR_STEP, abs(remaining_x))
			next.x += move_x if remaining_x > 0 else -move_x
		else:
			var remaining_y := finish.y - current.y
			var move_y := mini(CONNECTOR_STEP, abs(remaining_y))
			next.y += move_y if remaining_y > 0 else -move_y

		var a := _node_at(current)
		var b := _node_at(next)
		if a >= 0 and b >= 0:
			on_ramp_edges[_edge_key(a, b)] = true
		current = next


func is_on_ramp_edge(a: int, b: int) -> bool:
	return on_ramp_edges.has(_edge_key(a, b))


func _add_logical_link(start: Vector2i, finish: Vector2i) -> void:
	var a := _add_node(start)
	var b := _add_node(finish)
	if a == b:
		return
	if not adjacency[a].has(b):
		adjacency[a].append(b)
	if not adjacency[b].has(a):
		adjacency[b].append(a)


func _choose_longest_highway_corridor() -> Dictionary:
	var first_coordinate := maxi(
		HIGHWAY_EDGE_MARGIN,
		HIGHWAY_CORRIDOR_HALF_WIDTH
	)
	var last_coordinate := mini(
		GRID_SIZE - HIGHWAY_EDGE_MARGIN,
		GRID_SIZE - HIGHWAY_CORRIDOR_HALF_WIDTH
	)
	var best_horizontal := true
	var best_coordinate := first_coordinate
	var best_length := -1
	var best_connector_cost := INF
	var start_axis := HIGHWAY_EDGE_MARGIN
	var end_axis := GRID_SIZE - HIGHWAY_EDGE_MARGIN
	var corridor_length := end_axis - start_axis

	for coordinate in range(
		first_coordinate,
		last_coordinate + 1,
		CONNECTOR_STEP
	):
		if _horizontal_corridor_is_clear(coordinate):
			var connector_cost := (
				_distance_from_grid_to_horizontal(
					neighborhood_grid,
					coordinate
				)
				+ _distance_from_grid_to_horizontal(
					city_grid,
					coordinate
				)
			)
			if (
				corridor_length > best_length
				or (
					corridor_length == best_length
					and connector_cost < best_connector_cost
				)
			):
				best_horizontal = true
				best_coordinate = coordinate
				best_length = corridor_length
				best_connector_cost = connector_cost

	for coordinate in range(
		first_coordinate,
		last_coordinate + 1,
		CONNECTOR_STEP
	):
		if _vertical_corridor_is_clear(coordinate):
			var connector_cost := (
				_distance_from_grid_to_vertical(
					neighborhood_grid,
					coordinate
				)
				+ _distance_from_grid_to_vertical(
					city_grid,
					coordinate
				)
			)
			if (
				corridor_length > best_length
				or (
					corridor_length == best_length
					and connector_cost < best_connector_cost
				)
			):
				best_horizontal = false
				best_coordinate = coordinate
				best_length = corridor_length
				best_connector_cost = connector_cost

	if best_horizontal:
		return {
			"horizontal": true,
			"start": Vector2i(start_axis, best_coordinate),
			"end": Vector2i(end_axis, best_coordinate),
		}

	return {
		"horizontal": false,
		"start": Vector2i(best_coordinate, start_axis),
		"end": Vector2i(best_coordinate, end_axis),
	}


func _horizontal_corridor_is_clear(y: int) -> bool:
	return (
		_line_has_clearance_from_rect(
			y,
			neighborhood_rect,
			true
		)
		and _line_has_clearance_from_rect(
			y,
			city_rect,
			true
		)
	)


func _vertical_corridor_is_clear(x: int) -> bool:
	return (
		_line_has_clearance_from_rect(
			x,
			neighborhood_rect,
			false
		)
		and _line_has_clearance_from_rect(
			x,
			city_rect,
			false
		)
	)


func _line_has_clearance_from_rect(
	coordinate: int,
	rect: Rect2i,
	horizontal: bool
) -> bool:
	if horizontal:
		return (
			coordinate <= rect.position.y - HIGHWAY_CLEARANCE
			or coordinate >= rect.end.y + HIGHWAY_CLEARANCE
		)

	return (
		coordinate <= rect.position.x - HIGHWAY_CLEARANCE
		or coordinate >= rect.end.x + HIGHWAY_CLEARANCE
	)


func _distance_from_grid_to_horizontal(
	grid: Array,
	y: int
) -> float:
	var best := INF
	for node_value in _boundary_nodes(grid):
		var point: Vector2i = nodes[int(node_value)]
		best = minf(best, absf(float(point.y - y)))
	return best


func _distance_from_grid_to_vertical(
	grid: Array,
	x: int
) -> float:
	var best := INF
	for node_value in _boundary_nodes(grid):
		var point: Vector2i = nodes[int(node_value)]
		best = minf(best, absf(float(point.x - x)))
	return best


func _add_highway_with_merges(
	start: Vector2i,
	finish: Vector2i,
	merges: Array,
	horizontal: bool
) -> void:
	var points: Array = [start]
	for merge_value in merges:
		var merge: Vector2i = merge_value
		if not points.has(merge):
			points.append(merge)
	if not points.has(finish):
		points.append(finish)

	points.sort_custom(func(a, b):
		var pa: Vector2i = a
		var pb: Vector2i = b
		return pa.x < pb.x if horizontal else pa.y < pb.y
	)

	for point_value in points:
		_add_node(Vector2i(point_value))

	var start_id := _node_at(start)
	var finish_id := _node_at(finish)
	highway_nodes.append(start_id)
	if finish_id != start_id:
		highway_nodes.append(finish_id)

	for index in range(points.size() - 1):
		var a := _node_at(Vector2i(points[index]))
		var b := _node_at(Vector2i(points[index + 1]))
		if a != b:
			_add_edge(a, b, RoadClass.HIGHWAY)


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
