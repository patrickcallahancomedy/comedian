extends SceneTree

## DRIVE smoke test.
##
## Current contract:
## - DRIVE scene loads with the external car asset
## - the car stays centered
## - four map definitions exist
## - neighborhood / highway / city / parking can each be built
## - every map has a legal GPS route from its start to its destination


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

	var background := drive.get_node_or_null("WhiteBackground") as ColorRect
	var car := drive.get_node_or_null("PlayerCar") as TextureRect
	var city_map := drive.get_node_or_null("CityMap")
	var map_label := drive.get_node_or_null("MapLabel") as Label
	var status_label := drive.get_node_or_null("StatusLabel") as Label

	_check(background != null, "White background is missing")
	if background != null:
		_check(background.color == Color(1, 1, 1, 1), "Background is not white")

	_check(car != null, "Player car is missing")
	if car != null:
		_check(car.texture != null, "Player car texture did not load")
		var center := car.position + car.size * 0.5
		_check(center.distance_to(Vector2(215, 382.5)) < 2.0, "Player car is not centered")

	_check(city_map != null, "CityMap is missing")
	_check(map_label != null, "DRIVE map label is missing")
	_check(status_label != null, "DRIVE status label is missing")

	if city_map != null:
		var configs = city_map.get("map_configs")
		_check(configs is Array, "DRIVE map config list is missing")

		if configs is Array:
			_check(configs.size() == 4, "DRIVE does not contain exactly four maps")

		# Build all four stages and verify each one produces a usable route.
		for map_index in range(4):
			city_map.call("_load_map", map_index)

			var current_map = city_map.get("current_map")
			var route = city_map.get("shortest_route")
			var roads = city_map.get("roads")

			_check(current_map is Dictionary, "Map %d did not load config data" % map_index)
			_check(route is Array and not route.is_empty(), "Map %d has no legal GPS route" % map_index)
			_check(roads is Array and not roads.is_empty(), "Map %d generated no roads" % map_index)

			var physically_connected := bool(city_map.call("_city_is_connected", false))
			_check(physically_connected, "Map %d is physically disconnected" % map_index)

		# Return to the normal starting stage after structural checks.
		city_map.call("_load_map", 0)

		if map_label != null:
			_check("NEIGHBORHOOD" in map_label.text, "DRIVE does not start in neighborhood")

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
