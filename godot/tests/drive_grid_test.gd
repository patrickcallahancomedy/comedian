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

	_check(drive != null, "Grid controller missing")
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

	var parking_rect: Rect2 = drive._parking_space_rect()
	var venue_rect: Rect2 = drive._venue_rect()
	var destination_center: Vector2 = drive._city_cell_center(MAP.CITY_DESTINATION)
	var parking_stop: Vector2 = drive._parking_stop_point()
	_check(
		parking_rect.has_point(parking_stop),
		"Destination parking space does not contain the curbside stop point"
	)
	_check(
		parking_stop.x > destination_center.x,
		"Final parking stop is not shifted toward the venue curb"
	)
	_check(
		venue_rect.position.x > destination_center.x,
		"Venue should sit outside the road beside the parked car"
	)
	_check(
		venue_rect.position.x - parking_stop.x < 28.0,
		"Venue is too far from the parked car to read on mobile"
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
		var route_world_points := navigation._route_world_points(initial_route)
		_check(
			route_world_points.size() >= 2,
			"Navigation illumination has no world segments"
		)
		_check(
			route_world_points[0].distance_to(drive.visual_world_position) < 0.5,
			"Navigation illumination is not anchored to the visual car position"
		)
		_check(
			navigation.ROUTE_LIGHT_WIDTH_RATIO >= 0.85
			and navigation.ROUTE_LIGHT_WIDTH_RATIO <= 0.95,
			"Navigation illumination does not cover most of the road"
		)
		_check(
			navigation.ROUTE_LIGHT_COLOR.a <= 0.15,
			"Navigation illumination is not subtle"
		)
		_check(
			navigation.ROUTE_START_AHEAD_RATIO >= 0.15
			and navigation.ROUTE_START_AHEAD_RATIO <= 0.25,
			"Navigation illumination does not start near the car"
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

	# Reaching the destination performs one short curbside parking move before
	# the trip completes.
	drive.road_kind = "city"
	drive.city_cell = MAP.CITY_DESTINATION
	drive.parking_maneuver_started = false
	drive.drive_complete = false
	drive.visual_world_position = drive._city_cell_center(MAP.CITY_DESTINATION)
	drive.move_from = drive.visual_world_position
	drive.scale_from = drive.CITY_CAR_SCALE
	drive._begin_city_step()
	_check(drive.parking_maneuver_started, "Destination did not start curbside parking")
	_check(
		drive.move_to == drive._parking_stop_point(),
		"Parking maneuver does not target the curbside stop point"
	)
	_check(not drive.drive_complete, "Drive completed before curbside parking finished")

	drive.visual_world_position = drive.move_to
	drive.move_from = drive.visual_world_position
	drive._begin_city_step()
	_check(drive.drive_complete, "Drive did not complete after curbside parking")

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
