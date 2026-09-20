extends SceneTree

const NETWORK = preload("res://scripts/drive/drive_road_network.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DRIVE v0.12 STRUCTURE START")

	var packed := load("res://scenes/drive/drive_module.tscn") as PackedScene
	_check(packed != null, "Drive scene failed to load")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	var drive = scene.get_node("CityMap")
	var car := scene.get_node("PlayerCar") as TextureRect

	_check(drive != null, "Connected drive controller missing")
	_check(car.texture != null, "External player car asset missing")

	# Topology itself must be continuous.
	var neighborhood := NETWORK.neighborhood_nodes()
	var city := NETWORK.city_nodes()
	_check(neighborhood["n7"] == NETWORK.CONNECTOR_OUT_START, "Neighborhood does not physically meet connector")
	_check(is_equal_approx(NETWORK.CONNECTOR_OUT_END.y, NETWORK.HIGHWAY_START_Y), "Connector does not physically meet highway")
	_check(NETWORK.exit_curve(0.0).distance_to(NETWORK.EXIT_START) < 0.1, "Exit branch start is disconnected")
	_check(NETWORK.exit_curve(1.0).distance_to(NETWORK.CITY_ENTRY) < 0.1, "Exit connector does not meet city")
	_check(city["c0"] == NETWORK.CITY_ENTRY, "City entry does not share connector endpoint")
	_check(is_equal_approx((city["c8"] as Vector2).x, NETWORK.PARK_WIDEN_END.x), "City does not line up with parking road")

	_check(drive.current_road_kind == "neighborhood", "Drive does not start on neighborhood road")
	_check(drive.camera_zoom < 0.85, "Neighborhood is still oversized")
	_check(drive.street_edges.size() > 0, "Neighborhood has no road graph")

	drive._move_forward()
	_check(drive.started, "START did not begin movement")

	# Enter the real connector and drive through distance, not a timer transition.
	drive._enter_connector_out()
	var start_pos: Vector2 = drive.player_world_position
	_check(start_pos == NETWORK.CONNECTOR_OUT_START, "Connector starts at wrong world coordinate")
	drive._process_connector_out(1.5)
	_check(drive.current_road_kind == "connector_out", "Connector instantly swapped road type")
	_check(drive.player_world_position.distance_to(start_pos) > 100.0, "Car did not physically travel connector")
	_check(drive.camera_zoom < NETWORK.NEIGHBORHOOD_ZOOM, "Connector did not zoom out while driving")
	drive._process_connector_out(10.0)

	_check(drive.current_road_kind == "highway", "Connector did not physically feed highway")
	_check(drive.lane_count == 4, "Highway is not four lanes")
	_check(drive.player_world_position.y == NETWORK.HIGHWAY_START_Y, "Highway entry moved in world space")

	# Right-most highway lane literally enters the branch at the shared fork.
	drive.player_world_position = Vector2(NETWORK.highway_lane_center(3, 4), NETWORK.HIGHWAY_FORK_Y + 2.0)
	drive.target_lane = 3
	drive.current_lane = 3
	drive._process_highway(0.01)
	_check(drive.current_road_kind == "exit_connector", "Right-most lane did not enter physical branch")
	_check(drive.player_world_position.distance_to(NETWORK.EXIT_START) < 0.1, "Branch entry teleported away from fork")

	drive._process_exit_connector(10.0)
	_check(drive.current_road_kind == "city", "Exit connector did not reach city")
	_check(drive.player_world_position == NETWORK.CITY_ENTRY, "City did not start at connector endpoint")
	_check(drive.street_edges.size() >= 8, "City does not contain turn network")

	# Final city road widens in world space before parking.
	drive._enter_parking_widen()
	var widen_start: Vector2 = drive.player_world_position
	drive._process_parking_widen(0.7)
	_check(drive.current_road_kind == "parking_widen", "Parking lane appeared as a hard switch")
	_check(drive.player_world_position.distance_to(widen_start) > 100.0, "Car did not drive through parking widening road")
	drive._process_parking_widen(10.0)
	_check(drive.current_road_kind == "parking", "Widening road did not reach parking street")
	_check(drive.lane_count == 2, "Final street is not travel lane + parking lane")

	drive.target_lane = 1
	drive.current_lane = 1
	drive.player_world_position = Vector2(drive._parking_lane_x(1), drive.parking_spot_y + 1.0)
	drive._process_parking(0.01)
	_check(drive.drive_complete, "Right parking lane did not complete drive")

	scene.free()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("DRIVE v0.12 STRUCTURE PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	print("DRIVE v0.12 STRUCTURE FAIL count=%d" % failures.size())
	quit(1)
