extends SceneTree
## Render the real v0.8 scene at phone size; screenshots stay outside source.

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene = load("res://scenes/drive/drive_module.tscn").instantiate()
	root.add_child(scene)
	var city = scene.get_node("CityMap")
	city.set_process(false)
	await shot("01-start")

	var go := InputEventKey.new()
	go.keycode = KEY_SPACE
	go.pressed = true
	Input.parse_input_event(go)
	await process_frame
	for frame in range(80):
		city._process(1.0 / 60.0)
	await shot("02-neighborhood")

	for index in [1, 2]:
		city._load_stage(index, true)
		for frame in range(70):
			city._process(1.0 / 60.0)
		await shot("0%d-%s" % [index + 2, city.active_stage_id])

	city._finish_drive()
	await shot("05-arrival")
	scene.free()
	quit()


func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/drive-v08-" + label + ".png")
