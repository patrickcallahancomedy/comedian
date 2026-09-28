extends SceneTree

const NETWORK = preload("res://scripts/drive/procedural_road_network.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("PROCEDURAL ROAD A-B TEST START")

	var first = NETWORK.new()
	var second = NETWORK.new()
	first.generate(1337)
	second.generate(1337)

	_check(first.nodes.size() >= 35, "Generator produced too few road nodes")
	_check(
		first.nodes.size() == second.nodes.size(),
		"Same seed produced different node counts"
	)
	_check(
		first.nodes == second.nodes,
		"Same seed produced different road geometry"
	)
	_check(
		first.start_node >= 0 and first.destination_node >= 0,
		"Generator did not choose A and B"
	)

	var visited := _reachable_nodes(first, first.start_node)
	_check(
		visited.size() == first.nodes.size(),
		"Generated road network is not fully connected"
	)

	var route: Array = first.shortest_path(
		first.start_node,
		first.destination_node
	)
	_check(route.size() >= 5, "A-to-B route is too short to be meaningful")

	var alternate_data := _find_reroutable_turn(first, route)
	_check(
		not alternate_data.is_empty(),
		"Seeded map has no usable wrong-turn junction"
	)
	if not alternate_data.is_empty():
		var alternate: int = int(alternate_data["alternate"])
		var reroute: Array = first.shortest_path(
			alternate,
			first.destination_node
		)
		_check(
			not reroute.is_empty(),
			"A valid wrong turn cannot reroute to B"
		)

	var packed := load(
		"res://scenes/drive/procedural_drive_ab.tscn"
	) as PackedScene
	_check(packed != null, "Procedural A-to-B scene failed to load")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	var drive = scene.get_node("RoadWorld")
	drive.world_seed = 1337
	root.add_child(scene)

	_check(
		drive.network.nodes == first.nodes,
		"Drivable scene is not using the seeded road generator"
	)
	_check(
		drive.current_node == drive.network.start_node,
		"Car does not begin at Point A"
	)
	_check(
		drive.destination_node == drive.network.destination_node,
		"Drivable scene destination is not Point B"
	)
	_check(
		is_equal_approx(drive.CAR_SCALE, 0.72),
		"Prototype does not use one fixed car scale"
	)
	_check(
		drive.has_signal("trip_finished"),
		"Prototype no longer exposes the drive completion contract"
	)

	drive._start_drive()
	_check(drive.started, "START did not begin continuous driving")
	_check(drive.next_node >= 0, "Drive did not select an outgoing road")

	if not alternate_data.is_empty():
		var junction: int = int(alternate_data["junction"])
		var previous: int = int(alternate_data["previous"])
		var alternate: int = int(alternate_data["alternate"])
		var turn_sign: int = int(alternate_data["turn_sign"])

		drive.current_node = junction
		drive.previous_node = previous
		drive.next_node = -1
		drive.destination_node = drive.network.destination_node
		drive.visual_world_position = drive.network.nodes[junction]
		drive.move_to = drive.visual_world_position
		drive.heading = (
			drive.network.nodes[junction]
			- drive.network.nodes[previous]
		).normalized()
		drive.queued_turn = turn_sign
		drive.missed_turns = 0
		drive.current_edge_points = PackedVector2Array()
		drive._begin_next_edge()

		_check(
			drive.next_node != int(alternate_data["expected"])
			and drive.network.neighbors(junction).has(drive.next_node),
			"Queued L/R did not take a connected non-route road"
		)
		_check(
			drive.missed_turns == 1,
			"Wrong valid turn was not counted for rerouting"
		)
		_check(
			not drive.current_route_after_edge().is_empty(),
			"GPS did not reroute after the wrong turn"
		)

	scene.free()
	_finish()


func _reachable_nodes(network, start_id: int) -> Array:
	var visited: Array = [start_id]
	var queue: Array = [start_id]

	while not queue.is_empty():
		var current: int = int(queue.pop_front())
		for neighbor_value in network.neighbors(current):
			var neighbor: int = int(neighbor_value)
			if visited.has(neighbor):
				continue
			visited.append(neighbor)
			queue.append(neighbor)

	return visited


func _find_reroutable_turn(network, route: Array) -> Dictionary:
	for index in range(1, route.size() - 1):
		var previous: int = int(route[index - 1])
		var junction: int = int(route[index])
		var expected: int = int(route[index + 1])
		var incoming: Vector2 = (
			network.nodes[junction] - network.nodes[previous]
		).normalized()
		var expected_outgoing: Vector2 = (
			network.nodes[expected] - network.nodes[junction]
		).normalized()
		var expected_cross: float = (
			incoming.x * expected_outgoing.y
			- incoming.y * expected_outgoing.x
		)
		var expected_dot: float = clampf(
			incoming.dot(expected_outgoing),
			-1.0,
			1.0
		)
		var expected_angle: float = atan2(expected_cross, expected_dot)
		var expected_sign := 0
		if expected_angle < -0.28:
			expected_sign = -1
		elif expected_angle > 0.28:
			expected_sign = 1

		for candidate_value in network.neighbors(junction):
			var candidate: int = int(candidate_value)
			if candidate == previous or candidate == expected:
				continue

			var outgoing: Vector2 = (
				network.nodes[candidate] - network.nodes[junction]
			).normalized()
			var cross: float = incoming.x * outgoing.y - incoming.y * outgoing.x
			var dot: float = clampf(incoming.dot(outgoing), -1.0, 1.0)
			var angle: float = atan2(cross, dot)

			if absf(angle) <= 0.28:
				continue

			var turn_sign := -1 if angle < 0.0 else 1
			if turn_sign == expected_sign:
				continue
			if network.shortest_path(candidate, network.destination_node).is_empty():
				continue

			return {
				"previous": previous,
				"junction": junction,
				"expected": expected,
				"alternate": candidate,
				"turn_sign": turn_sign,
			}

	return {}


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		print("FAIL: ", message)


func _finish() -> void:
	if failures.is_empty():
		print("PROCEDURAL ROAD A-B TEST PASS")
		quit(0)
		return

	print("PROCEDURAL ROAD A-B TEST FAIL")
	for failure in failures:
		print(" - ", failure)
	quit(1)
