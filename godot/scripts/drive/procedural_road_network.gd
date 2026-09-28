class_name ProceduralRoadNetwork
extends RefCounted

## Road-first generator for COMEDIAN.
##
## Important separation:
## - nodes / adjacency are routing data.
## - strand_curves are the visible roads.
##
## We first make one connected planar-ish graph, close every leaf into a loop,
## then bake degree-2 chains into long Catmull-Rom road strands. The player
## therefore sees roads that flow through the graph instead of individual
## edge pieces stitched together.

const WORLD_RECT := Rect2(70.0, 70.0, 1060.0, 1360.0)
const TARGET_NODE_COUNT := 64
const POINT_CANDIDATES := 22
const MIN_POINT_SPACING := 82.0
const MAX_DEGREE := 4
const LOOP_SEARCH_DISTANCE := 310.0
const EXTRA_EDGE_TARGET_MULTIPLIER := 1.18
const CURVE_SAMPLES_PER_EDGE := 10

var seed := 0
var nodes: Array = []
var adjacency: Array = []
var edge_curves: Dictionary = {}
var strand_curves: Array = []

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

	_generate_organic_points(target_nodes)
	_build_connected_skeleton()
	_close_all_dead_ends()
	_add_extra_loops()
	_bake_visible_strands()
	_choose_far_apart_points()


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
			var alt: float = best_distance + weight
			if alt < float(distances[neighbor]):
				distances[neighbor] = alt
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


func _generate_organic_points(target_nodes: int) -> void:
	# Best-candidate blue-noise placement. There is no grid and no tile size.
	# Each accepted point is simply the best-spaced location from a small
	# random candidate pool, which produces irregular but usable road density.
	var center := WORLD_RECT.get_center()
	_add_node(center)

	while nodes.size() < target_nodes:
		var best_candidate := Vector2.ZERO
		var best_clearance := -1.0

		for candidate_index in range(POINT_CANDIDATES):
			var candidate := Vector2(
				_rng.randf_range(
					WORLD_RECT.position.x,
					WORLD_RECT.end.x
				),
				_rng.randf_range(
					WORLD_RECT.position.y,
					WORLD_RECT.end.y
				)
			)
			var clearance := _nearest_node_distance(candidate)
			if clearance > best_clearance:
				best_clearance = clearance
				best_candidate = candidate

		if (
			best_clearance >= MIN_POINT_SPACING
			or nodes.size() >= target_nodes - 4
		):
			_add_node(best_candidate)
		else:
			# Relax only when the remaining space is genuinely full.
			_add_node(best_candidate)


func _build_connected_skeleton() -> void:
	# Prim-style nearest growth makes one connected base web. Crossing edges
	# are avoided whenever there is a reasonable non-crossing alternative.
	var connected: Array = [0]
	var unconnected: Array = []
	for node_id in range(1, nodes.size()):
		unconnected.append(node_id)

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


func _close_all_dead_ends() -> void:
	# A branch is never allowed to remain a gameplay trap. Leaves are tied
	# back into the existing network until every road point has degree >= 2.
	var safety := nodes.size() * 12

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
	var attempts := nodes.size() * 40

	while _edge_count() < desired_edges and attempts > 0:
		attempts -= 1
		var a := _rng.randi_range(0, nodes.size() - 1)
		if adjacency[a].size() >= MAX_DEGREE:
			continue

		var nearby := _nearby_candidates(a)
		if nearby.is_empty():
			continue

		var b: int = int(nearby[_rng.randi_range(0, nearby.size() - 1)])
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

	# Start at actual junctions first. Degree-2 points disappear into a single
	# flowing visible road strand.
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

	# Any remaining edges belong to closed all-degree-2 loops.
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
		var next := second if first == previous else first
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
		var next := second if first == previous else first

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

		var p0 := p1
		var p3 := p2

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
		var point := 0.5 * (
			2.0 * p1
			+ (-p0 + p2) * t
			+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
		)
		points.append(point)

	return points


func _choose_far_apart_points() -> void:
	# Diameter approximation on graph distance. A and B are ordinary road
	# points inside the network, never artificial terminal branches.
	var first := _farthest_node_from(0)
	start_node = _farthest_node_from(first)
	destination_node = _farthest_node_from(start_node)


func _farthest_node_from(source: int) -> int:
	var farthest := source
	var farthest_length := -1.0

	for candidate in range(nodes.size()):
		if candidate == source:
			continue

		var path := shortest_path(source, candidate)
		if path.is_empty():
			continue

		var path_length := _path_length(path)
		if path_length > farthest_length:
			farthest_length = path_length
			farthest = candidate

	return farthest


func _path_length(path: Array) -> float:
	var result := 0.0
	for index in range(path.size() - 1):
		result += nodes[int(path[index])].distance_to(
			nodes[int(path[index + 1])]
		)
	return result


func _first_leaf() -> int:
	for node_id in range(nodes.size()):
		if adjacency[node_id].size() < 2:
			return node_id
	return -1


func _best_loop_target(leaf: int, require_no_crossing: bool) -> int:
	var best := -1
	var best_score := INF

	for candidate in range(nodes.size()):
		if candidate == leaf:
			continue
		if adjacency[leaf].has(candidate):
			continue
		if adjacency[candidate].size() >= MAX_DEGREE:
			continue

		var distance := nodes[leaf].distance_to(nodes[candidate])
		if distance > LOOP_SEARCH_DISTANCE:
			continue
		if require_no_crossing and _edge_would_cross(leaf, candidate):
			continue

		# Avoid closing a leaf straight back to the other end of the same tiny
		# local wedge when a broader loop is available.
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

		var distance := nodes[node_id].distance_to(nodes[candidate])
		if distance > LOOP_SEARCH_DISTANCE:
			continue

		scored.append([candidate, distance])

	scored.sort_custom(
		func(a: Array, b: Array) -> bool:
			return float(a[1]) < float(b[1])
	)

	var result: Array = []
	for index in range(mini(6, scored.size())):
		result.append(int(scored[index][0]))
	return result


func _nearest_node_distance(point: Vector2) -> float:
	if nodes.is_empty():
		return INF

	var result := INF
	for existing in nodes:
		result = minf(result, point.distance_to(existing))
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

	return ua > 0.02 and ua < 0.98 and ub > 0.02 and ub < 0.98


func _edge_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]
