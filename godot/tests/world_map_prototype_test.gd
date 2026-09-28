extends SceneTree

const LAYOUT = preload("res://scripts/drive/world_map_layout.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("WORLD MAP PROTOTYPE TEST START")

	var ramp := LAYOUT.main_onramp()
	var city_exit := LAYOUT.city_exit()
	var wrong_exit := LAYOUT.wrong_exit()

	_check(ramp.size() >= 20, "Main overpass curve is undersampled")
	_check(city_exit.size() >= 8, "City exit curve is undersampled")
	_check(wrong_exit.size() >= 8, "Wrong exit curve is undersampled")

	var feeder := LAYOUT.neighborhood_feeder()
	_check(
		feeder[feeder.size() - 1].distance_to(ramp[0]) < 0.1,
		"Neighborhood feeder does not physically meet the overpass"
	)

	var ramp_end := ramp[ramp.size() - 1]
	_check(
		LAYOUT.WESTBOUND_HIGHWAY.has_point(ramp_end),
		"Main overpass does not physically merge into westbound highway"
	)

	var city_exit_start := city_exit[0]
	_check(
		LAYOUT.WESTBOUND_HIGHWAY.has_point(city_exit_start),
		"Correct city exit does not branch from the highway"
	)
	var city_entry := LAYOUT.city_entry_road()
	_check(
		city_exit[city_exit.size() - 1].distance_to(city_entry[0]) < 0.1,
		"Correct highway exit does not physically reach the city road"
	)

	var wrong_exit_start := wrong_exit[0]
	_check(
		LAYOUT.WESTBOUND_HIGHWAY.has_point(wrong_exit_start),
		"Wrong exit does not branch from the physical highway"
	)
	var wrong_road := LAYOUT.wrong_exit_road()
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
