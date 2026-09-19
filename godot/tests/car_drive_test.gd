extends SceneTree

## DRIVE smoke test.
##
## Current contract:
## - scene loads with the external car asset
## - one continuous 20x20 world is generated
## - neighborhood, highway, city, and parking all exist in that same graph
## - the whole-trip GPS route reaches an open parking space
## - the close main view and whole-world minimap share the same world data


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

		_check(
			car.size.x <= 110.0 and car.size.y <= 110.0,
			"Player car is too large for the close road view"
		)

	if city_map != null:
		var world_size := int(city_map.get("WORLD_SIZE"))
		var intersections = city_map.get("intersections")
		var roads = city_map.get("roads")
		var route = city_map.get("shortest_route")
		var parking_slots = city_map.get("parking_slots")
		var open_slots = city_map.get("open_parking_slots")
		var destination = city_map.get("destination_intersection")
		var block_size := float(city_map.get("block_size"))
		var minimap_size := float(city_map.get("minimap_size"))

		_check(world_size == 20, "DRIVE master world is not 20x20")
		_check(intersections is Array and not intersections.is_empty(), "World has no intersections")
		_check(roads is Array and not roads.is_empty(), "World has no roads")
		_check(route is Array and not route.is_empty(), "Whole-trip GPS route was not found")
		_check(parking_slots is Array and parking_slots.size() == 4, "Parking lot does not have four candidate spaces")
		_check(open_slots is Array and open_slots.size() == 2, "Parking lot does not have exactly two open spaces")
		_check(open_slots.has(destination), "GPS destination is not an open parking space")
		_check(block_size <= 170.0, "Main-view blocks are still too large")
		_check(minimap_size >= 110.0, "Whole-world minimap is too small")

		# Confirm all four environments contribute roads to one shared graph.
		var road_regions: Dictionary = {}

		for road in roads:
			road_regions[str(road.get("region", ""))] = true

		for region_id in ["neighborhood", "highway", "city", "parking"]:
			_check(
				road_regions.has(region_id),
				"Shared world is missing region: %s" % region_id
			)

		# Neighborhood starts as a 5x5 grid (40 connections) with 16 removed.
		var neighborhood_road_count := 0
		var city_one_way_count := 0

		for road in roads:
			if str(road.get("region", "")) == "neighborhood":
				neighborhood_road_count += 1

			if (
				str(road.get("region", "")) == "city"
				and str(road.get("road_type", "")) == "city"
				and bool(road.get("one_way", false))
			):
				city_one_way_count += 1

		_check(
			neighborhood_road_count == 24,
			"Neighborhood did not remove exactly 16 of its 40 grid roads"
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

		# The minimap must fit the full world while the close view remains zoomed in.
		var mini_start: Vector2 = city_map.call("_world_to_minimap", Vector2.ZERO)
		var mini_end: Vector2 = city_map.call(
			"_world_to_minimap",
			Vector2(19, 19)
		)

		_check(
			mini_end.x > mini_start.x and mini_end.y > mini_start.y,
			"Minimap world projection is invalid"
		)

		if map_label != null:
			_check(
				"NEIGHBORHOOD" in map_label.text,
				"DRIVE does not begin in the neighborhood"
			)

	drive.free()
	_finish()


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
