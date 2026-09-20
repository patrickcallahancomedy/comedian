extends SceneTree

## DRIVE v0.11 structural smoke test.
## One connected road: smaller neighborhood -> widening connector -> 4-lane
## highway split -> shrinking connector -> turning city -> 2-lane parking street.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DRIVE v0.11 TEST START")

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
	_check(city.road_width < 90.0, "Neighborhood road is still too large")
	_check(city.intersection_spacing < 1200.0, "Neighborhood blocks are still oversized")
	_check(city.drive_speed < 500.0, "Neighborhood speed was not reduced")
	_check_no_dead_ends(city, "Neighborhood")

	city._move_forward()
	_check(city.section_started, "START did not begin the trip")
	_check(not start_button.visible, "START did not disappear after departure")

	# Literal connector: progress is distance, not elapsed transition time.
	city._load_stage(1, true)
	_check(city.active_stage_id == "connector_out", "First road chunk is not connector")
	_check(city.steering_mode == "connector", "Connector should be automatic road")
	var connector_start_width: float = city.road_width
	var connector_start_scale: float = city.car_scale
	city.lane_distance = city.lane_gate_distance * 0.5
	city._process_lane_mode(0.0)
	_check(city.road_width > connector_start_width, "Connector does not physically widen")
	_check(city.car_scale < connector_start_scale, "Connector does not zoom car out")
	city.lane_distance = city.lane_gate_distance
	city._process_lane_mode(0.0)

	_check(city.active_stage_id == "highway", "Connector did not feed highway")
	_check(city.steering_mode == "lane", "Highway should use lane steering")
	_check(city.lane_count == 4, "Highway should have four lanes")
	_check(int(city.active_profile.get("exit_lane", -1)) == 3, "Highway exit is not right-most lane")

	# Wrong lane passes the physical fork and stays on highway.
	var old_gate: float = city.lane_gate_distance
	city.current_lane = 2
	city.target_lane = 2
	city.lane_visual_offset = city._lane_center_offset(2)
	city.lane_distance = old_gate
	city._process_lane_mode(0.0)
	_check(city.active_stage_id == "highway", "Wrong highway lane advanced")
	_check(city.lane_gate_distance > old_gate, "Missed fork did not continue highway")

	# Right-most lane becomes the connector and keeps its screen position initially.
	city.current_lane = 3
	city.target_lane = 3
	city.lane_visual_offset = city._lane_center_offset(3)
	var exit_offset: float = city.lane_visual_offset
	city.lane_distance = city.lane_gate_distance
	city._process_lane_mode(0.0)
	_check(city.active_stage_id == "connector_in", "Right-most lane did not become connector")
	_check(city.steering_mode == "connector", "Exit road is not connector mode")
	_check(absf(city.road_center_offset - exit_offset) < 1.0, "Exit connector recentered instead of staying connected")

	var connector_in_start_scale: float = city.car_scale
	city.lane_distance = city.lane_gate_distance * 0.5
	city._process_lane_mode(0.0)
	_check(absf(city.road_center_offset) < absf(exit_offset), "Exit connector does not curve/recenter over distance")
	_check(city.car_scale > connector_in_start_scale, "Exit connector does not zoom car in")
	city.lane_distance = city.lane_gate_distance
	city._process_lane_mode(0.0)

	_check(city.active_stage_id == "downtown", "Connector did not reach city")
	_check(city.steering_mode == "turn", "City should have turns")
	_check(city.turn_roads.size() > 0, "City has no connected turn roads")
	_check_no_dead_ends(city, "City")

	# City road physically widens into a second curb/parking lane.
	city._load_stage(5, true)
	_check(city.active_stage_id == "parking_connector", "Parking lane connector missing")
	var parking_start_width: float = city.road_width
	city.lane_distance = city.lane_gate_distance * 0.75
	city._process_lane_mode(0.0)
	_check(city.road_width > parking_start_width, "Parking lane does not physically grow from city road")
	city.lane_distance = city.lane_gate_distance
	city._process_lane_mode(0.0)

	_check(city.active_stage_id == "parking_street", "Parking connector did not reach parking street")
	_check(city.lane_count == 2, "Final street should have travel lane plus parking lane")
	_check(int(city.active_profile.get("parking_lane", -1)) == 1, "Right lane is not parking lane")

	# Parking only completes from the right lane.
	var park_gate: float = city.lane_gate_distance
	city.current_lane = 0
	city.target_lane = 0
	city.lane_visual_offset = city._lane_center_offset(0)
	city.lane_distance = park_gate
	city._process_lane_mode(0.0)
	_check(not city.drive_complete, "Travel lane incorrectly parked")
	_check(city.lane_gate_distance > park_gate, "Missed parking spot did not continue street")

	city.current_lane = 1
	city.target_lane = 1
	city.lane_visual_offset = city._lane_center_offset(1)
	city.lane_distance = city.lane_gate_distance
	city._process_lane_mode(0.0)
	_check(city.drive_complete, "Parking lane did not finish drive")

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
		print("DRIVE v0.11 TEST PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("DRIVE v0.11 TEST FAIL count=%d" % failures.size())
	quit(1)
