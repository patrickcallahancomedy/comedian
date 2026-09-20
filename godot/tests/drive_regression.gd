extends SceneTree
## DRIVE v0.9 regressions: invisible connector gates, eight-lane exit recovery,
## contact debounce, random input safety, replay and venue handoff.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var packed = load("res://scenes/drive/drive_module.tscn")
	var scene = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	var city = scene.get_node("CityMap")
	city.set_process(false)

	# First connector should preserve the old profile until animation completes.
	city._begin_connector(1)
	check(city.transition_active, "First connector did not start")
	check(city.active_stage_id == "neighborhood", "First connector swapped too early")
	city._process_connector(city.transition_duration + 0.01)
	check(city.active_stage_id == "highway", "First connector did not reach highway")

	# Missing the right-most exit keeps the player on the highway.
	city.lane_traffic.clear()
	city.target_lane = 6
	city.current_lane = 6
	city.lane_visual_offset = city._lane_center_offset(6)
	city.lane_distance = city.lane_gate_distance
	var old_gate: float = city.lane_gate_distance
	city._process_lane_mode(0.0)
	check(city.active_stage_id == "highway", "Wrong lane accepted at highway gate")
	check(city.lane_gate_distance > old_gate, "Missed exit did not add highway")

	# Correct right-most lane starts connector rather than hard-swapping.
	city.lane_visual_offset = city._lane_center_offset(7)
	city.current_lane = 7
	city.target_lane = 7
	city.lane_distance = city.lane_gate_distance
	city._process_lane_mode(0.0)
	check(city.transition_active, "Correct highway lane did not start connector")
	check(city.active_stage_id == "highway", "Highway connector swapped too early")
	city._process_connector(city.transition_duration + 0.01)
	check(city.active_stage_id == "downtown", "Highway connector did not reach venue approach")

	# Contact debounce still works on the eight-lane highway.
	city._load_stage(1, true)
	city.lane_traffic = [{"lane": city.current_lane, "distance": 20.0, "speed_factor": 0.7}]
	city._process_lane_mode(1.0 / 60.0)
	check(city.bumps == 1, "Contact not detected")
	city._process_lane_mode(1.0 / 60.0)
	check(city.bumps == 1, "One contact counted twice")

	# Rapid input cannot push lane selection beyond the eight-lane bounds.
	var random := RandomNumberGenerator.new()
	random.seed = 7309
	for index in range(6000):
		match random.randi_range(0, 12):
			0: city._turn_left()
			1: city._turn_right()
			2: city._move_forward()
		city._process(1.0 / 60.0)
		check(city.target_lane >= 0 and city.target_lane < city.lane_count, "Lane out of bounds")
		check(is_finite(city.camera_world_position.x), "Invalid position after rapid steering")

	city._finish_drive()
	check(scene.get_node("Arrival").visible, "No arrival panel")
	var state = root.get_node("GameState")
	var gas: int = state.gas

	scene.get_node("Arrival/Layout/Replay").pressed.emit()
	await process_frame
	await process_frame
	scene = current_scene
	check(scene != null and scene.trip_result.is_empty(), "Replay did not reset result")
	check(state.gas == gas, "Practice replay changed persistent state")

	city = scene.get_node("CityMap")
	city._finish_drive()
	scene.get_node("Arrival/Layout/Continue").pressed.emit()
	scene._continue_trip()
	check(state.gas == maxi(0, gas - 3), "Handoff did not apply gas exactly once")
	check(root.get_node("SceneRouter").last_module_id == "drive", "Wrong module handoff")
	await process_frame
	await process_frame
	check(root.get_node("SceneRouter").current_route_id == "venue", "Arrival did not route to venue")

	for failure in failures:
		push_error(failure)
	print("REGRESSION PASS — v0.9 connectors, 8-lane exit, replay, venue" if failures.is_empty() else "REGRESSION FAIL")
	quit(0 if failures.is_empty() else 1)


func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
