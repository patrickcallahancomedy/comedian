extends SceneTree

const MAP = preload("res://scripts/drive/drive_world_map.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DRIVE WORLD REBUILD TEST START")

	_check(MAP.NEIGHBORHOOD_NODES.size() == 9, "Neighborhood graph is incomplete")
	_check(MAP.CITY_NODES.size() == 9, "City graph is incomplete")
	_check(MAP.HIGHWAY_LANES == 4, "Highway is not four lanes")
	_check(
		MAP.OPPOSITE_HIGHWAY_RECT.position.y < MAP.HIGHWAY_RECT.position.y,
		"Divided highway carriageways are not physically separate"
	)

	var neighborhood_route: Array[String] = MAP.shortest_path(
		"neighborhood",
		MAP.NEIGHBORHOOD_START,
		MAP.NEIGHBORHOOD_GATE
	)
	_check(
		neighborhood_route == ["n22", "n21", "n20", "n10", "n00"],
		"Neighborhood route is not the intended road path"
	)

	var city_route: Array[String] = MAP.shortest_path(
		"city",
		MAP.CITY_ENTRY,
		MAP.CITY_PARKING_NODE
	)
	_check(
		city_route == ["c20", "c10", "c11", "c21", "c22"],
		"City route is not the intended venue approach"
	)

	var onramp := MAP.onramp_points()
	_check(onramp.size() >= 20, "On-ramp curve is undersampled")
	_check(
		onramp[0] == MAP.node_position("neighborhood", MAP.NEIGHBORHOOD_GATE),
		"On-ramp does not begin at the neighborhood road"
	)
	_check(
		onramp[onramp.size() - 1] == MAP.highway_entry_point(),
		"On-ramp does not merge into lane 4"
	)

	var packed := load("res://scenes/drive/drive_module.tscn") as PackedScene
	_check(packed != null, "Drive scene failed to load")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	var drive = scene.get_node("CityMap")
	var navigation = scene.get_node("Navigation")
	var traffic = scene.get_node("TrafficCars")

	_check(drive != null, "Rebuilt drive controller missing")
	_check(navigation != null, "Rebuilt GPS navigation missing")
	_check(
		drive.get_script().resource_path.ends_with("drive_world_controller.gd"),
		"Drive scene is not using the rebuilt controller"
	)
	_check(
		navigation.get_script().resource_path.ends_with("drive_world_navigation.gd"),
		"Drive scene is not using the rebuilt navigation"
	)
	_check(traffic.get_child_count() == 6, "Highway traffic car count changed")

	drive._start_drive()
	_check(drive.started, "Drive did not start")
	_check(drive.road_kind == "neighborhood", "Drive did not begin in neighborhood")
	_check(drive.local_node == "n21", "Neighborhood did not begin by driving straight")

	# Jump to the neighborhood gate and prove the curve is the actual movement.
	drive.local_node = MAP.NEIGHBORHOOD_GATE
	drive.previous_local_node = "n10"
	drive.heading = Vector2i.LEFT
	drive.visual_world_position = MAP.node_position("neighborhood", MAP.NEIGHBORHOOD_GATE)
	drive.move_from = drive.visual_world_position
	drive.move_to = drive.visual_world_position
	drive.visual_scale = 1.0
	drive.scale_from = 1.0
	drive._begin_local_step()
	_check(drive.road_kind == "onramp", "Neighborhood gate did not enter on-ramp")
	_check(
		drive.path_points == MAP.onramp_points(),
		"Movement on-ramp does not use the world-map curve"
	)

	var ramp_guard := 0
	while drive.road_kind == "onramp" and ramp_guard < 40:
		drive.visual_world_position = drive.move_to
		drive.visual_scale = drive.scale_to
		drive.move_from = drive.visual_world_position
		drive.scale_from = drive.visual_scale
		drive._begin_next_step()
		ramp_guard += 1

	_check(ramp_guard < 40, "On-ramp traversal did not terminate")
	_check(drive.road_kind == "highway", "On-ramp did not enter highway")
	_check(
		drive.highway_lane == MAP.HIGHWAY_ENTRY_LANE,
		"On-ramp did not enter the rightmost lane"
	)
	_check(
		is_equal_approx(drive.visual_scale, drive.HIGHWAY_PLAYER_SCALE),
		"Car did not reach highway scale by the merge"
	)

	# Highway steering remains immediate.
	drive._turn_left()
	_check(
		drive.highway_lane == MAP.HIGHWAY_ENTRY_LANE - 1,
		"Highway left input did not change lanes"
	)
	drive._turn_right()
	_check(
		drive.highway_lane == MAP.HIGHWAY_ENTRY_LANE,
		"Highway right input did not return to lane 4"
	)

	# Collision is based on visible world overlap.
	drive.highway_lane = drive.HIGHWAY_TRAFFIC_LANES[0]
	drive.queued_highway_lane = drive.highway_lane
	drive.visual_world_position = MAP.highway_lane_center(
		drive.highway_lane,
		900.0
	)
	drive.highway_traffic_offsets[0] = 0.0
	var bumps_before: int = drive.bumps
	drive._update_highway_traffic(0.0)
	_check(drive.bumps == bumps_before + 1, "Visible highway collision did not register")
	_check(
		drive.highway_collision_slow_remaining > 0.0,
		"Collision did not trigger slowdown feedback"
	)

	# City destination requires an explicit right turn into the lot.
	drive.road_kind = "city"
	drive.local_area = "city"
	drive.local_node = MAP.CITY_PARKING_NODE
	drive.previous_local_node = "c21"
	drive.heading = Vector2i.DOWN
	drive.queued_turn = 0
	drive.visual_world_position = MAP.node_position("city", MAP.CITY_PARKING_NODE)
	drive.move_from = drive.visual_world_position
	drive.move_to = drive.visual_world_position
	drive.blocked_this_step = false
	drive._begin_local_step()
	_check(drive.blocked_this_step, "City auto-entered the parking lot")

	drive._turn_right()
	_check(drive.road_kind == "parking", "Right turn did not enter parking lot")
	_check(drive.move_to == MAP.PARKING_ENTRY, "Parking entry does not use driveway")

	drive.visual_world_position = drive.move_to
	drive.move_from = drive.visual_world_position
	drive._begin_next_step()
	_check(drive.parking_phase == 1, "Parking did not advance to aisle")

	drive.visual_world_position = drive.move_to
	drive.move_from = drive.visual_world_position
	drive._begin_next_step()
	_check(drive.blocked_this_step, "Parking aisle did not wait for player choice")

	drive._turn_right()
	_check(
		drive.move_to == MAP.PARKING_RIGHT_SPACE,
		"Parking right input did not select open right space"
	)

	drive.visual_world_position = drive.move_to
	drive.move_from = drive.visual_world_position
	drive._begin_next_step()
	_check(drive.drive_complete, "Parking did not complete the drive")

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
		print("DRIVE WORLD REBUILD TEST PASS")
		quit(0)
		return

	print("DRIVE WORLD REBUILD TEST FAIL")
	for failure in failures:
		print(" - ", failure)
	quit(1)
