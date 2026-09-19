extends SceneTree

## DRIVE reset smoke test.
##
## Contract for this checkpoint:
## - scene loads
## - background is white
## - the external car texture loads
## - the car sits in the center area
## Nothing else is part of DRIVE yet.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DRIVE RESET TEST START")

	var packed := load("res://scenes/drive/drive_module.tscn") as PackedScene
	_check(packed != null, "DRIVE scene failed to load")
	if packed == null:
		_finish()
		return

	var drive := packed.instantiate()
	get_root().add_child(drive)

	var background := drive.get_node_or_null("WhiteBackground") as ColorRect
	var car := drive.get_node_or_null("PlayerCar") as TextureRect

	_check(background != null, "White background is missing")
	if background != null:
		_check(background.color == Color(1, 1, 1, 1), "Background is not white")

	_check(car != null, "Player car is missing")
	if car != null:
		_check(car.texture != null, "Player car texture did not load")
		var center := car.position + car.size * 0.5
		_check(center.distance_to(Vector2(215, 382)) < 2.0, "Player car is not centered")

	drive.free()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("DRIVE RESET TEST PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	print("DRIVE RESET TEST FAIL count=%d" % failures.size())
	quit(1)
