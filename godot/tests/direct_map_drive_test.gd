extends SceneTree

const GENERATOR = preload("res://scripts/drive/grid_world_generator.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DIRECT MAP DRIVE TEST START")

	var packed: PackedScene = load(
		"res://scenes/drive/direct_map_drive_prototype.tscn"
	) as PackedScene
	_check(packed != null, "Direct-map drive scene failed to load")
	if packed == null:
		_finish()
		return

	var scene: Node = packed.instantiate()
	var world: Control = scene.get_node("World")
	world.world_seed = 20260928
	root.add_child(scene)

	var expected = GENERATOR.new()
	expected.generate(20260928)

	_check(
		world.generator.nodes == expected.nodes,
		"Driving prototype changed generated node geometry"
	)
	_check(
		world.generator.adjacency == expected.adjacency,
		"Driving prototype changed generated road connections"
	)
	_check(
		world.generator.edge_classes == expected.edge_classes,
		"Driving prototype changed generated road classes"
	)
	_check(
		world.current_node == world.generator.home_node,
		"Car does not begin at generated Point A"
	)
	_check(
		world.route == world.generator.shortest_path(
			world.generator.home_node,
			world.generator.venue_access_node
		),
		"Driving route is not using the generated graph"
	)

	world._refresh_layout()
	var home_screen: Vector2 = world._world_to_screen(
		Vector2(world.generator.nodes[world.generator.home_node])
	)
	_check(
		home_screen.distance_to(world.player_screen_center) < 0.01,
		"Camera is not centered on the actual generated car position"
	)

	var edge_a: int = world.generator.home_node
	var edge_b: int = int(world.generator.adjacency[edge_a][0])
	var world_distance: float = Vector2(
		world.generator.nodes[edge_a]
	).distance_to(
		Vector2(world.generator.nodes[edge_b])
	)
	var screen_distance: float = world._world_to_screen(
		Vector2(world.generator.nodes[edge_a])
	).distance_to(
		world._world_to_screen(
			Vector2(world.generator.nodes[edge_b])
		)
	)
	_check(
		is_equal_approx(
			screen_distance,
			world_distance * world.CAMERA_SCALE
		),
		"Camera does more than uniformly magnify the generated map"
	)

	_check(
		world._road_world_width(
			world.generator.RoadClass.HIGHWAY
		) > world._road_world_width(
			world.generator.RoadClass.NEIGHBORHOOD
		),
		"Highway is not visually wider than local streets"
	)
	_check(
		world._speed_for_class(
			world.generator.RoadClass.HIGHWAY
		) > world._speed_for_class(
			world.generator.RoadClass.NEIGHBORHOOD
		),
		"Highway does not drive faster than local streets"
	)

	world._start_drive()
	_check(world.started, "START did not begin driving")
	_check(world.target_node >= 0, "Drive did not enter generated road graph")

	var first_target: int = world.target_node
	world.segment_progress = 1.0
	world.visual_world_position = world.segment_end
	world._arrive_at_target()
	_check(
		world.current_node == first_target,
		"Car did not arrive at the exact generated intersection"
	)

	# Prove the controller can traverse the generated route all the way to B
	# without changing maps or swapping to a replacement highway.
	var safety: int = 0
	while (
		world.current_node != world.generator.venue_access_node
		and safety < 500
	):
		safety += 1
		var remaining: Array = world.generator.shortest_path(
			world.current_node,
			world.generator.venue_access_node
		)
		if remaining.size() < 2:
			break
		world._begin_segment(int(remaining[1]))
		world.segment_progress = 1.0
		world.visual_world_position = world.segment_end
		world._arrive_at_target()

	_check(
		world.current_node == world.generator.venue_access_node,
		"Controller could not traverse the single generated graph to B"
	)
	_check(
		world.drive_complete,
		"Arriving at generated venue access did not finish the drive"
	)

	scene.free()
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		print("FAIL: ", message)


func _finish() -> void:
	if failures.is_empty():
		print("DIRECT MAP DRIVE TEST PASS")
		quit(0)
		return

	print("DIRECT MAP DRIVE TEST FAIL")
	for failure in failures:
		print(" - ", failure)
	quit(1)
