class_name ProceduralRoadNetwork
extends RefCounted

## Seeded organic road graph for COMEDIAN.
## Roads grow from existing roads, then nearby branches reconnect to create loops.
## No neighborhood/highway/city modules exist here.

const WORLD_RECT := Rect2(80.0, 80.0, 1040.0, 1320.0)
const TARGET_NODE_COUNT := 58
const MIN_SPACING := 72.0
const MIN_SEGMENT_LENGTH := 88.0
const MAX_SEGMENT_LENGTH := 150.0
const MAX_DEGREE := 4
const LOOP_MAX_DISTANCE := 190.0
const CURVE_SAMPLES := 8

var seed := 0
var nodes: Array = []
var adjacency: Array = []
var edge_curves: Dictionary = {}
var start_node := -1
var destination_node := -1

var _rng := RandomNumberGenerator.new()
var _arrival_direction: Array = []


func generate(seed_value: int, target_nodes: int = TARGET_NODE_COUNT) -> void:
	seed = seed_value
	_rng.seed = seed_value
	nodes.clear()
	adjacency.clear()
	edge_curves.clear()
	_arrival_direction.clear()

	var root := WORLD_RECT.get_center()
	_add_node(root, Vector2.UP)

	var frontier: Array = [0]
	var attempts := 0
	var max_attempts := target_nodes * 90

	while nodes.size() < target_nodes and attempts < max_attempts:
		attempts += 1
		if frontier.is_empty():
			frontier.append(_rng.randi_range(0, nodes.size() - 1))

		var parent_slot := _rng.randi_range(0, frontier.size() - 1)
		var parent_id: int = frontier[parent_slot]
		if adjacency[parent_id].size() >= MAX_DEGREE:
			frontier.remove_at(parent_slot)
			continue

		var base_direction: Vector2 = _arrival_direction[parent_id]
		if base_direction.length_squared() < 0.01:
			base_direction = Vector2.UP

		var angle_choices := [
			deg_to_rad(-78.0),
			deg_to_rad(-52.0),
			deg_to_rad(-30.0),
			deg_to_rad(-12.0),
			0.0,
			deg_to_rad(12.0),
			deg_to_rad(30.0),
			deg_to_rad(52.0),
			deg_to_rad(78.0),
		]
		var angle: float = angle_choices[
			_rng.randi_range(0, angle_choices.size() - 1)
		]
		var direction: Vector2 = base_direction.rotated(angle).normalized()
		var length: float = _rng.randf_range(MIN_SEGMENT_LENGTH, MAX_SEGMENT_LENGTH)
		var candidate: Vector2 = nodes[parent_id] + direction * length

		if not WORLD_RECT.grow(-24.0).has_point(candidate):
			continue
		if _too_close_to_existing(candidate):
			continue
		if _would_cross_existing(parent_id, candidate):
			continue

		var new_id: int = _add_node(candidate, direction)
		_add_edge(parent_id, new_id)

		if adjacency[parent_id].size() >= MAX_DEGREE:
			frontier.erase(parent_id)
		if not frontier.has(new_id):
			frontier.append(new_id)

		# Keep older branches alive sometimes so the growth behaves more like
		# roots/mycelium than a single random walk.
		if _rng.randf() < 0.36 and not frontier.has(parent_id):
			frontier.append(parent_id)

	_add_loop_connections()
	_choose_far_apart_endpoints()


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
		var current: int = unvisited[0]
		var best_distance: float = float(distances[current])

		for slot in range(1, unvisited.size()):
			var candidate: int = unvisited[slot]
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

		for neighbor in adjacency[current]:
			if not unvisited.has(neighbor):
				continue
			var alt: float = best_distance + nodes[current].distance_to(nodes[neighbor])
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


func _add_node(position: Vector2, arrival_direction: Vector2) -> int:
	var node_id := nodes.size()
	nodes.append(position)
	adjacency.append([])
	_arrival_direction.append(arrival_direction.normalized())
	return node_id


func _add_edge(a: int, b: int) -> void:
	if a == b:
		return
	if adjacency[a].has(b):
		return

	adjacency[a].append(b)
	adjacency[b].append(a)

	var start: Vector2 = nodes[min(a, b)]
	var finish: Vector2 = nodes[max(a, b)]
	var delta: Vector2 = finish - start
	var normal: Vector2 = Vector2(-delta.y, delta.x).normalized()

	var curve_amount: float = _rng.randf_range(-0.12, 0.12) * delta.length()
	var control_one: Vector2 = start + delta * 0.34 + normal * curve_amount
	var control_two: Vector2 = start + delta * 0.68 + normal * curve_amount
	edge_curves[_edge_key(a, b)] = _sample_cubic(
		start,
		control_one,
		control_two,
		finish,
		CURVE_SAMPLES
	)


func _add_loop_connections() -> void:
	var candidates: Array = []
	for a in range(nodes.size()):
		if adjacency[a].size() >= MAX_DEGREE:
			continue
		for b in range(a + 1, nodes.size()):
			if adjacency[b].size() >= MAX_DEGREE:
				continue
			if adjacency[a].has(b):
				continue

			var distance: float = nodes[a].distance_to(nodes[b])
			if distance < MIN_SEGMENT_LENGTH * 0.75:
				continue
			if distance > LOOP_MAX_DISTANCE:
				continue
			candidates.append([a, b, distance])

	# Deterministic Fisher-Yates shuffle so the seed fully defines the map.
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary = candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = temporary

	for candidate in candidates:
		if _rng.randf() > 0.27:
			continue
		var a: int = candidate[0]
		var b: int = candidate[1]
		if adjacency[a].size() >= MAX_DEGREE or adjacency[b].size() >= MAX_DEGREE:
			continue
		if _edge_would_cross(a, b):
			continue
		_add_edge(a, b)


func _choose_far_apart_endpoints() -> void:
	var endpoints: Array = []
	for node_id in range(nodes.size()):
		if adjacency[node_id].size() == 1:
			endpoints.append(node_id)

	if endpoints.size() < 2:
		start_node = 0
		destination_node = nodes.size() - 1
		return

	# Prefer an A low in the world so the first screen feels like leaving home.
	start_node = endpoints[0]
	for endpoint in endpoints:
		if nodes[endpoint].y > nodes[start_node].y:
			start_node = endpoint

	var farthest := start_node
	var farthest_length := -1.0
	for endpoint in endpoints:
		if endpoint == start_node:
			continue
		var path: Array = shortest_path(start_node, endpoint)
		var path_length: float = _path_length(path)
		if path_length > farthest_length:
			farthest_length = path_length
			farthest = endpoint
	destination_node = farthest


func _path_length(path: Array) -> float:
	var result := 0.0
	for index in range(path.size() - 1):
		result += nodes[path[index]].distance_to(nodes[path[index + 1]])
	return result


func _too_close_to_existing(candidate: Vector2) -> bool:
	for point in nodes:
		if candidate.distance_to(point) < MIN_SPACING:
			return true
	return false


func _would_cross_existing(parent_id: int, candidate: Vector2) -> bool:
	for a in range(nodes.size()):
		for b in adjacency[a]:
			if b <= a:
				continue
			if a == parent_id or b == parent_id:
				continue
			if _segments_intersect(nodes[parent_id], candidate, nodes[a], nodes[b]):
				return true
	return false


func _edge_would_cross(a: int, b: int) -> bool:
	for c in range(nodes.size()):
		for d in adjacency[c]:
			if d <= c:
				continue
			if c == a or c == b or d == a or d == b:
				continue
			if _segments_intersect(nodes[a], nodes[b], nodes[c], nodes[d]):
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


func _sample_cubic(
	start: Vector2,
	control_one: Vector2,
	control_two: Vector2,
	finish: Vector2,
	samples: int
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(samples + 1):
		var t := float(index) / float(samples)
		var inverse := 1.0 - t
		points.append(
			start * inverse * inverse * inverse
			+ control_one * 3.0 * inverse * inverse * t
			+ control_two * 3.0 * inverse * t * t
			+ finish * t * t * t
		)
	return points


func _edge_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]
