extends SceneTree

## DRIVE smoke test.
##
## This exists because a successful web export is not enough: DRIVE must require
## player input and a wrong turn must not secretly advance the route.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DRIVE TEST START")

	var packed := load("res://scenes/car/car_module.tscn") as PackedScene
	_check(packed != null, "DRIVE scene failed to load")
	if packed == null:
		_finish()
		return

	var drive = packed.instantiate()
	drive.title_seconds = 0.01
	get_root().add_child(drive)

	await create_timer(0.03).timeout

	# Take control of stepping so this test is deterministic.
	drive.set_process(false)
	drive.game_started = true

	# Reach the first intersection without touching anything.
	drive._process(2.0)
	_check(drive.waiting_at_intersection, "DRIVE did not stop for a player choice")
	_check(drive.route_segment == 0, "DRIVE advanced without player input")
	_check(not drive.finished, "DRIVE finished without player input")

	# Sitting there forever must not autoplay the game.
	drive._process(30.0)
	_check(drive.waiting_at_intersection, "DRIVE left the intersection without input")
	_check(drive.route_segment == 0, "DRIVE autoplayed while waiting")
	_check(not drive.finished, "DRIVE can finish hands-off")

	# First required turn is RIGHT.
	drive._choose_turn(1)
	_check(drive.route_segment == 1, "Correct DRIVE turn did not advance route")
	_check(not drive.waiting_at_intersection, "Correct DRIVE turn did not resume movement")

	# Reach second intersection; required turn there is LEFT.
	drive._process(2.0)
	_check(drive.waiting_at_intersection, "DRIVE did not stop at second intersection")
	_check(drive.route_segment == 1, "DRIVE skipped second intersection")

	# Choose the wrong direction. It must enter a loop and return to the SAME
	# intersection rather than quietly granting progress.
	drive._choose_turn(1)
	_check(drive.detour_active, "Wrong DRIVE turn did not start a detour")
	drive._process(10.0)
	_check(not drive.detour_active, "DRIVE detour did not complete")
	_check(drive.waiting_at_intersection, "DRIVE detour did not return to intersection")
	_check(drive.route_segment == 1, "Wrong DRIVE turn advanced the route")

	# Now make the correct LEFT turn.
	drive._choose_turn(-1)
	_check(drive.route_segment == 2, "Correct turn after detour did not advance")

	drive.queue_free()
	await process_frame
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
