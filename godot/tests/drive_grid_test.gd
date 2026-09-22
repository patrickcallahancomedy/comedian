extends SceneTree

const MAP = preload("res://scripts/drive/drive_grid_map.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DRIVE GRID v0.1 TEST START")

	_check(MAP.MAP_SIZE == Vector2i(880, 800), "Logical map size is wrong")
	_check(is_equal_approx(MAP.CONNECTOR_ONE_RECT.size.x, 80.0), "Connector one is not doubled to 80 units")
	_check(is_equal_approx(MAP.CONNECTOR_TWO_RECT.size.x, 80.0), "Connector two is not doubled to 80 units")
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
		"City grid scale changed unexpectedly"
	)

	var packed := load("res://scenes/drive/drive_module.tscn") as PackedScene
	_check(packed != null, "Drive grid scene failed to load")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	var drive = scene.get_node("CityMap")
	var neighborhood_tiles = scene.get_node("CityMap/NeighborhoodTiles")
	var neighborhood_decor = scene.get_node("CityMap/NeighborhoodDecor")
	var navigation = scene.get_node("Navigation")

	_check(drive != null, "Grid controller missing")
	_check(neighborhood_tiles != null, "Neighborhood TileMapLayer missing")
	if neighborhood_tiles != null:
		_check(
			neighborhood_tiles.get_used_cells().size() == 16,
			"Neighborhood TileMapLayer is not filling the 4x4 driving grid"
		)
	_check(neighborhood_decor != null, "Neighborhood Sprite2D decor missing")
	if neighborhood_decor != null:
		_check(
			neighborhood_decor.get_child_count() == 12,
			"Neighborhood decor does not contain the twelve house sprites"
		)
	_check(navigation != null, "Navigation display missing")
	if navigation != null:
		_check(navigation.get_instruction() == "↑  ROUTE READY", "Navigation is not ready before start")
	_check(is_equal_approx(drive.STEP_SECONDS, 1.0), "Movement is not one block per second")
	_check(drive.road_kind == "neighborhood", "Drive does not start in neighborhood")

	drive._start_drive()
	_check(drive.started, "START did not begin grid drive")
	if navigation != null:
		_check(
			navigation.get_instruction() == "↑  STRAIGHT  •  1 BLOCK",
			"Navigation does not show the first neighborhood instruction"
		)

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
	_check(
		is_equal_approx(
			drive._current_world_speed(),
			float(MAP.NEIGHBORHOOD_CELL) / drive.STEP_SECONDS
		),
		"On-ramp does not start at neighborhood speed"
	)

	# The highway connector accelerates across its physical 80-unit ramp.
	drive.visual_world_position.x = MAP.CONNECTOR_ONE_RECT.position.x
	var ramp_start_speed: float = drive._current_world_speed()
	drive.visual_world_position.x = MAP.CONNECTOR_ONE_RECT.position.x + MAP.CONNECTOR_ONE_RECT.size.x * 0.5
	var ramp_mid_speed: float = drive._current_world_speed()
	drive.visual_world_position.x = MAP.CONNECTOR_ONE_RECT.end.x
	var ramp_end_speed: float = drive._current_world_speed()
	_check(ramp_mid_speed > ramp_start_speed, "On-ramp does not accelerate through the middle")
	_check(ramp_end_speed > ramp_mid_speed, "On-ramp does not continue accelerating")
	_check(
		is_equal_approx(
			ramp_end_speed,
			float(MAP.HIGHWAY_CELL) * 4.0 / drive.STEP_SECONDS
		),
		"On-ramp does not reach highway speed"
	)

	# Connector hands directly to the four-lane highway.
	drive.visual_world_position = MAP.highway_entry_point()
	drive.visual_cell_scale = 0.5
	drive.move_from = drive.visual_world_position
	drive.scale_from = 0.5
	drive._begin_highway_step()
	_check(drive.road_kind == "highway", "Connector did not enter highway")
	_check(
		is_equal_approx(
			drive._current_world_speed(),
			float(MAP.HIGHWAY_CELL) * 4.0 / drive.STEP_SECONDS
		),
		"Highway is not running at the faster speed"
	)

	var lane_before: int = drive.queued_highway_lane
	var target_y_before: float = drive.move_to.y
	drive._turn_right()
	_check(drive.queued_highway_lane == lane_before + 1, "Highway lane input did not register")
	_check(not is_equal_approx(drive.move_to.y, target_y_before), "Highway merge still waits for checkpoint")

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
	_check(is_equal_approx(drive.scale_to, 6.0), "City connector should grow smoothly to full city scale")

	# The city connector decelerates from highway speed down to 0.8x neighborhood speed.
	drive.visual_world_position.x = MAP.CONNECTOR_TWO_RECT.position.x
	var exit_start_speed: float = drive._current_world_speed()
	drive.visual_world_position.x = MAP.CONNECTOR_TWO_RECT.position.x + MAP.CONNECTOR_TWO_RECT.size.x * 0.5
	var exit_mid_speed: float = drive._current_world_speed()
	drive.visual_world_position.x = MAP.CONNECTOR_TWO_RECT.end.x
	var exit_end_speed: float = drive._current_world_speed()
	_check(exit_mid_speed < exit_start_speed, "City off-ramp does not slow through the middle")
	_check(exit_end_speed < exit_mid_speed, "City off-ramp does not keep slowing")
	_check(
		is_equal_approx(
			exit_end_speed,
			float(MAP.NEIGHBORHOOD_CELL) * 0.8 / drive.STEP_SECONDS
		),
		"City off-ramp does not reach 0.8x neighborhood speed"
	)

	drive.visual_world_position = MAP.city_entry_point()
	drive.visual_cell_scale = 6.0
	drive.move_from = drive.visual_world_position
	drive.scale_from = 6.0
	drive._begin_city_step()
	_check(drive.road_kind == "city", "Second connector did not enter city")
	_check(is_equal_approx(drive.visual_cell_scale, 6.0), "City entry should preserve the smoothly-grown city size")
	_check(
		is_equal_approx(
			drive._current_world_speed(),
			float(MAP.NEIGHBORHOOD_CELL) * 0.8 / drive.STEP_SECONDS
		),
		"City speed is not 0.8x neighborhood speed"
	)
	drive.visual_cell_scale = drive.CITY_CAR_SCALE
	drive._update_car_visual()
	_check(
		is_equal_approx(drive.player_car.scale.x, drive.CAR_REFERENCE_SCALE * 6.0),
		"Rendered city car scale is not actually 6x"
	)

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
