extends SceneTree

## Automated control playthroughs prove completion/functionality only.
var failures: Array[String] = []
var timings: Array[float] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var packed := load("res://scenes/drive/drive_module.tscn") as PackedScene

	for seed_value in range(1, 101):
		var scene := packed.instantiate()
		var drive = scene.get_node("CityMap")
		drive.world_seed = seed_value
		root.add_child(scene)
		scene.set_process(false)
		drive.set_process(false)

		drive._process(5.0)
		check(drive.drive_time == 0.0, "Pre-start time counted")
		drive._move_forward()

		var frames := 0
		while not drive.drive_complete and frames < 2400:
			match drive.current_road_kind:
				"neighborhood", "city":
					if drive.waiting_for_turn:
						follow_gps_turn(drive)
				"highway":
					while drive.target_lane < 3:
						drive._turn_right()
				"parking":
					if drive.target_lane < 1:
						drive._turn_right()

			drive._process(1.0 / 30.0)
			check(is_finite(drive.player_world_position.x), "Non-finite world position")
			check(is_finite(drive.camera_zoom), "Non-finite camera zoom")
			frames += 1

		check(drive.drive_complete, "Trip stalled: seed %d road %s" % [seed_value, drive.current_road_kind])
		check(not scene.trip_result.is_empty(), "Arrival result missing")
		check(drive.drive_time < 45.0, "Trip too long: seed %d %.1fs" % [seed_value, drive.drive_time])

		if drive.drive_complete:
			timings.append(drive.drive_time)

		scene.free()

	if not timings.is_empty():
		timings.sort()
		print("PACING min=%.2f median=%.2f max=%.2f" % [
			timings[0],
			timings[timings.size() / 2],
			timings[-1],
		])

	for failure in failures:
		push_error(failure)
	print("PLAYTEST PASS" if failures.is_empty() else "PLAYTEST FAIL")
	quit(0 if failures.is_empty() else 1)


func follow_gps_turn(drive) -> void:
	if drive.shortest_route.size() < 2:
		return

	var desired_id: String = drive.shortest_route[1]
	var desired: Vector2 = (
		(drive.street_nodes[desired_id] as Vector2)
		- (drive.street_nodes[drive.street_current] as Vector2)
	).normalized()
	var cross := drive.street_heading.cross(desired)

	if cross < -0.25:
		drive._turn_left()
	elif cross > 0.25:
		drive._turn_right()


func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
