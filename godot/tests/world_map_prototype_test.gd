extends SceneTree

const LAYOUT = preload("res://scripts/drive/world_map_layout.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("WORLD MAP PROTOTYPE TEST START")

	var westbound := LAYOUT.westbound_highway()
	var eastbound := LAYOUT.eastbound_highway()
	var overpass := LAYOUT.overpass_arterial()
	var collector := LAYOUT.neighborhood_collector()
	var ramp := LAYOUT.main_onramp()
	var city_exit := LAYOUT.city_exit()
	var wrong_exit := LAYOUT.wrong_exit()
	var city_roads: Array = LAYOUT.city_roads()
	var wrong_road := LAYOUT.wrong_exit_road()

	_check(westbound.size() >= 40, "Westbound highway is undersampled")
	_check(eastbound.size() == westbound.size(), "Divided highway paths disagree")
	_check(overpass.size() >= 16, "Overpass is undersampled")
	_check(ramp.size() >= 30, "Main on-ramp is undersampled")
	_check(city_exit.size() >= 18, "City exit is undersampled")
	_check(wrong_exit.size() >= 14, "Wrong exit is undersampled")

	_check(
		collector[collector.size() - 1].distance_to(overpass[0]) < 0.1,
		"Neighborhood collector does not physically meet the overpass"
	)

	_check(
		_min_point_distance(ramp[0], overpass) < 8.0,
		"On-ramp does not branch from the physical overpass"
	)

	_check(
		_min_point_distance(ramp[ramp.size() - 1], westbound) < 18.0,
		"On-ramp does not merge alongside the westbound freeway"
	)

	_check(
		_min_point_distance(city_exit[0], westbound) < 18.0,
		"Correct city exit does not branch from the freeway"
	)

	var city_arterial: PackedVector2Array = city_roads[0]
	_check(
		city_exit[city_exit.size() - 1].distance_to(city_arterial[0]) < 0.1,
		"Correct city exit does not physically reach the city arterial"
	)

	_check(
		_min_point_distance(wrong_exit[0], westbound) < 18.0,
		"Wrong exit does not branch from the physical freeway"
	)
	_check(
		wrong_exit[wrong_exit.size() - 1].distance_to(wrong_road[0]) < 0.1,
		"Wrong exit does not lead to its own physical road"
	)

	var packed := load(
		"res://scenes/drive/world_map_prototype.tscn"
	) as PackedScene
	_check(packed != null, "World map prototype scene failed to load")

	if packed != null:
		var scene := packed.instantiate()
		root.add_child(scene)
		_check(
			scene.get_script() != null
			and scene.get_script().resource_path.ends_with(
				"world_map_prototype.gd"
			),
			"Prototype scene is not using the map-only script"
		)
		_check(
			scene.get_child_count() == 0,
			"Map prototype unexpectedly contains gameplay nodes"
		)
		scene.free()

	_finish()


func _min_point_distance(point: Vector2, path: PackedVector2Array) -> float:
	var result := INF
	for candidate in path:
		result = minf(result, point.distance_to(candidate))
	return result


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		print("FAIL: ", message)


func _finish() -> void:
	if failures.is_empty():
		print("WORLD MAP PROTOTYPE TEST PASS")
		quit(0)
		return

	print("WORLD MAP PROTOTYPE TEST FAIL")
	for failure in failures:
		print(" - ", failure)
	quit(1)
