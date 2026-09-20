extends SceneTree
## DRIVE v0.11 regression coverage for connected road chunks, physical highway
## fork, parking lane, contact debounce, replay and venue handoff.

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

	# Connector geometry is distance driven.
	city._load_stage(1, true)
	var start_width: float = city.road_width
	city.lane_distance = city.lane_gate_distance * 0.5
	city._process_lane_mode(0.0)
	check(city.road_width > start_width, "First connector did not widen by distance")
	city.lane_distance = city.lane_gate_distance
	city._process_lane_mode(0.0)
	check(city.active_stage_id == "highway", "First connector did not reach highway")
	check(city.lane_count == 4, "Highway is not four lanes")

	# Missed physical fork keeps the player on highway.
	city.lane_traffic.clear()
	city.target_lane = 2
	city.current_lane = 2
	city.lane_visual_offset = city._lane_center_offset(2)
	city.lane_distance = city.lane_gate_distance
	var old_gate: float = city.lane_gate_distance
	city._process_lane_mode(0.0)
	check(city.active_stage_id == "highway", "Wrong lane accepted at highway fork")
	check(city.lane_gate_distance > old_gate, "Missed fork did not continue highway")

	# Correct lane becomes connector without teleporting to screen center.
	city.lane_visual_offset = city._lane_center_offset(3)
	city.current_lane = 3
	city.target_lane = 3
	var fork_offset: float = city.lane_visual_offset
	city.lane_distance = city.lane_gate_distance
	city._process_lane_mode(0.0)
	check(city.active_stage_id == "connector_in", "Right lane did not feed connector")
	check(absf(city.road_center_offset - fork_offset) < 1.0, "Connector lost fork position")

	# Contact debounce still works on four-lane highway.
	city._load_stage(2, true)
	city.lane_traffic = [{"lane": city.current_lane, "distance": 20.0, "speed_factor": 0.7}]
	city._process_lane_mode(1.0 / 60.0)
	check(city.bumps == 1, "Contact not detected")
	city._process_lane_mode(1.0 / 60.0)
	check(city.bumps == 1, "One contact counted twice")

	# Final street has two lanes and parking requires the right lane.
	city._load_stage(6, true)
	check(city.lane_count == 2, "Parking street is not two lanes")
	var park_gate: float = city.lane_gate_distance
	city.current_lane = 0
	city.target_lane = 0
	city.lane_visual_offset = city._lane_center_offset(0)
	city.lane_distance = park_gate
	city._process_lane_mode(0.0)
	check(not city.drive_complete, "Travel lane incorrectly completed parking")
	check(city.lane_gate_distance > park_gate, "Missed parking did not continue road")

	# Random lane input remains bounded.
	var random := RandomNumberGenerator.new()
	random.seed = 7311
	for index in range(3000):
		match random.randi_range(0, 10):
			0: city._turn_left()
			1: city._turn_right()
		city._process(1.0 / 60.0)
		check(city.target_lane >= 0 and city.target_lane < city.lane_count, "Lane out of bounds")

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
	print("REGRESSION PASS — v0.11 connected roads, fork, parking" if failures.is_empty() else "REGRESSION FAIL")
	quit(0 if failures.is_empty() else 1)


func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
