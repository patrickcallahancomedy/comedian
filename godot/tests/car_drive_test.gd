extends SceneTree

## DRIVE smoke test.
##
## Checks the tiny real gameplay contract:
## - external player-car texture loads
## - the game requires LEFT / RIGHT at intersections
## - correct turns advance the route
## - wrong turns do not secretly advance it

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

	var drive = packed.instantiate()
	drive.title_seconds = 0.01
	drive.seconds_per_block = 1.0
	get_root().add_child(drive)

	await create_timer(0.03).timeout

	_check(drive.player_car.texture != null, "DRIVE external car texture did not load")

	# Deterministic manual stepping.
	drive.set_process(false)
	drive.started = true

	# First intersection is RIGHT. No input must stop and wait.
	drive.block_progress = 0.95
	drive._process(0.10)
	_check(drive.waiting_for_turn, "DRIVE did not wait for a turn")
	_check(drive.block_index == 0, "DRIVE advanced without a player turn")

	# Correct RIGHT advances.
	drive._handle_direction(1)
	_check(drive.block_index == 1, "Correct RIGHT turn did not advance DRIVE")
	_check(not drive.waiting_for_turn, "DRIVE stayed paused after correct turn")

	# Second intersection is LEFT. Deliberately choose wrong RIGHT.
	drive.block_progress = 0.95
	drive._handle_direction(1)
	drive._process(0.10)
	_check(drive.block_index == 1, "Wrong DRIVE turn advanced the route")
	_check(drive.missed_turns == 1, "Wrong DRIVE turn was not counted")
	_check(drive.block_progress <= drive.TURN_ZONE + 0.001, "Wrong turn did not reset to a retry")

	# Now choose correct LEFT.
	drive.block_progress = 0.95
	drive._handle_direction(-1)
	drive._process(0.10)
	_check(drive.block_index == 2, "Correct LEFT turn did not advance DRIVE")

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
