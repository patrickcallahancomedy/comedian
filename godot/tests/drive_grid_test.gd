extends SceneTree

const MAP = preload("res://scripts/drive/drive_grid_map.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DRIVE GRID v0.1 TEST START")

	_check(MAP.MAP_SIZE == Vector2i(800, 800), "Logical map is not 800x800")
	_check(MAP.MASTER_UNIT == 10, "Master snap unit changed")
	_check(MAP.rect_is_master_snapped(MAP.NEIGHBORHOOD_RECT), "Neighborhood is off master grid")
	_check(MAP.rect_is_master_snapped(MAP.CONNECTOR_ONE_RECT), "Connector one is off master grid")
	_check(MAP.rect_is_master_snapped(MAP.HIGHWAY_RECT), "Highway is off master grid")
	_check(MAP.rect_is_master_snapped(MAP.CONNECTOR_TWO_RECT), "Connector two is off master grid")
	_check(MAP.rect_is_master_snapped(MAP.CITY_RECT), "City is off master grid")

	_check(
		MAP.gate_is_on_outer_edge(MAP.NEIGHBORHOOD_GATE, MAP.NEIGHBORHOOD_SIZE),
		"Neighborhood gate is not on the outside edge"
	)
	_check(
		MAP.gate_faces_outside(
			MAP.NEIGHBORHOOD_GATE,
			MAP.NEIGHBORHOOD_GATE_SIDE,
			MAP.NEIGHBORHOOD_SIZE
		),
		"Neighborhood gate does not face outside"
	)

	_check(
		is_equal_approx(MAP.car_scale_for_cell(MAP.NEIGHBORHOOD_CELL), 1.0),
		"Neighborhood car is not 100 percent"
	)
	_check(
		is_equal_approx(MAP.car_scale_for_cell(MAP.HIGHWAY_CELL), 0.5),
		"Highway car is not 50 percent"
	)
	_check(
		is_equal_approx(MAP.car_scale_for_cell(MAP.CITY_CELL), 1.5),
		"City car is not 150 percent"
	)

	var packed := load("res://scenes/drive/drive_module.tscn") as PackedScene
	_check(packed != null, "Drive grid scene failed to load")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	var drive = scene.get_node("CityMap")

	_check(drive != null, "Grid controller missing")
	_check(is_equal_approx(drive.STEP_SECONDS, 1.0), "Movement is not one block per second")
	_check(drive.road_kind == "neighborhood", "Drive does not start in neighborhood")

	drive._start_drive()
	_check(drive.started, "START did not begin grid drive")

	# Prove the only way out is the perimeter gate.
	drive.neighborhood_cell = MAP.NEIGHBORHOOD_GATE
	drive.heading = MAP.NEIGHBORHOOD_GATE_SIDE
	drive.visual_world_position = MAP.neighborhood_cell_center(MAP.NEIGHBORHOOD_GATE)
	drive.visual_cell_scale = 1.0
	drive.move_from = drive.visual_world_position
	drive.scale_from = 1.0
	drive._begin_neighborhood_step()
	_check(drive.road_kind == "connector_one", "Outside gate did not enter connector")
	_check(is_equal_approx(drive.scale_to, 0.5), "First connector does not scale toward highway")

	# Connector hands directly to the four-lane highway.
	drive.visual_world_position = MAP.highway_entry_point()
	drive.visual_cell_scale = 0.5
	drive.move_from = drive.visual_world_position
	drive.scale_from = 0.5
	drive._begin_highway_step()
	_check(drive.road_kind == "highway", "Connector did not enter highway")

	# A missed exit loops instead of trapping the run.
	drive.highway_column = MAP.HIGHWAY_COLUMNS - 1
	drive.highway_lane = 0
	drive.queued_highway_lane = 0
	drive._begin_highway_step()
	_check(drive.missed_turns == 1, "Missed highway exit was not counted")
	_check(drive.highway_column == 1, "Missed highway exit did not loop to start")
	_check(drive.road_kind == "highway", "Missed exit left highway state")

	# Lane four reaches the city connector and scales up.
	drive.highway_column = MAP.HIGHWAY_COLUMNS - 1
	drive.highway_lane = MAP.HIGHWAY_EXIT_LANE
	drive.queued_highway_lane = MAP.HIGHWAY_EXIT_LANE
	drive.visual_world_position = MAP.highway_exit_point()
	drive.visual_cell_scale = 0.5
	drive.move_from = drive.visual_world_position
	drive.scale_from = 0.5
	drive._begin_highway_step()
	_check(drive.road_kind == "connector_two", "Correct highway lane missed city connector")
	_check(is_equal_approx(drive.scale_to, 1.5), "Second connector does not scale toward city")

	drive.visual_world_position = MAP.city_entry_point()
	drive.visual_cell_scale = 1.5
	drive.move_from = drive.visual_world_position
	drive.scale_from = 1.5
	drive._begin_city_step()
	_check(drive.road_kind == "city", "Second connector did not enter city")

	scene.free()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("DRIVE GRID v0.1 TEST PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	print("DRIVE GRID v0.1 TEST FAIL count=%d" % failures.size())
	quit(1)
