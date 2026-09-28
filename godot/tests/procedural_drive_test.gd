extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("PROCEDURAL DRIVE TEST START")

	var packed: PackedScene = load(
		"res://scenes/drive/procedural_drive_prototype.tscn"
	) as PackedScene
	_check(
		packed != null,
		"Procedural drive scene failed to load"
	)
	if packed == null:
		_finish()
		return

	var scene: Node = packed.instantiate()
	var world: Control = scene.get_node("World")
	world.world_seed = 20260928
	root.add_child(scene)

	_check(
		world.generator.seed == 20260928,
		"Procedural drive did not use the requested seed"
	)
	_check(
		world.current_node == world.generator.home_node,
		"Drive does not start at generated home"
	)
	_check(
		not world.route.is_empty(),
		"Generated drive has no route to venue"
	)
	_check(
		world.generator.uses_highway,
		"Test seed did not generate the expected highway"
	)
	_check(
		world.player_car.visible,
		"Player car is missing"
	)
	_check(
		not world.arrival_panel.visible,
		"Arrival panel is visible before driving"
	)

	world._start_drive()
	_check(
		world.started,
		"START did not begin procedural drive"
	)
	_check(
		world.target_node >= 0,
		"Drive did not choose an initial road segment"
	)

	var highway_a: int = int(world.generator.highway_nodes[0])
	var highway_b: int = int(world.generator.highway_nodes[1])

	world.current_node = highway_a
	world.previous_node = -1
	world.target_node = highway_b
	world.current_edge_class = world.generator.RoadClass.HIGHWAY
	world.segment_start = Vector2(world.generator.nodes[highway_a])
	world.segment_end = Vector2(world.generator.nodes[highway_b])
	world.visual_world_position = world.segment_start
	world.segment_progress = 1.0
	world.highway_lane = 1
	world.highway_lane_shift = world._lane_shift_for(1)
	world.highway_lane_shift_target = world.highway_lane_shift

	var missed_before: int = world.missed_turns
	world._advance_segment(0.0)
	_check(
		world.missed_turns == missed_before + 1,
		"Missing highway exit did not register"
	)
	_check(
		world.current_node == highway_a
		and world.target_node == highway_b,
		"Missing highway exit left the highway segment"
	)
	_check(
		is_equal_approx(world.segment_progress, 0.0),
		"Missing highway exit did not continue to the next highway pass"
	)
	_check(
		world.gps_title.text == "Missed exit",
		"GPS did not show missed-exit notice"
	)

	world.highway_lane = 2
	world.highway_lane_shift_target = world._lane_shift_for(2)
	world._turn_right()
	_check(
		world.highway_lane == world.HIGHWAY_EXIT_LANE,
		"Right input did not move into the highway exit lane"
	)

	world.segment_progress = 1.0
	world._advance_segment(0.0)
	_check(
		world.current_node == highway_b,
		"Exit lane did not leave highway at generated endpoint"
	)
	_check(
		world.current_edge_class != world.generator.RoadClass.HIGHWAY
		or world.target_node < 0,
		"Drive remained on highway after taking the exit"
	)

	_check(
		world._scale_for_class(
			world.generator.RoadClass.NEIGHBORHOOD
		) > world._scale_for_class(
			world.generator.RoadClass.CITY
		),
		"Neighborhood/city camera scales no longer reflect generated block sizes"
	)
	_check(
		world._speed_for_class(
			world.generator.RoadClass.HIGHWAY
		) > world._speed_for_class(
			world.generator.RoadClass.NEIGHBORHOOD
		),
		"Highway is not faster than neighborhood driving"
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
		print("PROCEDURAL DRIVE TEST PASS")
		quit(0)
		return

	print("PROCEDURAL DRIVE TEST FAIL")
	for failure in failures:
		print(" - ", failure)
	quit(1)
