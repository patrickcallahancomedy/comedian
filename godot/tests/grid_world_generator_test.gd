extends SceneTree

const GENERATOR = preload("res://scripts/drive/grid_world_generator.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("GRID WORLD GENERATOR TEST START")

	var first = GENERATOR.new()
	var second = GENERATOR.new()

	first.generate(20260928)
	second.generate(20260928)

	_check(
		first.nodes == second.nodes,
		"Same seed produced different node positions"
	)
	_check(
		first.adjacency == second.adjacency,
		"Same seed produced different road connections"
	)
	_check(
		first.edge_classes == second.edge_classes,
		"Same seed produced different road classes"
	)

	_check(
		first.neighborhood_nodes.size()
		== first.NEIGHBORHOOD_INTERSECTIONS,
		"Neighborhood is not the 10x10 / ~100 intersection tier"
	)
	_check(
		first.city_nodes.size() == first.CITY_INTERSECTIONS,
		"City is not the ~50 intersection tier"
	)
	_check(
		first.city_rect.size.x > first.neighborhood_rect.size.x
		and first.city_rect.size.y > first.neighborhood_rect.size.y,
		"City does not occupy a larger physical footprint"
	)

	_check(
		first.home_node >= 0
		and first.neighborhood_nodes.has(first.home_node),
		"Point A is not a road point inside the neighborhood"
	)
	_check(
		first.venue_block.size
		== Vector2i(first.CITY_SPACING, first.CITY_SPACING),
		"Point B is not exactly one full city block"
	)
	_check(
		_venue_block_has_four_road_sides(first),
		"Venue block is not bounded by city roads on all four sides"
	)
	_check(
		first.venue_access_node >= 0,
		"Venue block has no road access node"
	)

	if first.uses_highway:
		_check(
			_highway_avoids_local_regions(first),
			"Highway passes through the neighborhood or city street grid"
		)
		_check(
			_highway_spans_local_extents(first),
			"Highway no longer spans the far extents of the local regions"
		)

	var route: Array = first.shortest_path(
		first.home_node,
		first.venue_access_node
	)
	_check(
		not route.is_empty(),
		"No connected route exists from A to the venue block"
	)

	var reachable: Array = first.all_nodes_reachable_from(
		first.home_node
	)
	_check(
		reachable.size() == first.nodes.size(),
		"Generated road systems are not one connected graph"
	)

	var dead_ends: int = 0
	for node_id in range(first.nodes.size()):
		if (
			first.adjacency[node_id].size() < 2
			and not first.highway_nodes.has(node_id)
		):
			dead_ends += 1
			print(
				"UNEXPECTED DEAD END: ",
				node_id,
				" @ ",
				first.nodes[node_id],
				" connector=",
				first.connector_nodes.has(node_id)
			)
	_check(
		dead_ends == 0,
		"Generated map contains terminal wrong-turn roads away from highway continuations"
	)

	if first.uses_highway:
		_check(
			first.highway_nodes.size() == 2
			and first.adjacency[int(first.highway_nodes[0])].size() == 1
			and first.adjacency[int(first.highway_nodes[1])].size() == 1,
			"Highway does not continue past both interchanges"
		)

	var off_grid_edges: int = 0
	for a in range(first.nodes.size()):
		for b_value in first.adjacency[a]:
			var b: int = int(b_value)
			if b <= a:
				continue

			var pa: Vector2i = first.nodes[a]
			var pb: Vector2i = first.nodes[b]

			if pa.x != pb.x and pa.y != pb.y:
				off_grid_edges += 1

	_check(
		off_grid_edges == 0,
		"Road generator produced non-grid road geometry"
	)

	var outside_world: int = 0
	for point_value in first.nodes:
		var point: Vector2i = point_value
		if (
			point.x < 0
			or point.y < 0
			or point.x >= first.GRID_SIZE
			or point.y >= first.GRID_SIZE
		):
			outside_world += 1

	_check(
		outside_world == 0,
		"Generated road node escaped the 500x500 world"
	)

	if first.uses_highway:
		_check(
			first.highway_nodes.size() == 2,
			"Highway does not expose two straight continuation endpoints"
		)
		if first.highway_nodes.size() == 2:
			var first_highway_a: Vector2i = first.nodes[int(first.highway_nodes[0])]
			var first_highway_b: Vector2i = first.nodes[int(first.highway_nodes[1])]
			_check(
				first_highway_a.x == first_highway_b.x
				or first_highway_a.y == first_highway_b.y,
				"Highway endpoints are not grid-aligned"
			)
	else:
		_check(
			first.highway_nodes.is_empty(),
			"Surface-only map still generated highway nodes"
		)

	var highway_maps: int = 0
	var highways_with_turns: int = 0
	var same_corner_maps: int = 0

	for test_seed in range(1, 25):
		var candidate = GENERATOR.new()
		candidate.generate(test_seed)

		if candidate.uses_highway:
			highway_maps += 1

			if candidate.highway_nodes.size() != 2:
				highways_with_turns += 1
			else:
				var highway_a: Vector2i = candidate.nodes[
					int(candidate.highway_nodes[0])
				]
				var highway_b: Vector2i = candidate.nodes[
					int(candidate.highway_nodes[1])
				]
				if highway_a.x != highway_b.x and highway_a.y != highway_b.y:
					highways_with_turns += 1

		var neighborhood_center: Vector2 = Vector2(
			candidate.neighborhood_rect.get_center()
		)
		var city_center: Vector2 = Vector2(
			candidate.city_rect.get_center()
		)
		var world_midpoint: float = float(candidate.GRID_SIZE) * 0.5

		var same_horizontal_half: bool = (
			(neighborhood_center.x < world_midpoint)
			== (city_center.x < world_midpoint)
		)
		var same_vertical_half: bool = (
			(neighborhood_center.y < world_midpoint)
			== (city_center.y < world_midpoint)
		)

		if same_horizontal_half and same_vertical_half:
			same_corner_maps += 1

	_check(
		same_corner_maps == 0,
		"Neighborhood and city were generated in the same corner"
	)
	_check(
		highway_maps >= 22,
		"Different-corner placement is not producing highway-heavy maps"
	)
	_check(
		highways_with_turns == 0,
		"Generated highway contains a turn"
	)

	var packed: PackedScene = load(
		"res://scenes/drive/grid_world_prototype.tscn"
	) as PackedScene
	_check(
		packed != null,
		"Grid world prototype scene failed to load"
	)

	if packed != null:
		var scene: Node = packed.instantiate()
		root.add_child(scene)

		_check(
			scene.get_node_or_null("Map") != null,
			"Map prototype has no map node"
		)
		_check(
			scene.find_child("PlayerCar", true, false) == null,
			"Map-only prototype unexpectedly contains a player car"
		)

		scene.free()

	_finish()


func _highway_avoids_local_regions(network) -> bool:
	if network.highway_nodes.size() != 2:
		return false

	var a: Vector2i = network.nodes[int(network.highway_nodes[0])]
	var b: Vector2i = network.nodes[int(network.highway_nodes[1])]

	return (
		not _segment_enters_rect(a, b, network.neighborhood_rect)
		and not _segment_enters_rect(a, b, network.city_rect)
	)


func _segment_enters_rect(
	a: Vector2i,
	b: Vector2i,
	rect: Rect2i
) -> bool:
	if a.y == b.y:
		var y: int = a.y
		if y <= rect.position.y or y >= rect.end.y:
			return false

		var segment_left: int = mini(a.x, b.x)
		var segment_right: int = maxi(a.x, b.x)
		return (
			segment_right > rect.position.x
			and segment_left < rect.end.x
		)

	if a.x == b.x:
		var x: int = a.x
		if x <= rect.position.x or x >= rect.end.x:
			return false

		var segment_top: int = mini(a.y, b.y)
		var segment_bottom: int = maxi(a.y, b.y)
		return (
			segment_bottom > rect.position.y
			and segment_top < rect.end.y
		)

	return true


func _highway_spans_local_extents(network) -> bool:
	if network.highway_nodes.size() != 2:
		return false

	var a: Vector2i = network.nodes[int(network.highway_nodes[0])]
	var b: Vector2i = network.nodes[int(network.highway_nodes[1])]

	if a.y == b.y:
		var highway_left: int = mini(a.x, b.x)
		var highway_right: int = maxi(a.x, b.x)
		var region_left: int = mini(
			network.neighborhood_rect.position.x,
			network.city_rect.position.x
		)
		var region_right: int = maxi(
			network.neighborhood_rect.end.x,
			network.city_rect.end.x
		)
		return (
			highway_left <= region_left
			and highway_right >= region_right
		)

	if a.x == b.x:
		var highway_top: int = mini(a.y, b.y)
		var highway_bottom: int = maxi(a.y, b.y)
		var region_top: int = mini(
			network.neighborhood_rect.position.y,
			network.city_rect.position.y
		)
		var region_bottom: int = maxi(
			network.neighborhood_rect.end.y,
			network.city_rect.end.y
		)
		return (
			highway_top <= region_top
			and highway_bottom >= region_bottom
		)

	return false


func _venue_block_has_four_road_sides(network) -> bool:
	var top_left: Vector2i = network.venue_block.position
	var top_right: Vector2i = (
		network.venue_block.position
		+ Vector2i(network.venue_block.size.x, 0)
	)
	var bottom_left: Vector2i = (
		network.venue_block.position
		+ Vector2i(0, network.venue_block.size.y)
	)
	var bottom_right: Vector2i = network.venue_block.end

	var tl: int = _find_node(network, top_left)
	var tr: int = _find_node(network, top_right)
	var bl: int = _find_node(network, bottom_left)
	var br: int = _find_node(network, bottom_right)

	if tl < 0 or tr < 0 or bl < 0 or br < 0:
		return false

	return (
		network.adjacency[tl].has(tr)
		and network.adjacency[tl].has(bl)
		and network.adjacency[tr].has(br)
		and network.adjacency[bl].has(br)
	)


func _find_node(network, point: Vector2i) -> int:
	for node_id in range(network.nodes.size()):
		var candidate: Vector2i = network.nodes[node_id]
		if candidate == point:
			return node_id
	return -1


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		print("FAIL: ", message)


func _finish() -> void:
	if failures.is_empty():
		print("GRID WORLD GENERATOR TEST PASS")
		quit(0)
		return

	print("GRID WORLD GENERATOR TEST FAIL")
	for failure in failures:
		print(" - ", failure)
	quit(1)
