class_name ProceduralRoadNetwork
extends RefCounted

## Road-first generator for COMEDIAN.
##
## The network has a density field:
## - dense, imperfect grid-like streets around Point A
## - a looser organic middle
## - dense, imperfect grid-like streets around Point B
##
## It is still one graph. The zones only influence spacing and direction.
## Visible roads are baked as flowing strands after the graph is complete.

const WORLD_RECT := Rect2(70.0, 70.0, 1060.0, 1360.0)

const START_DISTRICT_RECT := Rect2(565.0, 1080.0, 430.0, 285.0)
const END_DISTRICT_RECT := Rect2(145.0, 125.0, 430.0, 285.0)
const MIDDLE_RECT := Rect2(220.0, 390.0, 760.0, 720.0)

const DISTRICT_ROWS := 4
const DISTRICT_COLUMNS := 5
const DISTRICT_JITTER := 18.0
const DISTRICT_EDGE_KEEP_CHANCE := 0.82

const TARGET_NODE_COUNT := 62
const MIDDLE_CANDIDATES := 24
const MIDDLE_MIN_SPACING := 125.0

const MAX_DEGREE := 4
const LOOP_SEARCH_DISTANCE := 300.0
const EXTRA_EDGE_TARGET_MULTIPLIER := 1.22
const CURVE_SAMPLES_PER_EDGE := 10

var seed := 0
var nodes: Array = []
var adjacency: Array = []
var edge_curves: Dictionary = {}
var strand_curves: Array = []

var start_zone_nodes: Array = []
var middle_zone_nodes: Array = []
var end_zone_nodes: Array = []

var start_node := -1
var destination_node := -1

var _rng := RandomNumberGenerator.new()


func generate(seed_value: int, target_nodes: int = TARGET_NODE_COUNT) -> void:
	seed = seed_value
	_rng.seed = seed_value

	nodes.clear()
	adjacency.clear()
	edge_curves.clear()
	strand_curves.clear()
	start_zone_nodes.clear()
	middle_zone_nodes.clear()
	end_zone_nodes.clear()

	start_zone_nodes = _generate_district(
		START_DISTRICT_RECT,
		deg_to_rad(_rng.randf_range(-9.0, 9.0))
	)
	end_zone_nodes = _generate_district(
		END_DISTRICT_RECT,
		deg_to_rad(_rng.randf_range(-9.0, 9.0))
	)

	var dense_count := start_zone_nodes.size() + end_zone_nodes.size()
	var middle_target := maxi(12, target_nodes - dense_count)
	middle_zone_nodes = _generate_middle_points(middle_target)

	_connect_district(start_zone_nodes)
	_connect_district(end_zone_nodes)
	_connect_middle()
	_connect_zone_to_middle(start_zone_nodes, 3)
	_connect_zone_to_middle(end_zone_nodes, 3)

	_close_all_dead_ends()
	_add_extra_loops()
	_close_all_dead_ends()

	_bake_visible_strands()
	_choose_a_and_b()


func neighbors(node_id: int) -> Array:
	if node_id < 0 or node_id >= adjacency.size():
		return []
	return adjacency[node_id].duplicate()


func edge_curve(from_id: int, to_id: int) -> PackedVector2Array:
	var key := _edge_key(from_id, to_id)
	if not edge_curves.has(key):
		return PackedVector2Array()

	var stored: PackedVector2Array = edge_curves[key]
	if from_id < to_id:
		return stored

	var reversed := PackedVector2Array()
	for index in range(stored.size() - 1, -1, -1):
		reversed.append(stored[index])
	return reversed


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

			var weight: float = nodes[current].distance_to(nodes[neighbor])
			var alternate: float = best_distance + weight
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


func _generate_district(rect: Rect2, rotation: float) -> Array:
	var result: Array = []
	var center := rect.get_center()

	var x_spacing := rect.size.x / float(DISTRICT_COLUMNS - 1)
	var y_spacing := rect.size.y / float(DISTRICT_ROWS - 1)

	for row in range(DISTRICT_ROWS):
		for column in range(DISTRICT_COLUMNS):
			var point := Vector2(
				rect.position.x + float(column) * x_spacing,
				rect.position.y + float(row) * y_spacing
			)

			point -= center
			point = point.rotated(rotation)
			point += center

			point += Vector2(
				_rng.randf_range(-DISTRICT_JITTER, DISTRICT_JITTER),
				_rng.randf_range(-DISTRICT_JITTER, DISTRICT_JITTER)
			)

			point.x = clampf(
				point.x,
				WORLD_RECT.position.x + 16.0,
				WORLD_RECT.end.x - 16.0
			)
			point.y = clampf(
				point.y,
				WORLD_RECT.position.y + 16.0,
				WORLD_RECT.end.y - 16.0
			)

			result.append(_add_node(point))

	return result


func _generate_middle_points(count: int) -> Array:
	var result: Array = []

	while result.size() < count:
		var best_candidate := Vector2.ZERO
		var best_clearance := -1.0

		for candidate_index in range(MIDDLE_CANDIDATES):
			var candidate := Vector2(
				_rng.randf_range(
					MIDDLE_RECT.position.x,
					MIDDLE_RECT.end.x
				),
				_rng.randf_range(
					MIDDLE_RECT.position.y,
					MIDDLE_RECT.end.y
				)
			)

			var clearance := _nearest_node_distance(candidate)
			if clearance > best_clearance:
				best_clearance = clearance
				best_candidate = candidate

		# The center deliberately has larger spacing than the two dense ends.
		if (
			best_clearance >= MIDDLE_MIN_SPACING
			or result.size() >= count - 3
		):
			result.append(_add_node(best_candidate))
		else:
			result.append(_add_node(best_candidate))

	return result


func _connect_district(zone_nodes: Array) -> void:
	for row in range(DISTRICT_ROWS):
		for column in range(DISTRICT_COLUMNS):
			var node_id: int = int(
				zone_nodes[row * DISTRICT_COLUMNS + column]
			)

			if column < DISTRICT_COLUMNS - 1:
				var right_id: int = int(
					zone_nodes[
						row * DISTRICT_COLUMNS + column + 1
					]
				)
				# Horizontal continuity is strong; occasional gaps keep the
				# area from reading like a perfect city-builder grid.
				if (
					_rng.randf() <= DISTRICT_EDGE_KEEP_CHANCE
					or row == 1
					or row == DISTRICT_ROWS - 2
				):
					_add_edge(node_id, right_id)

			if row < DISTRICT_ROWS - 1:
				var down_id: int = int(
					zone_nodes[
						(row + 1) * DISTRICT_COLUMNS + column
					]
				)
				if (
					_rng.randf() <= DISTRICT_EDGE_KEEP_CHANCE
					or column == 1
					or column == DISTRICT_COLUMNS - 2
				):
					_add_edge(node_id, down_id)


func _connect_middle() -> void:
	if middle_zone_nodes.is_empty():
		return

	var connected: Array = [int(middle_zone_nodes[0])]
	var unconnected: Array = []
	for index in range(1, middle_zone_nodes.size()):
		unconnected.append(int(middle_zone_nodes[index]))

	while not unconnected.is_empty():
		var best_a := -1
		var best_b := -1
		var best_distance := INF
		var fallback_a := -1
		var fallback_b := -1
		var fallback_distance := INF

		for a_value in connected:
			var a: int = int(a_value)
			if adjacency[a].size() >= MAX_DEGREE:
				continue

			for b_value in unconnected:
				var b: int = int(b_value)
				var distance: float = nodes[a].distance_to(nodes[b])

				if distance < fallback_distance:
					fallback_distance = distance
					fallback_a = a
					fallback_b = b

				if distance >= best_distance:
					continue
				if _edge_would_cross(a, b):
					continue

				best_distance = distance
				best_a = a
				best_b = b

		if best_a < 0:
			best_a = fallback_a
			best_b = fallback_b

		if best_a < 0 or best_b < 0:
			break

		_add_edge(best_a, best_b)
		connected.append(best_b)
		unconnected.erase(best_b)


func _connect_zone_to_middle(zone_nodes: Array, connection_count: int) -> void:
	var candidates: Array = []

	for zone_value in zone_nodes:
		var zone_id: int = int(zone_value)
		for middle_value in middle_zone_nodes:
			var middle_id: int = int(middle_value)
			var distance: float = nodes[zone_id].distance_to(
				nodes[middle_id]
			)
			candidates.append([zone_id, middle_id, distance])

	candidates.sort_custom(
		func(a: Array, b: Array) -> bool:
			return float(a[2]) < float(b[2])
	)

	var added := 0
	for candidate in candidates:
		if added >= connection_count:
			break

		var a: int = int(candidate[0])
		var b: int = int(candidate[1])

		if adjacency[a].size() >= MAX_DEGREE:
			continue
		if adjacency[b].size() >= MAX_DEGREE:
			continue
		if adjacency[a].has(b):
			continue
		if _edge_would_cross(a, b):
			continue

		_add_edge(a, b)
		added += 1


func _close_all_dead_ends() -> void:
	var safety := nodes.size() * 16

	while safety > 0:
		safety -= 1
		var leaf := _first_leaf()
		if leaf < 0:
			return

		var candidate := _best_loop_target(leaf, true)
		if candidate < 0:
			candidate = _best_loop_target(leaf, false)
		if candidate < 0:
			return

		_add_edge(leaf, candidate)


func _add_extra_loops() -> void:
	var desired_edges := int(ceil(
		float(nodes.size()) * EXTRA_EDGE_TARGET_MULTIPLIER
	))
	var attempts := nodes.size() * 48

	while _edge_count() < desired_edges and attempts > 0:
		attempts -= 1

		var a := _rng.randi_range(0, nodes.size() - 1)
		if adjacency[a].size() >= MAX_DEGREE:
			continue

		var nearby := _nearby_candidates(a)
		if nearby.is_empty():
			continue

		var b: int = int(
			nearby[_rng.randi_range(0, nearby.size() - 1)]
		)
		if adjacency[b].size() >= MAX_DEGREE:
			continue
		if adjacency[a].has(b):
			continue
		if _edge_would_cross(a, b):
			continue

		_add_edge(a, b)


func _bake_visible_strands() -> void:
	edge_curves.clear()
	strand_curves.clear()

	var visited_edges: Dictionary = {}

	for node_id in range(nodes.size()):
		if adjacency[node_id].size() == 2:
			continue

		for neighbor_value in adjacency[node_id]:
			var neighbor: int = int(neighbor_value)
			var key := _edge_key(node_id, neighbor)
			if visited_edges.has(key):
				continue

			var sequence := _follow_strand(
				node_id,
				neighbor,
				visited_edges
			)
			_bake_sequence(sequence, false)

	for a in range(nodes.size()):
		for b_value in adjacency[a]:
			var b: int = int(b_value)
			if b <= a:
				continue

			var key := _edge_key(a, b)
			if visited_edges.has(key):
				continue

			var loop_sequence := _follow_closed_loop(
				a,
				b,
				visited_edges
			)
			_bake_sequence(loop_sequence, true)


func _follow_strand(
	start: int,
	first_neighbor: int,
	visited_edges: Dictionary
) -> Array:
	var sequence: Array = [start]
	var previous := start
	var current := first_neighbor

	while true:
		visited_edges[_edge_key(previous, current)] = true
		sequence.append(current)

		if adjacency[current].size() != 2:
			break

		var first: int = int(adjacency[current][0])
		var second: int = int(adjacency[current][1])
		var next: int = second if first == previous else first
		var next_key := _edge_key(current, next)

		if visited_edges.has(next_key):
			break

		previous = current
		current = next

	return sequence


func _follow_closed_loop(
	start: int,
	first_neighbor: int,
	visited_edges: Dictionary
) -> Array:
	var sequence: Array = [start]
	var previous := start
	var current := first_neighbor

	while true:
		visited_edges[_edge_key(previous, current)] = true
		sequence.append(current)

		var first: int = int(adjacency[current][0])
		var second: int = int(adjacency[current][1])
		var next: int = second if first == previous else first

		if next == start:
			visited_edges[_edge_key(current, next)] = true
			sequence.append(start)
			break

		var next_key := _edge_key(current, next)
		if visited_edges.has(next_key):
			break

		previous = current
		current = next

	return sequence


func _bake_sequence(sequence: Array, closed: bool) -> void:
	if sequence.size() < 2:
		return

	var visible := PackedVector2Array()

	for index in range(sequence.size() - 1):
		var p1_id: int = int(sequence[index])
		var p2_id: int = int(sequence[index + 1])

		var p1: Vector2 = nodes[p1_id]
		var p2: Vector2 = nodes[p2_id]
		var p0: Vector2 = p1
		var p3: Vector2 = p2

		if index > 0:
			p0 = nodes[int(sequence[index - 1])]
		elif closed and sequence.size() > 3:
			p0 = nodes[int(sequence[sequence.size() - 2])]

		if index + 2 < sequence.size():
			p3 = nodes[int(sequence[index + 2])]
		elif closed and sequence.size() > 3:
			p3 = nodes[int(sequence[1])]

		var curve := _sample_catmull_rom(
			p0,
			p1,
			p2,
			p3,
			CURVE_SAMPLES_PER_EDGE
		)
		_store_edge_curve(p1_id, p2_id, curve)

		for point_index in range(curve.size()):
			if not visible.is_empty() and point_index == 0:
				continue
			visible.append(curve[point_index])

	if visible.size() >= 2:
		strand_curves.append(visible)


func _store_edge_curve(
	a: int,
	b: int,
	curve_from_a_to_b: PackedVector2Array
) -> void:
	var stored := curve_from_a_to_b

	if a > b:
		stored = PackedVector2Array()
		for index in range(
			curve_from_a_to_b.size() - 1,
			-1,
			-1
		):
			stored.append(curve_from_a_to_b[index])

	edge_curves[_edge_key(a, b)] = stored


func _sample_catmull_rom(
	p0: Vector2,
	p1: Vector2,
	p2: Vector2,
	p3: Vector2,
	samples: int
) -> PackedVector2Array:
	var points := PackedVector2Array()

	for index in range(samples + 1):
		var t := float(index) / float(samples)
		var t2 := t * t
		var t3 := t2 * t
		var point: Vector2 = 0.5 * (
			2.0 * p1
			+ (-p0 + p2) * t
			+ (
				2.0 * p0
				- 5.0 * p1
				+ 4.0 * p2
				- p3
			) * t2
			+ (
				-p0
				+ 3.0 * p1
				- 3.0 * p2
				+ p3
			) * t3
		)
		points.append(point)

	return points


func _choose_a_and_b() -> void:
	start_node = _closest_usable_node(
		start_zone_nodes,
		START_DISTRICT_RECT.get_center()
	)
	destination_node = _closest_usable_node(
		end_zone_nodes,
		END_DISTRICT_RECT.get_center()
	)


func _closest_usable_node(
	candidates: Array,
	target: Vector2
) -> int:
	var best := -1
	var best_distance := INF

	for candidate_value in candidates:
		var candidate: int = int(candidate_value)
		if adjacency[candidate].size() < 2:
			continue

		var distance: float = nodes[candidate].distance_to(target)
		if distance < best_distance:
			best_distance = distance
			best = candidate

	return best


func _first_leaf() -> int:
	for node_id in range(nodes.size()):
		if adjacency[node_id].size() < 2:
			return node_id
	return -1


func _best_loop_target(
	leaf: int,
	require_no_crossing: bool
) -> int:
	var best := -1
	var best_score := INF

	for candidate in range(nodes.size()):
		if candidate == leaf:
			continue
		if adjacency[leaf].has(candidate):
			continue
		if adjacency[candidate].size() >= MAX_DEGREE:
			continue

		var distance: float = nodes[leaf].distance_to(nodes[candidate])
		if distance > LOOP_SEARCH_DISTANCE:
			continue
		if require_no_crossing and _edge_would_cross(leaf, candidate):
			continue

		var score := distance
		if adjacency[leaf].size() == 1:
			var existing: int = int(adjacency[leaf][0])
			if adjacency[existing].has(candidate):
				score += 110.0

		if score < best_score:
			best_score = score
			best = candidate

	return best


func _nearby_candidates(node_id: int) -> Array:
	var scored: Array = []

	for candidate in range(nodes.size()):
		if candidate == node_id:
			continue
		if adjacency[node_id].has(candidate):
			continue

		var distance: float = nodes[node_id].distance_to(
			nodes[candidate]
		)
		if distance > LOOP_SEARCH_DISTANCE:
			continue

		scored.append([candidate, distance])

	scored.sort_custom(
		func(a: Array, b: Array) -> bool:
			return float(a[1]) < float(b[1])
	)

	var result: Array = []
	for index in range(mini(7, scored.size())):
		result.append(int(scored[index][0]))

	return result


func _nearest_node_distance(point: Vector2) -> float:
	if nodes.is_empty():
		return INF

	var result := INF
	for existing in nodes:
		result = minf(
			result,
			point.distance_to(existing)
		)
	return result


func _add_node(position: Vector2) -> int:
	var node_id := nodes.size()
	nodes.append(position)
	adjacency.append([])
	return node_id


func _add_edge(a: int, b: int) -> void:
	if a == b:
		return
	if adjacency[a].has(b):
		return
	if adjacency[a].size() >= MAX_DEGREE:
		return
	if adjacency[b].size() >= MAX_DEGREE:
		return

	adjacency[a].append(b)
	adjacency[b].append(a)


func _edge_count() -> int:
	var total := 0
	for links in adjacency:
		total += links.size()
	return total / 2


func _edge_would_cross(a: int, b: int) -> bool:
	for c in range(nodes.size()):
		for d_value in adjacency[c]:
			var d: int = int(d_value)
			if d <= c:
				continue
			if c == a or c == b or d == a or d == b:
				continue

			if _segments_intersect(
				nodes[a],
				nodes[b],
				nodes[c],
				nodes[d]
			):
				return true

	return false


func _segments_intersect(
	a1: Vector2,
	a2: Vector2,
	b1: Vector2,
	b2: Vector2
) -> bool:
	var denominator := (
		(a2.x - a1.x) * (b2.y - b1.y)
		- (a2.y - a1.y) * (b2.x - b1.x)
	)

	if absf(denominator) < 0.0001:
		return false

	var ua := (
		(b2.x - b1.x) * (a1.y - b1.y)
		- (b2.y - b1.y) * (a1.x - b1.x)
	) / denominator
	var ub := (
		(a2.x - a1.x) * (a1.y - b1.y)
		- (a2.y - a1.y) * (a1.x - b1.x)
	) / denominator

	return (
		ua > 0.02
		and ua < 0.98
		and ub > 0.02
		and ub < 0.98
	)


func _edge_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]
