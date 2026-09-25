extends SceneTree

const MAP = preload("res://scripts/drive/drive_grid_map.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DRIVE GRID v0.1 TEST START")

	_check(MAP.MAP_SIZE == Vector2i(1760, 1600), "Logical map size is wrong")
	_check(is_equal_approx(MAP.CONNECTOR_ONE_RECT.size.x, 160.0), "Connector one is not doubled to 160 units")
	_check(is_equal_approx(MAP.CONNECTOR_TWO_RECT.size.x, 160.0), "Connector two is not doubled to 160 units")
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

	# Neighborhood road graph: corners turn, edge cells feed the inner grid,
	# inner cells are four-way intersections, and only the fixed gate opens out.
	_check(
		MAP.neighborhood_connections(Vector2i(0, 0)) == [Vector2i.RIGHT, Vector2i.DOWN],
		"Top-left neighborhood corner is not a turn"
	)
	_check(
		MAP.neighborhood_connections(Vector2i(3, 0)) == [Vector2i.LEFT, Vector2i.DOWN],
		"Top-right neighborhood corner is not a turn"
	)
	_check(
		MAP.neighborhood_connections(Vector2i(0, 3)) == [Vector2i.RIGHT, Vector2i.UP],
		"Bottom-left neighborhood corner is not a turn"
	)
	_check(
		MAP.neighborhood_connections(Vector2i(3, 3)) == [Vector2i.LEFT, Vector2i.UP],
		"Bottom-right neighborhood corner is not a turn"
	)
	_check(
		MAP.neighborhood_connections(Vector2i(1, 1)).size() == 4,
		"Inner neighborhood cell is not a four-way intersection"
	)
	_check(
		MAP.neighborhood_connections(Vector2i(1, 0)).size() == 3,
		"Perimeter neighborhood cell is not a T-junction"
	)
	_check(
		MAP.neighborhood_has_connection(MAP.NEIGHBORHOOD_GATE, MAP.NEIGHBORHOOD_GATE_SIDE),
		"Neighborhood gate does not visually/logically open to connector"
	)
	_check(
		MAP.neighborhood_cells_connect(Vector2i(1, 3), Vector2i(1, 2)),
		"Start cell does not connect into the inner grid"
	)
	_check(
		not MAP.neighborhood_has_connection(Vector2i(0, 0), Vector2i.LEFT),
		"Non-gate corner incorrectly opens outside the neighborhood"
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
	var navigation = scene.get_node("Navigation")
	var traffic_container = scene.get_node_or_null("TrafficCars")

	_check(drive != null, "Grid controller missing")
	_check(traffic_container != null, "Highway traffic container missing")
	if traffic_container != null:
		_check(traffic_container.get_child_count() == 3, "Highway should have exactly three traffic cars")
	_check(drive.HIGHWAY_TRAFFIC_COLUMNS.size() == 3, "Highway traffic column data is not three cars")
	_check(drive.HIGHWAY_TRAFFIC_LANES.size() == 3, "Highway traffic lane data is not three cars")
	_check(
		scene.get_node_or_null("NeighborhoodTiles") == null,
		"Legacy NeighborhoodTiles node should be removed"
	)
	_check(
		scene.get_node_or_null("NeighborhoodDecor") == null,
		"Legacy NeighborhoodDecor node should be removed"
	)
	_check(
		drive.NEIGHBORHOOD_ROAD_WIDTH > 0.0,
		"Basic neighborhood road styling is missing"
	)

	var on_ramp_points: PackedVector2Array = drive._connector_one_points()
	_check(on_ramp_points.size() == 4, "On-ramp is not a four-point wedge")
	if on_ramp_points.size() == 4:
		var on_ramp_start_width := on_ramp_points[3].y - on_ramp_points[0].y
		var on_ramp_end_width := on_ramp_points[2].y - on_ramp_points[1].y
		_check(
			on_ramp_end_width > on_ramp_start_width,
			"On-ramp does not widen toward the highway"
		)

	var off_ramp_points: PackedVector2Array = drive._connector_two_points()
	_check(off_ramp_points.size() == 4, "Off-ramp is not a four-point wedge")
	if off_ramp_points.size() == 4:
		var off_ramp_start_width := off_ramp_points[3].y - off_ramp_points[0].y
		var off_ramp_end_width := off_ramp_points[2].y - off_ramp_points[1].y
		_check(
			off_ramp_end_width > off_ramp_start_width,
			"Off-ramp does not widen toward the city"
		)

	_check(
		drive._city_connections(Vector2i(0, 0)).size() == 2,
		"City corner is not a two-way turn"
	)
	_check(
		drive._city_connections(Vector2i(1, 0)).size() == 3,
		"City perimeter tile is not a three-way intersection"
	)
	_check(
		drive._city_connections(Vector2i(1, 1)).size() == 4,
		"City interior tile is not a four-way intersection"
	)
	_check(
		not drive._city_connections(Vector2i(0, 0)).has(Vector2i.LEFT),
		"City top-left corner incorrectly opens through the border"
	)
	_check(
		not drive._city_connections(Vector2i(0, 0)).has(Vector2i.UP),
		"City top-left corner incorrectly opens through the border"
	)
	_check(
		drive._city_connections(MAP.CITY_ENTRY).has(Vector2i.LEFT),
		"City entry is not the one intentional outside opening"
	)
	_check(
		not drive._city_connections(MAP.CITY_DESTINATION).has(Vector2i.RIGHT),
		"City destination incorrectly opens through the outside border"
	)
	_check(
		drive.CITY_WORLD_ZOOM < drive.WORLD_ZOOM,
		"City camera does not zoom out enough to show its tile layout"
	)

	var parking_lot: Rect2 = drive._parking_lot_rect()
	var venue_rect: Rect2 = drive._venue_rect()
	var destination_center: Vector2 = drive._city_cell_center(MAP.CITY_DESTINATION)
	var aisle_entry: Vector2 = drive._parking_aisle_point()
	_check(
		parking_lot.has_point(aisle_entry),
		"Parking aisle entry is not inside the parking lot"
	)
	_check(
		aisle_entry.x > destination_center.x,
		"Parking lot is not reached by turning right off the street"
	)
	_check(
		parking_lot.has_point(drive._parking_space_center(-1, 1)),
		"Upper open parking space is not inside the lot"
	)
	_check(
		parking_lot.has_point(drive._parking_space_center(1, -1)),
		"Lower open parking space is not inside the lot"
	)
	_check(
		venue_rect.position.x >= parking_lot.end.x,
		"Venue is not positioned beside the parking lot"
	)

	_check(navigation != null, "Navigation display missing")
	if navigation != null:
		_check(navigation.text == "", "Legacy text navigation should be blank")
		_check(navigation.get_turn_hint().is_empty(), "Turn route guidance should stay hidden before START")
	_check(is_equal_approx(drive.STEP_SECONDS, 1.0), "Base timing constant changed")
	_check(is_equal_approx(drive.TURN_SECONDS, 0.34), "Turn timing changed")
	_check(drive.road_kind == "neighborhood", "Drive does not start in neighborhood")
	_check(MAP.NEIGHBORHOOD_CELL == 80, "Neighborhood blocks are not doubled")
	_check(MAP.HIGHWAY_CELL == 40, "Highway columns are not doubled")
	_check(MAP.HIGHWAY_LANE_WIDTH == 10, "Highway lanes should stay skinny while road length is doubled")
	_check(MAP.CITY_CELL == 120, "City blocks are not doubled")
	_check(
		is_equal_approx(drive.NEIGHBORHOOD_WORLD_SPEED, 40.0),
		"Neighborhood car speed was changed instead of enlarging the world"
	)

	drive._start_drive()
	_check(drive.started, "START did not begin grid drive")
	if navigation != null:
		var initial_route: Array[Vector3i] = navigation._current_route_states()
		_check(initial_route.size() >= 2, "Navigation route line has no usable path")
		var route_world_points: PackedVector2Array = navigation._route_world_points(initial_route)
		_check(
			route_world_points.size() >= 2,
			"Navigation route line has no world segments"
		)
		_check(
			route_world_points[0].distance_to(drive.visual_world_position) < 0.5,
			"Navigation route line is not anchored to the car"
		)
		_check(
			navigation.ROUTE_LINE_WIDTH_RATIO >= 0.28
			and navigation.ROUTE_LINE_WIDTH_RATIO <= 0.36,
			"GPS route line width changed"
		)
		_check(
			navigation.ROUTE_LINE_COLOR.a >= 0.95,
			"GPS route line is not solid enough"
		)
		var initial_instruction: Dictionary = navigation._current_instruction()
		_check(
			initial_instruction.get("title") == "Turn right",
			"GPS instruction banner does not show the first turn"
		)
		_check(
			String(initial_instruction.get("subtitle", "")) == "In 2 blocks",
			"GPS instruction banner block count is off by one"
		)
		var initial_hint: Dictionary = navigation.get_turn_hint()
		_check(
			initial_hint.get("cell") == Vector2i(1, 1),
			"First turn guidance is not anchored to the expected intersection"
		)
		_check(
			initial_hint.get("turn") == "right",
			"First turn guidance should point right"
		)
		var neighborhood_route_points: PackedVector2Array = navigation._current_route_world_points()
		_check(
			neighborhood_route_points.size() >= 2,
			"Blue GPS route is missing in neighborhood"
		)
		_check(
			neighborhood_route_points[neighborhood_route_points.size() - 1]
				== Vector2(
					MAP.CONNECTOR_ONE_RECT.position.x,
					MAP.neighborhood_cell_center(MAP.NEIGHBORHOOD_GATE).y
				),
			"Neighborhood route does not stop at the connector mouth"
		)
		var saved_kind_for_line: String = drive.road_kind
		var saved_position_for_line: Vector2 = drive.visual_world_position
		var saved_lane_for_line: int = drive.highway_lane
		drive.road_kind = "connector_one"
		drive.visual_world_position = MAP.CONNECTOR_ONE_RECT.get_center()
		_check(
			not navigation._should_draw_route_line(),
			"Blue GPS route should be hidden on connector one"
		)
		drive.road_kind = "highway"
		drive.highway_lane = 1
		drive.visual_world_position = drive._highway_cell_center(5, 1)
		_check(
			not navigation._should_draw_route_line(),
			"Blue GPS route should be hidden on highway"
		)
		drive.road_kind = "connector_two"
		drive.visual_world_position = drive._connector_two_rect().get_center()
		_check(
			not navigation._should_draw_route_line(),
			"Blue GPS route should be hidden on connector two"
		)
		drive.road_kind = "city"
		drive.city_cell = MAP.CITY_ENTRY
		drive.heading = Vector2i.RIGHT
		drive.visual_world_position = drive._city_cell_center(MAP.CITY_ENTRY)
		_check(
			navigation._should_draw_route_line()
			and navigation._current_route_world_points().size() >= 2,
			"Blue GPS route is missing in city"
		)
		drive.road_kind = saved_kind_for_line
		drive.visual_world_position = saved_position_for_line
		drive.highway_lane = saved_lane_for_line


		# Missing that turn should move the hint to the next best intersection.
		drive.neighborhood_cell = Vector2i(1, 0)
		drive.heading = Vector2i.UP
		var reroute_hint: Dictionary = navigation.get_turn_hint()
		_check(
			reroute_hint.get("cell") == Vector2i(1, 0),
			"Missed turn did not move the route guidance to the next intersection"
		)
		_check(
			reroute_hint.get("turn") == "right",
			"Rerouted turn guidance should point right"
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
	if navigation != null:
		navigation._update_status_visibility()
		_check(
			not drive.status_label.visible,
			"Legacy CONNECTOR label is visible behind GPS banner"
		)
	_check(is_equal_approx(drive.scale_to, 0.5), "First connector does not scale toward highway")
	_check(
		is_equal_approx(
			drive._current_world_speed(),
			drive.NEIGHBORHOOD_WORLD_SPEED
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
			drive.HIGHWAY_WORLD_SPEED
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
	drive.road_kind = "connector_one"
	drive.steering_feedback = 1.0
	drive.turn_drift_direction = 1.0
	drive.camera_nudge = Vector2(5.0, 0.0)
	drive._stabilize_for_connector()
	_check(is_equal_approx(drive.steering_feedback, 0.0), "Connector keeps steering wobble")
	_check(is_equal_approx(drive.turn_drift_direction, 0.0), "Connector keeps drift state")
	_check(drive.camera_nudge == Vector2.ZERO, "Connector keeps camera wobble")
	drive.road_kind = "highway"
	if navigation != null:
		navigation._update_status_visibility()
		_check(not drive.status_label.visible, "Highway status text should be hidden")
		_check(
			drive.road_kind == "highway",
			"Highway state changed while testing route visibility"
		)
	_check(
		is_equal_approx(
			drive._current_world_speed(),
			drive.HIGHWAY_WORLD_SPEED
		),
		"Highway is not running at the faster speed"
	)

	var lane_before: int = drive.queued_highway_lane
	var target_y_before: float = drive.move_to.y
	drive._turn_right()
	_check(drive.queued_highway_lane == lane_before + 1, "Highway lane input did not register")
	_check(not is_equal_approx(drive.move_to.y, target_y_before), "Highway merge still waits for checkpoint")
	_check(drive.steering_feedback > 0.0, "Highway steering has no visual feedback")
	_check(drive.camera_nudge.x < 0.0, "Camera does not counter-nudge on a right merge")
	_check(
		drive.player_car.pivot_offset.y < drive.player_car.size.y * 0.5,
		"Steering pivot is not ahead of the car center"
	)
	_check(
		is_equal_approx(drive.CAR_STEERING_PIVOT_Y_RATIO, 0.28),
		"Steering pivot ratio changed from front-axle fishtail setup"
	)
	_check(
		drive._ease_turn_in_out(0.1) < 0.1,
		"Turn does not ease in"
	)
	_check(
		drive._ease_turn_in_out(0.9) > 0.9,
		"Turn does not ease out"
	)
	_check(
		is_equal_approx(drive._late_fishtail_amount(0.4), 0.0),
		"Fishtail starts too early"
	)
	_check(
		drive._late_fishtail_amount(0.8) > 0.8,
		"Fishtail does not peak near the end of the turn"
	)
	_check(
		is_equal_approx(drive._late_fishtail_amount(1.0), 0.0),
		"Fishtail does not settle at turn completion"
	)

	# A missed exit continues forward seamlessly instead of visibly resetting.
	drive.highway_column = MAP.HIGHWAY_COLUMNS - 1
	drive.highway_lane = 0
	drive.queued_highway_lane = 0
	drive.visual_world_position = drive._highway_cell_center(drive.highway_column, 0)
	drive.move_from = drive.visual_world_position
	var missed_exit_position: Vector2 = drive.visual_world_position
	drive._begin_highway_step()
	_check(drive.missed_turns == 1, "Missed highway exit was not counted")
	_check(drive.highway_lap == 1, "Missed highway exit did not advance the visual highway")
	_check(drive.highway_column == 0, "Missed highway exit did not begin the next highway span")
	_check(drive.road_kind == "highway", "Missed exit left highway state")
	_check(
		drive.move_to.x > missed_exit_position.x,
		"Missed highway exit visibly teleports backward"
	)
	_check(
		not drive.status_label.text.contains("LOOP"),
		"Missed highway exit still exposes the loop in UI text"
	)
	if navigation != null:
		navigation._process(0.0)
		var missed_instruction: Dictionary = navigation._current_instruction()
		_check(
			missed_instruction.get("title") == "Missed exit",
			"GPS banner does not announce a missed highway exit"
		)
		navigation.missed_exit_notice_remaining = 0.0
		var rerouted_instruction: Dictionary = navigation._current_instruction()
		_check(
			rerouted_instruction.get("title") != "Missed exit",
			"GPS banner does not return to normal guidance after missed-exit notice"
		)

	# Lane four reaches the shifted city connector even after a missed exit.
	drive.highway_column = MAP.HIGHWAY_COLUMNS - 1
	drive.highway_lane = MAP.HIGHWAY_EXIT_LANE
	drive.queued_highway_lane = MAP.HIGHWAY_EXIT_LANE
	drive.visual_world_position = drive._highway_cell_center(
		MAP.HIGHWAY_COLUMNS - 1,
		MAP.HIGHWAY_EXIT_LANE
	)
	drive.visual_cell_scale = 0.5
	drive.move_from = drive.visual_world_position
	drive.scale_from = 0.5
	drive._begin_highway_step()
	_check(drive.road_kind == "connector_two", "Correct highway lane missed city connector")
	_check(is_equal_approx(drive.scale_to, 1.5), "City connector should grow smoothly to full city scale")

	# The city connector decelerates from highway speed down to 0.8x neighborhood speed.
	var active_exit_rect: Rect2 = drive._connector_two_rect()
	drive.visual_world_position.x = active_exit_rect.position.x
	var exit_start_speed: float = drive._current_world_speed()
	drive.visual_world_position.x = active_exit_rect.position.x + active_exit_rect.size.x * 0.5
	var exit_mid_speed: float = drive._current_world_speed()
	drive.visual_world_position.x = active_exit_rect.end.x
	var exit_end_speed: float = drive._current_world_speed()
	_check(exit_mid_speed < exit_start_speed, "City off-ramp does not slow through the middle")
	_check(exit_end_speed < exit_mid_speed, "City off-ramp does not keep slowing")
	_check(
		is_equal_approx(
			exit_end_speed,
			drive.CITY_WORLD_SPEED
		),
		"City off-ramp does not reach 0.8x neighborhood speed"
	)

	drive.visual_world_position = drive._city_entry_point()
	drive.visual_cell_scale = drive.CITY_CAR_SCALE
	drive.move_from = drive.visual_world_position
	drive.scale_from = drive.CITY_CAR_SCALE
	drive._begin_city_step()
	_check(drive.road_kind == "city", "Second connector did not enter city")
	_check(
		drive.move_to == drive._city_entry_center_point(),
		"Off-ramp does not drive forward into the first city block"
	)
	_check(
		is_equal_approx(drive.move_to.y, drive.visual_world_position.y),
		"Off-ramp city handoff drags the car sideways"
	)
	_check(is_equal_approx(drive.visual_cell_scale, 1.5), "City entry should preserve the smoothly-grown city size")
	_check(
		is_equal_approx(
			drive._current_world_speed(),
			drive.CITY_WORLD_SPEED
		),
		"City speed is not 0.8x neighborhood speed"
	)
	drive.visual_cell_scale = drive.CITY_CAR_SCALE
	drive._update_car_visual()
	_check(
		is_equal_approx(drive.player_car.scale.x, drive.CAR_REFERENCE_SCALE * drive.CITY_CAR_SCALE),
		"Rendered city car scale does not match the 1.5x city target"
	)

	drive.road_kind = "highway"
	drive.visual_cell_scale = 1.0
	drive._update_car_visual()
	_check(
		drive.HIGHWAY_PLAYER_VISUAL_MULTIPLIER >= 2.5,
		"Highway car is still too small relative to the lane"
	)
	_check(
		is_equal_approx(
			drive.player_car.scale.x,
			drive.CAR_REFERENCE_SCALE * drive.HIGHWAY_PLAYER_VISUAL_MULTIPLIER
		),
		"Highway player car scale multiplier is not applied"
	)

	var highway_effective_scale: float = (
		MAP.car_scale_for_cell(MAP.HIGHWAY_CELL)
		* drive.HIGHWAY_PLAYER_VISUAL_MULTIPLIER
	)

	drive.road_kind = "connector_one"
	drive.visual_world_position = Vector2(
		MAP.CONNECTOR_ONE_RECT.end.x,
		MAP.highway_entry_point().y
	)
	_check(
		is_equal_approx(
			drive._rendered_car_section_scale(),
			highway_effective_scale
		),
		"On-ramp does not finish at the highway car size"
	)

	drive.road_kind = "connector_two"
	drive.visual_world_position = Vector2(
		drive._connector_two_rect().position.x,
		drive._highway_cell_center(
			MAP.HIGHWAY_COLUMNS - 1,
			MAP.HIGHWAY_EXIT_LANE
		).y
	)
	_check(
		is_equal_approx(
			drive._rendered_car_section_scale(),
			highway_effective_scale
		),
		"Off-ramp does not start at the highway car size"
	)

	# Reaching the destination now enters the lot, then requires two separate
	# steering decisions: choose an aisle, then choose a parking space.
	_check(is_equal_approx(drive.CITY_WORLD_SPEED, 36.0), "City speed was not increased slightly")
	_check(drive._parking_space_is_open(-1, 1), "Upper aisle right space should be open")
	_check(not drive._parking_space_is_open(-1, -1), "Upper aisle left space should be occupied")
	_check(drive._parking_space_is_open(1, -1), "Lower aisle left space should be open")
	_check(not drive._parking_space_is_open(1, 1), "Lower aisle right space should be occupied")

	drive.road_kind = "city"
	drive.city_cell = MAP.CITY_DESTINATION
	drive.parking_maneuver_started = false
	drive.parking_target_index = -1
	drive.parking_lane_choice = 0
	drive.parking_phase = 0
	drive.drive_complete = false
	drive.visual_world_position = drive._city_cell_center(MAP.CITY_DESTINATION)
	drive.move_from = drive.visual_world_position
	drive.scale_from = drive.CITY_CAR_SCALE

	if navigation != null:
		var lot_instruction: Dictionary = navigation._current_instruction()
		_check(
			lot_instruction.get("title", "") == "Turn right"
			and lot_instruction.get("subtitle", "") == "Into parking lot",
			"GPS does not direct the final turn into the parking lot"
		)

	drive._begin_city_step()
	_check(drive.road_kind == "city", "Parking turn leaves city mode before reaching the driveway")
	_check(
		drive.move_to == drive._parking_entry_point(),
		"City route does not lead to the parking-lot entrance"
	)
	_check(
		is_equal_approx(drive.move_to.y, drive.visual_world_position.y),
		"Parking entrance pulls the car sideways instead of forward"
	)
	if navigation != null:
		var parking_route_points: PackedVector2Array = navigation._current_route_world_points()
		_check(
			parking_route_points[parking_route_points.size() - 1]
				== drive._parking_entry_point(),
			"Blue city route does not finish at the parking-lot entrance"
		)

	drive.visual_world_position = drive.move_to
	drive.move_from = drive.visual_world_position
	drive._begin_city_step()
	_check(drive.road_kind == "parking", "Parking entrance did not switch to parking mode")
	_check(drive.move_to == drive._parking_aisle_point(), "Parking entry does not drive into the aisle")
	_check(
		is_equal_approx(drive.move_to.y, drive.visual_world_position.y),
		"Parking-lot entry drags the car sideways"
	)

	drive.visual_world_position = drive.move_to
	drive.move_from = drive.visual_world_position
	drive._begin_parking_step()
	_check(drive.blocked_this_step, "Car should wait at the aisle choice")
	if navigation != null:
		var choose_aisle_instruction: Dictionary = navigation._current_instruction()
		_check(
			choose_aisle_instruction.get("title", "") == "Choose an aisle",
			"GPS does not ask the player to choose an aisle"
		)

	# First left/right input only moves into an aisle; it must not park.
	drive._handle_parking_turn(-1)
	_check(drive.parking_lane_choice == -1, "Left input did not choose the upper aisle")
	_check(drive.parking_phase == 1, "Choosing an aisle skipped directly to parking")
	_check(
		drive.move_to == drive._parking_lane_point(-1),
		"Choosing an aisle does not target the aisle lane"
	)
	_check(
		is_equal_approx(drive.move_to.x, drive.visual_world_position.x),
		"Choosing an aisle drags sideways instead of following the turn"
	)
	_check(not drive.drive_complete, "Choosing an aisle completed parking too early")

	drive.visual_world_position = drive.move_to
	drive.move_from = drive.visual_world_position
	drive._begin_parking_step()
	_check(drive.parking_phase == 2, "Aisle arrival did not wait for a parking-space choice")
	_check(drive.blocked_this_step, "Car should stop in the aisle before choosing a space")
	if navigation != null:
		var choose_space_instruction: Dictionary = navigation._current_instruction()
		_check(
			choose_space_instruction.get("title", "") == "Choose a parking spot",
			"GPS does not ask for a second parking turn"
		)

	# Turning toward the occupied car must do nothing.
	drive._handle_parking_turn(-1)
	_check(drive.parking_phase == 2, "Occupied space should not advance parking")
	_check(drive.parking_target_index == -1, "Occupied space should not become the target")

	# Turning the other way enters the open space.
	drive._handle_parking_turn(1)
	_check(drive.parking_target_index == 1, "Open parking space was not selected")
	_check(drive.parking_phase == 3, "Open space did not start final parking move")
	_check(
		drive.move_to == drive._parking_space_center(-1, 1),
		"Final parking move does not target the selected open space"
	)
	_check(
		is_equal_approx(drive.move_to.y, drive.visual_world_position.y),
		"Final parking turn drags sideways instead of entering the space"
	)

	drive.visual_world_position = drive.move_to
	drive.move_from = drive.visual_world_position
	drive._begin_parking_step()
	_check(drive.drive_complete, "Drive did not complete after parking in the selected open space")

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
