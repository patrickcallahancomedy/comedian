extends SceneTree

## DRIVE Step 1 smoke test.
##
## Contract:
## - scene loads
## - road exists
## - real external car texture loads
## - LEFT / RIGHT buttons exist and are enabled

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DRIVE STEP 1 TEST START")

	var packed := load("res://scenes/drive/drive_module.tscn") as PackedScene
	_check(packed != null, "DRIVE scene failed to load")
	if packed == null:
		_finish()
		return

	var drive = packed.instantiate()
	get_root().add_child(drive)

	var road := drive.get_node_or_null("Road")
	var car := drive.get_node_or_null("Road/PlayerCar") as TextureRect
	var left := drive.get_node_or_null("Controls/LeftButton") as Button
	var right := drive.get_node_or_null("Controls/RightButton") as Button

	_check(road != null, "DRIVE road is missing")
	_check(car != null, "DRIVE player car is missing")
	_check(car != null and car.texture != null, "DRIVE player car texture did not load")
	_check(left != null, "DRIVE LEFT button is missing")
	_check(right != null, "DRIVE RIGHT button is missing")
	_check(left != null and not left.disabled, "DRIVE LEFT button is disabled")
	_check(right != null and not right.disabled, "DRIVE RIGHT button is disabled")

	drive.free()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("DRIVE STEP 1 TEST PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	print("DRIVE STEP 1 TEST FAIL count=%d" % failures.size())
	quit(1)
