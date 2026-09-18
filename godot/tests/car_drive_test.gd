extends SceneTree

## DRIVE smoke test.
##
## Intentionally avoids adding the scene to the live tree. This keeps the test
## deterministic and proves the playable contract without waiting on timers:
## - scene loads
## - no blocking title overlay exists
## - real external car texture is wired
## - LEFT / RIGHT controls exist
## - no input cannot advance a turn
## - correct / wrong turns behave as expected

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
	_check(drive != null, "DRIVE scene failed to instantiate")
	if drive == null:
		_finish()
		return

	# Scene contract: there must be actual gameplay visible immediately.
	_check(not drive.has_node("TitleCard"), "Blocking DRIVE title overlay still exists")
	_check(drive.has_node("Road"), "DRIVE road is missing")
	_check(drive.has_node("Road/PlayerCar"), "DRIVE player car is missing")
	_check(drive.has_node("Controls/LeftButton"), "DRIVE LEFT button is missing")
	_check(drive.has_node("Controls/RightButton"), "DRIVE RIGHT button is missing")
	_check(drive.has_node("HUD/MiniMapPanel/Margin/MiniMap"), "DRIVE minimap is missing")

	var player_car := drive.get_node_or_null("Road/PlayerCar") as TextureRect
	_check(player_car != null, "DRIVE player car is not a TextureRect")
	if player_car != null:
		_check(player_car.texture != null, "DRIVE external car texture did not load")

	# Wire the @onready references manually because this test intentionally does
	# not add the scene to the tree.
	drive.road = drive.get_node("Road")
	drive.minimap = drive.get_node("HUD/MiniMapPanel/Margin/MiniMap")
	drive.player_car = drive.get_node("Road/PlayerCar")
	drive.left_button = drive.get_node("Controls/LeftButton")
	drive.right_button = drive.get_node("Controls/RightButton")
	drive.result_panel = drive.get_node("ResultPanel")
	drive.result_label = drive.get_node("ResultPanel/Margin/Layout/ResultLabel")
	drive.continue_button = drive.get_node("ResultPanel/Margin/Layout/ContinueButton")

	drive.started = true
	drive.seconds_per_block = 1.0

	# Reach first intersection with no input. It must wait instead of advancing.
	drive.block_progress = 0.95
	drive._process(0.10)
	_check(drive.waiting_for_turn, "DRIVE did not stop for player input")
	_check(drive.block_index == 0, "DRIVE advanced without LEFT / RIGHT input")
	_check(not drive.finished, "DRIVE finished without player input")

	# First required turn is RIGHT.
	drive._handle_direction(1)
	_check(drive.block_index == 1, "Correct RIGHT did not advance DRIVE")
	_check(not drive.waiting_for_turn, "Correct RIGHT did not resume DRIVE")

	# Second intersection requires LEFT. Choose wrong RIGHT first.
	drive.block_progress = 0.95
	drive._handle_direction(1)
	drive._process(0.10)
	_check(drive.block_index == 1, "Wrong turn advanced DRIVE")
	_check(drive.missed_turns == 1, "Wrong turn was not counted")
	_check(drive.block_progress <= drive.TURN_ZONE + 0.001, "Wrong turn did not create a retry")

	# Then choose the correct LEFT.
	drive.block_progress = 0.95
	drive._handle_direction(-1)
	drive._process(0.10)
	_check(drive.block_index == 2, "Correct LEFT did not advance DRIVE")

	drive.free()
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
