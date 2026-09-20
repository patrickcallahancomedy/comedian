extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DRIVE TEST START")

	var packed := load("res://scenes/drive/drive_module.tscn") as PackedScene
	_check(packed != null, "DRIVE scene failed to load")

	if packed == null:
		_finish()
		return

	var drive := packed.instantiate()
	get_root().add_child(drive)

	var car := drive.get_node_or_null("PlayerCar") as TextureRect
	var city_map := drive.get_node_or_null("CityMap")
	var map_label := drive.get_node_or_null("MapLabel") as Label

	_check(car != null, "Player car is missing")
	_check(city_map != null, "CityMap is missing")
	_check(map_label != null, "Map label is missing")

	if car != null:
		_check(car.texture != null, "Player car texture did not load")

	if city_map == null:
		drive.free()
		_finish()
		return

	_check(
		city_map.get("active_stage_id") == "neighborhood",
		"DRIVE does not start in the neighborhood"
	)
	_check(
		city_map.get("steering_mode") == "turn",
		"Neighborhood is not using turn mode"
	)
	_check(
		int(city_map.get("lane_count")) == 1,
		"Neighborhood should use one lane"
	)
	_check(
		is_equal_approx(float(city_map.get("car_scale")), 1.0),
		"Neighborhood car scale is wrong"
	)
	_check(
		bool(city_map.get("stop_signs_enabled")),
		"Neighborhood stop signs are disabled"
	)
	_check(
		float(city_map.get("intersection_spacing")) >= 1800.0,
		"Neighborhood blocks are still too short"
	)
	_check_no_dead_ends(city_map, "Neighborhood")

	for point in city_map.get("turn_intersections"):
		var route = city_map.call(
			"_find_turn_route",
			point,
			city_map.get("exit_intersection")
		)
		_check(
			not route.is_empty(),
			"Neighborhood node cannot reach the gate"
		)

	city_map.call("_load_stage", 1, false)

	var main_speed := float(city_map.get("drive_speed"))

	_check(
		city_map.get("active_stage_id") == "main_road",
		"Main road profile failed to load"
	)
	_check(
		city_map.get("steering_mode") == "lane",
		"Main road is not using lane mode"
	)
	_check(
		int(city_map.get("lane_count")) == 2,
		"Main road should have two lanes"
	)
	_check(
		is_equal_approx(float(city_map.get("car_scale")), 0.75),
		"Main road car should be 75 percent scale"
	)
	_check(
		city_map.get("lane_traffic").size() > 0,
		"Main road has no passing traffic"
	)

	city_map.call("_load_stage", 2, false)

	var highway_speed := float(city_map.get("drive_speed"))

	_check(
		city_map.get("active_stage_id") == "highway",
		"Highway profile failed to load"
	)
	_check(
		int(city_map.get("lane_count")) == 3,
		"Highway should have three lanes"
	)
	_check(
		is_equal_approx(float(city_map.get("car_scale")), 0.5),
		"Highway car should be 50 percent scale"
	)
	_check(
		highway_speed > main_speed,
		"Highway is not faster than the main road"
	)
	_check(
		int(city_map.get("active_profile").get("exit_lane", -1)) == 2,
		"Highway does not require the right exit lane"
	)

	var old_gate_distance := float(city_map.get("lane_gate_distance"))
	city_map.set("section_started", true)
	city_map.set("current_lane", 0)
	city_map.set("target_lane", 0)
	city_map.set("lane_distance", old_gate_distance)
	city_map.call("_process_lane_mode", 0.0)

	_check(
		city_map.get("active_stage_id") == "highway",
		"Missing the highway exit incorrectly advanced the stage"
	)
	_check(
		float(city_map.get("lane_gate_distance")) > old_gate_distance,
		"Missing the highway exit did not move the next gate forward"
	)

	city_map.set("current_lane", 2)
	city_map.set("target_lane", 2)
	city_map.set(
		"lane_distance",
		float(city_map.get("lane_gate_distance"))
	)
	city_map.call("_process_lane_mode", 0.0)

	_check(
		city_map.get("active_stage_id") == "downtown",
		"Correct highway exit did not advance to downtown"
	)
	_check(
		city_map.get("steering_mode") == "turn",
		"Downtown is not using turn mode"
	)
	_check(
		is_equal_approx(float(city_map.get("car_scale")), 1.25),
		"Downtown car should be 125 percent scale"
	)
	_check(
		bool(city_map.get("one_way_enabled")),
		"Downtown one-way streets are disabled"
	)
	_check_no_dead_ends(city_map, "Downtown")

	var one_way_count := 0

	for road in city_map.get("turn_roads"):
		if bool(road.get("one_way", false)):
			one_way_count += 1

	_check(
		one_way_count > 0,
		"Downtown generated no one-way streets"
	)

	for point in city_map.get("turn_intersections"):
		var route = city_map.call(
			"_find_turn_route",
			point,
			city_map.get("exit_intersection")
		)
		_check(
			not route.is_empty(),
			"Downtown node cannot legally reach the gate"
		)

	city_map.call("_load_stage", 4, false)

	_check(
		city_map.get("active_stage_id") == "parking",
		"Parking profile failed to load"
	)
	_check(
		int(city_map.get("lane_count")) == 1,
		"Parking should use one lane"
	)
	_check(
		not bool(city_map.get("stop_signs_enabled")),
		"Parking should not use stop signs"
	)
	_check_no_dead_ends(city_map, "Parking")

	drive.free()
	_finish()


func _check_no_dead_ends(city_map, label: String) -> void:
	var degree: Dictionary = {}

	for point in city_map.get("turn_intersections"):
		degree[point] = 0

	for road in city_map.get("turn_roads"):
		var a: Vector2i = road["from"]
		var b: Vector2i = road["to"]
		degree[a] = int(degree.get(a, 0)) + 1
		degree[b] = int(degree.get(b, 0)) + 1

	for point in degree.keys():
		_check(
			int(degree[point]) >= 2,
			"%s generated a dead end" % label
		)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("DRIVE TEST PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)

	print("DRIVE TEST FAIL count=%d" % failures.size())
	quit(1)
