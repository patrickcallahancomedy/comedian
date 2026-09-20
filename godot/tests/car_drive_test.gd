extends SceneTree

## DRIVE v0.8 structural smoke test.
## The retired v0.7 profiles still exist in drive_profiles.gd, but the playable
## route is intentionally neighborhood -> highway -> downtown.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DRIVE v0.8 TEST START")

	var packed := load("res://scenes/drive/drive_module.tscn") as PackedScene
	_check(packed != null, "DRIVE scene failed to load")
	if packed == null:
		_finish()
		return

	var drive := packed.instantiate()
	get_root().add_child(drive)
	var car := drive.get_node_or_null("PlayerCar") as TextureRect
	var city = drive.get_node_or_null("CityMap")
	var map_label := drive.get_node_or_null("MapLabel") as Label
	var controls := drive.get_node_or_null("TouchControls")

	_check(car != null and car.texture != null, "Player car texture did not load")
	_check(city != null, "CityMap is missing")
	_check(map_label != null, "Map label node is missing")
	_check(controls != null, "Touch controls are missing")
	if city == null:
		drive.free()
		_finish()
		return

	_check(city.active_stage_id == "neighborhood", "Trip does not start in neighborhood")
	_check(city.steering_mode == "turn", "Neighborhood should use turn steering")
	_check(not city.stop_signs_enabled, "v0.8 neighborhood should not pause at stop signs")
	_check(city.intersection_spacing >= 1800.0, "Neighborhood blocks unexpectedly shortened")
	_check_no_dead_ends(city, "Neighborhood")

	# START should be the only non-steering tap. Once used, it disappears.
	var start_button := drive.get_node("TouchControls/ForwardButton") as Button
	_check(start_button.visible, "START is not visible before departure")
	city._move_forward()
	_check(city.section_started, "START did not begin the trip")
	_check(not start_button.visible, "START did not disappear after departure")

	city._load_stage(1, false)
	_check(city.active_stage_id == "highway", "Second active phase is not highway")
	_check(city.steering_mode == "lane", "Highway should use lane steering")
	_check(city.lane_count == 3, "Highway should have three lanes")
	_check(city.lane_traffic.size() > 0, "Highway has no traffic")
	_check(int(city.active_profile.get("exit_lane", -1)) == 2, "Highway exit lane changed")

	var old_gate := city.lane_gate_distance
	city.section_started = true
	city.current_lane = 0
	city.target_lane = 0
	city.lane_visual_offset = city._lane_center_offset(0)
	city.lane_distance = old_gate
	city._process_lane_mode(0.0)
	_check(city.active_stage_id == "highway", "Missing exit incorrectly advanced")
	_check(city.lane_gate_distance > old_gate, "Missing exit did not extend route")

	city.current_lane = 2
	city.target_lane = 2
	city.lane_visual_offset = city._lane_center_offset(2)
	city.lane_distance = city.lane_gate_distance
	city._process_lane_mode(0.0)
	_check(city.active_stage_id == "downtown", "Correct exit did not reach downtown")
	_check(city.steering_mode == "turn", "Downtown should use turn steering")
	_check(not city.one_way_enabled, "v0.8 downtown should not use one-way rules")
	_check(not city.stop_signs_enabled, "v0.8 downtown should not pause at stop signs")
	_check_no_dead_ends(city, "Downtown")

	# At a stopped intersection, one steering tap should resume the car without GO.
	city.section_started = true
	city.is_driving = false
	city.auto_stop_remaining = 0.0
	var before := city.current_intersection
	for neighbor in city._legal_turn_neighbors(before):
		var desired: Vector2i = neighbor - before
		if desired != city.heading:
			while city.heading != desired:
				city._turn_right()
			break
	_check(city.is_driving, "Steering did not resume turn-mode driving")

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
		print("DRIVE v0.8 TEST PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("DRIVE v0.8 TEST FAIL count=%d" % failures.size())
	quit(1)
