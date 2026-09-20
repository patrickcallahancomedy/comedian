extends SceneTree
## Repeatable control-driven playthroughs, not a claim of human enjoyment.
var failures: Array[String] = []
var timings: Array[float] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var packed := load("res://scenes/drive/drive_module.tscn") as PackedScene
	for seed_value in range(1, 101):
		root.get_node("GameState").energy = 10 if seed_value > 50 else 100
		var scene := packed.instantiate()
		var city = scene.get_node("CityMap")
		city.world_seed = seed_value
		root.add_child(scene)
		scene.set_process(false)
		city.set_process(false)
		city._process(10.0)
		check(city.drive_time == 0.0, "Pre-GO time counted")
		city._move_forward()
		var frames := 0
		var injected_mistake := false
		var decision_target := Vector2i(-99, -99)
		var last_stage := -1
		while not city.drive_complete and frames < 120 * 60:
			if city.stage_index != last_stage:
				decision_target = Vector2i(-99, -99)
				last_stage = city.stage_index
			if city.transition_active:
				pass
			elif city.steering_mode == "turn":
				var at: Vector2i = city.target_intersection if city.is_driving else city.current_intersection
				# Queue one choice per road. Read only the displayed GPS route.
				if at != decision_target and at != city.exit_intersection:
					var route: Array[Vector2i] = city._find_turn_route(at, city.exit_intersection)
					if route.size() > 1:
						var desired := route[1] - at
						if seed_value % 2 == 0 and not injected_mistake:
							for other in city._legal_turn_neighbors(at):
								if other == city.current_intersection:
									desired = other - at
									injected_mistake = true
									break
						steer(city, desired)
					decision_target = at
				if not city.is_driving and city.auto_stop_remaining <= 0.0:
					city._move_forward()
			else:
				# Overtake a slow car with enough visible distance to react.
				var wanted: int = city.target_lane
				for traffic in city.lane_traffic:
					var gap: float = traffic.distance - city.lane_distance
					if traffic.lane == wanted and gap > 180.0 and gap < 800.0:
						wanted = (wanted + 1) % city.lane_count
				if city.active_stage_id == "highway" and city.lane_gate_distance - city.lane_distance < 1500:
					wanted = int(city.active_profile.get("exit_lane", city.lane_count - 1))
				if wanted > city.target_lane:
					city._turn_right()
				elif wanted < city.target_lane:
					city._turn_left()
			city._process(1.0 / 60.0)
			check(is_finite(city.camera_world_position.x), "Non-finite position")
			frames += 1
		check(city.drive_complete, "Trip stalled: seed %d, stage %s" % [seed_value, city.active_stage_id])
		check(not scene.trip_result.is_empty(), "Missing arrival result")
		check(city.drive_time < 70.0, "Trip too long: %d" % seed_value)
		if injected_mistake:
			check(city.wrong_turns > 0, "Wrong turn not recorded")
		var original_result: Dictionary = scene.trip_result.duplicate()
		city._finish_drive()
		check(scene.trip_result == original_result, "Finish is not idempotent")
		if city.drive_complete:
			timings.append(city.drive_time)
			print("TRIP seed=%d seconds=%.2f wrong=%d bumps=%d" % [seed_value, city.drive_time, city.wrong_turns, city.bumps])
		scene.free()
	if not timings.is_empty():
		timings.sort()
		print("PACING min=%.2f median=%.2f max=%.2f" % [timings[0], timings[timings.size()/2], timings[-1]])
	for failure in failures:
		push_error(failure)
	print("PLAYTEST PASS" if failures.is_empty() else "PLAYTEST FAIL")
	quit(0 if failures.is_empty() else 1)

func steer(city, desired: Vector2i) -> void:
	for step in range(2):
		if city.heading == desired:
			return
		if Vector2i(city.heading.y, -city.heading.x) == desired:
			city._turn_left()
		else:
			city._turn_right()

func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
