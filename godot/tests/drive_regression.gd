extends SceneTree

const NETWORK = preload("res://scripts/drive/drive_road_network.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var packed = load("res://scenes/drive/drive_module.tscn")
	var scene = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	var drive = scene.get_node("CityMap")
	drive.set_process(false)
	drive._move_forward()

	# Missing the fork stays on the same physical highway and removes the exit lane.
	drive._enter_highway()
	drive.player_world_position = Vector2(NETWORK.highway_lane_center(1, 4), NETWORK.HIGHWAY_FORK_Y + 2.0)
	drive.current_lane = 1
	drive.target_lane = 1
	drive._process_highway(0.01)
	check(drive.current_road_kind == "highway", "Wrong lane incorrectly took highway branch")
	check(drive.highway_after_fork, "Missed fork did not continue main highway")
	check(drive.lane_count == 3, "Exit lane did not physically leave main highway")

	# Correct fork starts at the right lane's exact world coordinate.
	drive._enter_highway()
	drive.player_world_position = Vector2(NETWORK.highway_lane_center(3, 4), NETWORK.HIGHWAY_FORK_Y + 2.0)
	drive.current_lane = 3
	drive.target_lane = 3
	drive._process_highway(0.01)
	check(drive.current_road_kind == "exit_connector", "Right lane did not take exit")
	check(drive.player_world_position.distance_to(NETWORK.EXIT_START) < 0.1, "Exit connector is not physically attached")

	# Lane input cannot exceed actual road lanes.
	drive._enter_highway()
	for i in range(20):
		drive._turn_right()
	check(drive.target_lane == 3, "Highway lane selection exceeded four lanes")
	for i in range(20):
		drive._turn_left()
	check(drive.target_lane == 0, "Highway lane selection went below zero")

	drive._enter_parking()
	for i in range(20):
		drive._turn_right()
	check(drive.target_lane == 1, "Parking selection exceeded two lanes")

	# Finish result is idempotent and replay stays free.
	drive._finish_drive()
	check(scene.get_node("Arrival").visible, "Arrival panel missing")
	var original_result: Dictionary = scene.trip_result.duplicate(true)
	drive._finish_drive()
	check(scene.trip_result == original_result, "Finish is not idempotent")

	var state = root.get_node("GameState")
	var gas: int = state.gas
	scene.get_node("Arrival/Layout/Replay").pressed.emit()
	await process_frame
	await process_frame
	scene = current_scene
	check(scene != null and scene.trip_result.is_empty(), "Replay did not reset trip")
	check(state.gas == gas, "Replay changed persistent gas")

	# Continue still hands the result to the existing venue flow once.
	drive = scene.get_node("CityMap")
	drive._finish_drive()
	scene.get_node("Arrival/Layout/Continue").pressed.emit()
	scene._continue_trip()
	check(state.gas == maxi(0, gas - 3), "Handoff did not apply gas once")
	check(root.get_node("SceneRouter").last_module_id == "drive", "Wrong module handoff")
	await process_frame
	await process_frame
	check(root.get_node("SceneRouter").current_route_id == "venue", "Drive did not route to venue")

	for failure in failures:
		push_error(failure)
	print("REGRESSION PASS — v0.12 one world road network" if failures.is_empty() else "REGRESSION FAIL")
	quit(0 if failures.is_empty() else 1)


func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
