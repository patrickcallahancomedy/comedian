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

	var background := drive.get_node_or_null("GroundBackground") as ColorRect
	var car := drive.get_node_or_null("PlayerCar") as TextureRect
	var city_map := drive.get_node_or_null("CityMap")
	var map_label := drive.get_node_or_null("MapLabel") as Label
	var status_label := drive.get_node_or_null("StatusLabel") as Label

	_check(background != null, "Ground background is missing")
	_check(car != null, "Player car is missing")
	_check(city_map != null, "CityMap is missing")
	_check(map_label != null, "DRIVE map label is missing")
	_check(status_label != null, "DRIVE status label is missing")

	if car != null:
		_check(car.texture != null, "Player car texture did not load")

		var center := car.position + car.size * 0.5
		_check(
			center.distance_to(Vector2(215, 382)) < 2.0,
			"Player car is not centered"
		)

	if city_map != null:
		var intersections = city_map.get("intersections")
		var positions = city_map.get("intersection_positions")
		var roads = city_map.get("roads")
		var route = city_map.get("shortest_route")
		var parking_slots = city_map.get("parking_slots")
		var open_slots = city_map.get("open_parking_slots")
		var destination = city_map.get("destination_intersection")
		var minimap_world_size: Vector2 = city_map.get("minimap_world_size")

		_check(
			int(city_map.get("world_size")) == 20,
			"Logical DRIVE graph is not 20x20"
		)
		_check(
			minimap_world_size == Vector2(42.0, 34.0),
			"Physical minimap world size is wrong"
		)
		_check(
			intersections is Array and not intersections.is_empty(),
			"World has no intersections"
		)
		_check(
			positions is Dictionary and positions.size() == intersections.size(),
			"Not every intersection has a physical position"
		)
		_check(
			roads is Array and not roads.is_empty(),
			"World has no roads"
		)
		_check(
			route is Array and not route.is_empty(),
			"Whole-trip GPS route was not found"
		)
		_check(
			parking_slots is Array and parking_slots.size() == 4,
			"Parking lot does not have four candidate spaces"
		)
		_check(
			open_slots is Array and open_slots.size() == 2,
			"Parking lot does not have exactly two open spaces"
		)
		_check(
			open_slots.has(destination),
			"GPS destination is not an open parking space"
		)

		var neighborhood_distance := _distance_between(
			positions,
			Vector2i(0, 12),
			Vector2i(1, 12)
		)
		var city_distance := _distance_between(
			positions,
			Vector2i(10, 4),
			Vector2i(11, 4)
		)
		var highway_distance := _distance_between(
			positions,
			Vector2i(5, 10),
			Vector2i(6, 10)
		)

		_check(
			neighborhood_distance > city_distance * 2.0,
			"Neighborhood blocks are not physically longer than city blocks"
		)
		_check(
			highway_distance > neighborhood_distance,
			"Highway segments are not the longest road spacing"
		)

		var road_regions: Dictionary = {}
		var neighborhood_road_count := 0
		var city_one_way_count := 0

		for road in roads:
			var region_id := str(road.get("region", ""))
			road_regions[region_id] = true

			if region_id == "neighborhood":
				neighborhood_road_count += 1

			if (
				region_id == "city"
				and str(road.get("road_type", "")) == "city"
				and bool(road.get("one_way", false))
			):
				city_one_way_count += 1

		for region_id in ["neighborhood", "highway", "city", "parking"]:
			_check(
				road_regions.has(region_id),
				"Shared world is missing region: %s" % region_id
			)

		_check(
			neighborhood_road_count == 32,
			"Neighborhood did not remove exactly 8 of its 40 grid roads"
		)
		_check(
			city_one_way_count > 0,
			"City generated no one-way streets"
		)

		if route is Array and not route.is_empty():
			_check(
				route[0] == city_map.get("start_intersection"),
				"GPS route does not begin at Darren's house"
			)
			_check(
				route[route.size() - 1] == destination,
				"GPS route does not end at the parking destination"
			)

		var mini_start: Vector2 = city_map.call(
			"_world_to_minimap",
			Vector2.ZERO
		)
		var mini_end: Vector2 = city_map.call(
			"_world_to_minimap",
			minimap_world_size
		)

		_check(
			mini_end.x > mini_start.x and mini_end.y > mini_start.y,
			"Minimap physical-world projection is invalid"
		)

		if map_label != null:
			_check(
				map_label.text == "NEIGHBORHOOD",
				"DRIVE does not begin in the neighborhood"
			)

	drive.free()
	_finish()


func _distance_between(
	positions: Dictionary,
	a: Vector2i,
	b: Vector2i
) -> float:
	if not positions.has(a) or not positions.has(b):
		return 0.0

	var a_position: Vector2 = positions[a]
	var b_position: Vector2 = positions[b]

	return a_position.distance_to(b_position)


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
