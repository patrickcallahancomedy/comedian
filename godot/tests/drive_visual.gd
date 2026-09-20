extends SceneTree
## Render the real scene at phone size; output is outside the source tree.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/drive/drive_module.tscn").instantiate()
	root.add_child(scene)
	var city = scene.get_node("CityMap")
	city.set_process(false)
	await shot("01-start")
	# Exercise the actual key handler, including the newly supported arrows.
	var go := InputEventKey.new()
	go.keycode = KEY_SPACE
	go.pressed = true
	Input.parse_input_event(go)
	await process_frame
	for frame in range(80):
		city._process(1.0 / 60.0)
	await shot("02-neighborhood")
	for index in [1, 2, 3, 4]:
		city._load_stage(index, true)
		for frame in range(70):
			city._process(1.0 / 60.0)
		await shot("0%d-%s" % [index + 2, city.active_stage_id])
	scene.get_node("Effects").elapsed = 12.1
	await shot("07-phone")
	city._finish_drive()
	await shot("08-arrival")
	scene.free()
	quit()

func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/drive-" + label + ".png")
