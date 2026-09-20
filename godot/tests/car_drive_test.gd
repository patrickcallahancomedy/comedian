extends SceneTree

## DRIVE v0.9 structural smoke test.
## The player should experience one road: neighborhood -> connector -> eight-lane
## highway -> connector -> close venue approach.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DRIVE v0.9 TEST START")

	var packed := load("res://scenes/drive/drive_module.tscn") as PackedScene
	_check(packed != null, "DRIVE scene failed to load")
	if packed == null:
		_finish()
		return

	var drive := packed.instantiate()
	get_root().add_child(drive)
	var car := drive.get_node_or_null("PlayerCar") as TextureRect
	var city = drive.get_node_or_null("CityMap")
	var start_button := drive.get_node_or_null("TouchControls/ForwardButton") as Button

	_check(car != null and car.texture != null, "Player car texture did not load")
	_check(city != null, "CityMap is missing")
	_check(start_button != null, "START button is missing")
	if city == null:
		drive.free()
		_finish()
		return

	_check(city.active_stage_id == "neighborhood", "Trip does not start in neighborhood")
	_check(city.steering_mode == "turn", "Neighborhood should use turn steering")
	_check(city.drive_speed < 680.0, "Neighborhood was not slowed down")
	_check(city.intersection_spacing >= 1800.0, "Neighborhood blocks unexpectedly shortened")
	_check_no_dead_ends(city, "Neighborhood")

	city._move_forward()
	_check(city.section_started, "START did not begin the trip")
	_check(not start_button.visible, "START did not disappear after departure")

	# Crossing the first invisible gate should animate instead of hard-swapping.
	city._begin_connector(1)
	_check(city.transition_active, "Neighborhood gate did not start connector")
	_check(city.active_stage_id == "neighborhood", "Connector hard-swapped the stage")
	_check(city.transition_to_road_width > city.transition_from_road_width, "First connector does not widen road")
	_check(city.transition_to_car_scale < city.transition_from_car_scale, "First connector does not zoom car out")
	city._process_connector(city.transition_duration + 0.01)

	_check(city.active_stage_id == "highway", "Connector did not arrive on highway")
	_check(city.steering_mode == "lane", "Highway should use lane steering")
	_check(city.lane_count == 8, "Highway should have eight lanes")
	_check(city.lane_traffic.size() > 0, "Highway has no traffic")
	_check(int(city.active_profile.get("exit_lane", -1)) == 7, "Highway exit is not right-most lane")

	var old_gate: float = city.lane_gate_distance
	city.current_lane = 3
	city.target_lane = 3
	city.lane_visual_offset = city._lane_center_offset(3)
	city.lane_distance = old_gate
	city._process_lane_mode(0.0)
	_check(city.active_stage_id == "highway", "Wrong highway lane advanced")
	_check(city.lane_gate_distance > old_gate, "Missed exit did not extend highway")

	city.current_lane = 7
	city.target_lane = 7
	city.lane_visual_offset = city._lane_center_offset(7)
	city.lane_distance = city.lane_gate_distance
	city._process_lane_mode(0.0)
	_check(city.transition_active, "Right-most highway lane did not enter connector")
	_check(city.active_stage_id == "highway", "Second connector hard-swapped stage")
	_check(city.transition_to_car_scale > city.transition_from_car_scale, "Second connector does not zoom car in")
	city._process_connector(city.transition_duration + 0.01)

	_check(city.active_stage_id == "downtown", "Second connector did not reach venue approach")
	_check(city.steering_mode == "approach", "Final city section should be automatic approach")
	_check(city.lane_count == 1, "Venue approach should be one broad road")
	_check(city.road_width > 300.0, "Venue approach road does not dominate screen")
	_check(city.car_scale >= 1.5, "Venue approach car is not close enough")

	# The final gate is the parking space and should finish the drive.
	city.lane_distance = city.lane_gate_distance
	city._process_lane_mode(0.0)
	_check(city.drive_complete, "Parking-space gate did not finish drive")

	drive.free()
	_finish()


func _check_no_dead_ends(city, label: String) -> void:
	var degree: Dictionary = {}
	for point in city.turn_intersections:
		degree[point] = 0
	for road in city.turn_roads:
		var a: Vector2i = road["from"]
		var b: Vector2i = road["to"]
		degree[a] = int(degree.get(a, 0)) + 1
		degree[b] = int(degree.get(b, 0)) + 1
	for point in degree.keys():
		_check(int(degree[point]) >= 2, "%s generated a dead end" % label)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("DRIVE v0.9 TEST PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("DRIVE v0.9 TEST FAIL count=%d" % failures.size())
	quit(1)
