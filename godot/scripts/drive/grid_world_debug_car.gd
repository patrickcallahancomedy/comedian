extends Control

const PLAYER_CAR_TEXTURE = preload("res://assets/car/player_car_top.png")

const BASE_SPEED := 25.0
const SPEED_MULTIPLIERS := [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
const SPEED_LABELS := ["1×", "2×", "3×", "4×", "5×", "6×", "7×", "8×", "9×", "10×"]
const CAR_HEIGHT := 18.0
const DRIVE_VIEW_CAR_HEIGHT := 64.0
const TURN_NONE := 0
const TURN_LEFT := -1
const TURN_RIGHT := 1

var current_node := -1
var next_node := -1
var previous_node := -1
var world_position := Vector2.ZERO
var running := false
var finished := false
var waiting_for_turn := false
var speed_index := 0
var queued_turn := TURN_NONE
var drive_forward := Vector2.UP

@onready var map = $"../Map"
@onready var run_button: Button = $"../DebugPanel/Content/DRIVE/RunButton"
@onready var reset_button: Button = $"../DebugPanel/Content/DRIVE/ResetButton"
@onready var speed_button: HSlider = $"../DebugPanel/Content/DRIVE/SpeedButton"
@onready var speed_value_label: Label = $"../DebugPanel/Content/DRIVE/SpeedValueLabel"
@onready var status_label: Label = $"../DebugPanel/Content/DRIVE/StatusLabel"
@onready var left_button: Button = $"../SteerLeftButton"
@onready var right_button: Button = $"../SteerRightButton"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	run_button.pressed.connect(_run)
	reset_button.pressed.connect(_reset)
	speed_button.value_changed.connect(_set_speed)
	left_button.pressed.connect(_turn_left)
	right_button.pressed.connect(_turn_right)
	_set_speed(speed_button.value)
	map.map_generated.connect(_reset)
	call_deferred("_reset")


func _process(delta: float) -> void:
	queue_redraw()

	if not running or finished:
		return

	var remaining_time := delta

	while remaining_time > 0.0 and running and not finished:
		if next_node < 0:
			_choose_next_node()
			if next_node < 0:
				break

		var target := Vector2(map.generator.nodes[next_node])
		var distance := world_position.distance_to(target)

		if distance <= 0.0001:
			_arrive_at_next_node()
			continue

		var road_class := map.generator.edge_class(current_node, next_node)
		var speed := (
			BASE_SPEED
			* float(SPEED_MULTIPLIERS[speed_index])
			* _road_speed_multiplier(road_class)
		)
		var time_to_target := distance / speed

		if remaining_time >= time_to_target:
			world_position = target
			remaining_time -= time_to_target
			_arrive_at_next_node()
		else:
			world_position = world_position.move_toward(
				target,
				speed * remaining_time
			)
			remaining_time = 0.0

	_sync_drive_camera()


func _draw() -> void:
	if current_node < 0:
		return

	var screen := (
		map.drive_camera_screen_position()
		if map.drive_camera_enabled
		else map.world_to_screen(world_position)
	)
	var car_height := (
		DRIVE_VIEW_CAR_HEIGHT
		if (
			map.drive_camera_enabled
			and not map.show_whole_map
			and not map.zoom_map_enabled
		)
		else CAR_HEIGHT
	)

	var car_rotation := 0.0
	if not map.drive_camera_enabled:
		car_rotation = Vector2.UP.angle_to(drive_forward)

	var texture_size := PLAYER_CAR_TEXTURE.get_size()
	var aspect := texture_size.x / maxf(texture_size.y, 1.0)
	var car_size := Vector2(car_height * aspect, car_height)

	draw_set_transform(screen, car_rotation, Vector2.ONE)
	draw_texture_rect(
		PLAYER_CAR_TEXTURE,
		Rect2(-car_size * 0.5, car_size),
		false
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _run() -> void:
	if finished:
		_reset()
	if current_node < 0:
		return
	if next_node < 0:
		_choose_next_node()
	if next_node < 0:
		return

	waiting_for_turn = false
	running = true
	status_label.text = "DRIVING"
	_sync_drive_camera()


func _reset() -> void:
	running = false
	finished = false
	waiting_for_turn = false
	queued_turn = TURN_NONE
	previous_node = -1
	current_node = map.generator.home_node
	next_node = -1

	if current_node < 0 or map.generator.venue_access_node < 0:
		status_label.text = "NO ROUTE"
		queue_redraw()
		return

	world_position = Vector2(map.generator.nodes[current_node])

	# The route is used only to point the parked car down a sensible first
	# street. Once RUN is pressed, every later turn is controlled by the player.
	var starter_route := map.generator.shortest_path(
		current_node,
		map.generator.venue_access_node
	)
	if starter_route.size() >= 2:
		next_node = int(starter_route[1])
		var initial_delta := (
			Vector2(map.generator.nodes[next_node]) - world_position
		)
		if initial_delta.length_squared() > 0.0001:
			drive_forward = initial_delta.normalized()
	else:
		drive_forward = Vector2.UP

	status_label.text = "READY - STEER LEFT / RIGHT"
	_sync_drive_camera()
	queue_redraw()


func _arrive_at_next_node() -> void:
	previous_node = current_node
	current_node = next_node
	next_node = -1
	world_position = Vector2(map.generator.nodes[current_node])

	if _is_venue_node(current_node):
		_finish()
		return

	_choose_next_node()


func _choose_next_node() -> void:
	if current_node < 0 or finished:
		return

	# Hidden merge links are real car movement even though they are not drawn.
	# Once the car enters one, continue through the short merge chain.
	if previous_node >= 0:
		var incoming_class := map.generator.edge_class(
			previous_node,
			current_node
		)
		if incoming_class < 0:
			var automatic := _automatic_hidden_continuation()
			if automatic >= 0:
				_set_next_node(automatic, false)
				return
		elif incoming_class == map.generator.RoadClass.RAMP:
			# At the highway end of a ramp, enter the short hidden merge chain
			# instead of treating the visually finished ramp as a dead end.
			var hidden_merge := _first_hidden_candidate()
			if hidden_merge >= 0:
				_set_next_node(hidden_merge, false)
				return

	# The highway is one-way. LEFT/RIGHT can queue the off-ramp; otherwise the
	# car keeps going forward and wraps to the beginning if the exit is missed.
	if _is_highway_spine_node(current_node):
		_choose_highway_next()
		return

	var candidates := _visible_candidates()
	if candidates.is_empty():
		_stop_for_turn("DEAD END")
		return

	var straight := -1
	var left := -1
	var right := -1

	for candidate_value in candidates:
		var candidate: int = int(candidate_value)
		var direction := (
			Vector2(map.generator.nodes[candidate])
			- Vector2(map.generator.nodes[current_node])
		).normalized()
		var relation := _turn_relation(drive_forward, direction)
		if relation == TURN_LEFT:
			left = candidate
		elif relation == TURN_RIGHT:
			right = candidate
		else:
			straight = candidate

	if queued_turn == TURN_LEFT and left >= 0:
		queued_turn = TURN_NONE
		_set_next_node(left, true)
		return
	if queued_turn == TURN_RIGHT and right >= 0:
		queued_turn = TURN_NONE
		_set_next_node(right, true)
		return
	if straight >= 0:
		_set_next_node(straight, true)
		return

	_stop_for_turn("TURN LEFT OR RIGHT")


func _choose_highway_next() -> void:
	var forward_neighbor := -1
	var exit_neighbor := -1
	var exit_turn := TURN_NONE
	var travel_sign := _highway_travel_sign()
	var center := Vector2(map.generator.nodes[current_node])
	var horizontal := _highway_is_horizontal()

	for neighbor_value in map.generator.adjacency[current_node]:
		var neighbor: int = int(neighbor_value)
		if neighbor == previous_node:
			continue

		var road_class := map.generator.edge_class(current_node, neighbor)
		if road_class == map.generator.RoadClass.HIGHWAY:
			var point := Vector2(map.generator.nodes[neighbor])
			var delta_axis := (
				point.x - center.x
				if horizontal
				else point.y - center.y
			)
			if signf(delta_axis) == float(travel_sign):
				forward_neighbor = neighbor
		elif road_class < 0 and _hidden_branch_is_off_ramp(neighbor):
			exit_neighbor = neighbor
			var branch_direction := (
				Vector2(map.generator.nodes[neighbor]) - center
			).normalized()
			exit_turn = _turn_relation(drive_forward, branch_direction)

	if (
		exit_neighbor >= 0
		and queued_turn != TURN_NONE
		and queued_turn == exit_turn
	):
		queued_turn = TURN_NONE
		_set_next_node(exit_neighbor, false)
		status_label.text = "EXIT"
		return

	if forward_neighbor >= 0:
		_set_next_node(forward_neighbor, true)
		status_label.text = "HIGHWAY"
		return

	_wrap_highway()


func _wrap_highway() -> void:
	if map.generator.highway_nodes.size() != 2:
		_stop_for_turn("END OF HIGHWAY")
		return

	var a: int = int(map.generator.highway_nodes[0])
	var b: int = int(map.generator.highway_nodes[1])
	var pa := Vector2(map.generator.nodes[a])
	var pb := Vector2(map.generator.nodes[b])
	var horizontal := _highway_is_horizontal()
	var travel_sign := _highway_travel_sign()

	var restart := a
	if horizontal:
		restart = a if signf(pb.x - pa.x) == float(travel_sign) else b
	else:
		restart = a if signf(pb.y - pa.y) == float(travel_sign) else b

	previous_node = -1
	current_node = restart
	world_position = Vector2(map.generator.nodes[current_node])
	next_node = -1
	status_label.text = "HIGHWAY"
	_choose_highway_next()


func _first_hidden_candidate() -> int:
	for neighbor_value in map.generator.adjacency[current_node]:
		var neighbor: int = int(neighbor_value)
		if neighbor == previous_node:
			continue
		if map.generator.edge_class(current_node, neighbor) < 0:
			return neighbor
	return -1


func _automatic_hidden_continuation() -> int:
	var candidates: Array[int] = []
	for neighbor_value in map.generator.adjacency[current_node]:
		var neighbor: int = int(neighbor_value)
		if neighbor == previous_node:
			continue
		candidates.append(neighbor)

	if candidates.size() == 1:
		return candidates[0]

	# Prefer the rest of the merge chain before selecting a visible road.
	for neighbor in candidates:
		if map.generator.edge_class(current_node, neighbor) < 0:
			return neighbor

	for neighbor in candidates:
		if map.generator.edge_class(current_node, neighbor) == map.generator.RoadClass.RAMP:
			return neighbor

	return -1


func _visible_candidates() -> Array[int]:
	var result: Array[int] = []
	for neighbor_value in map.generator.adjacency[current_node]:
		var neighbor: int = int(neighbor_value)
		if neighbor == previous_node:
			continue
		if map.generator.edge_class(current_node, neighbor) < 0:
			continue
		result.append(neighbor)
	return result


func _set_next_node(node_id: int, update_forward: bool) -> void:
	next_node = node_id
	waiting_for_turn = false

	if update_forward:
		var delta := (
			Vector2(map.generator.nodes[next_node])
			- Vector2(map.generator.nodes[current_node])
		)
		if delta.length_squared() > 0.0001:
			drive_forward = delta.normalized()

	if running:
		status_label.text = _road_status(
			map.generator.edge_class(current_node, next_node)
		)


func _road_status(road_class: int) -> String:
	match road_class:
		map.generator.RoadClass.NEIGHBORHOOD:
			return "NEIGHBORHOOD"
		map.generator.RoadClass.CITY:
			return "CITY"
		map.generator.RoadClass.CONNECTOR:
			return "CONNECTOR"
		map.generator.RoadClass.RAMP:
			return "RAMP"
		map.generator.RoadClass.HIGHWAY:
			return "HIGHWAY"
	return "MERGING"


func _road_speed_multiplier(road_class: int) -> float:
	if road_class == map.generator.RoadClass.HIGHWAY:
		return 2.0
	if road_class == map.generator.RoadClass.RAMP:
		return 1.5
	if road_class < 0:
		return 1.5
	return 1.0


func _turn_left() -> void:
	_queue_turn(TURN_LEFT)


func _turn_right() -> void:
	_queue_turn(TURN_RIGHT)


func _queue_turn(turn: int) -> void:
	if finished:
		return
	queued_turn = turn
	status_label.text = "LEFT QUEUED" if turn == TURN_LEFT else "RIGHT QUEUED"

	if waiting_for_turn:
		waiting_for_turn = false
		_choose_next_node()
		if next_node >= 0:
			running = true


func _stop_for_turn(message: String) -> void:
	next_node = -1
	waiting_for_turn = true
	running = false
	status_label.text = message


func _turn_relation(forward: Vector2, candidate: Vector2) -> int:
	if forward.length_squared() <= 0.0001:
		return TURN_NONE
	var dot := forward.normalized().dot(candidate.normalized())
	if dot > 0.75:
		return TURN_NONE
	var cross := forward.normalized().cross(candidate.normalized())
	return TURN_LEFT if cross < 0.0 else TURN_RIGHT


func _is_highway_spine_node(node_id: int) -> bool:
	for neighbor_value in map.generator.adjacency[node_id]:
		var neighbor: int = int(neighbor_value)
		if (
			map.generator.edge_class(node_id, neighbor)
			== map.generator.RoadClass.HIGHWAY
		):
			return true
	return false


func _hidden_branch_is_off_ramp(first_hidden_node: int) -> bool:
	var parent := current_node
	var cursor := first_hidden_node

	for _step in range(3):
		for neighbor_value in map.generator.adjacency[cursor]:
			var neighbor: int = int(neighbor_value)
			if neighbor == parent:
				continue
			var road_class := map.generator.edge_class(cursor, neighbor)
			if road_class == map.generator.RoadClass.RAMP:
				return not map.generator.is_on_ramp_edge(cursor, neighbor)

		var next_hidden := -1
		for neighbor_value in map.generator.adjacency[cursor]:
			var neighbor: int = int(neighbor_value)
			if neighbor == parent:
				continue
			if map.generator.edge_class(cursor, neighbor) < 0:
				next_hidden = neighbor
				break

		if next_hidden < 0:
			break
		parent = cursor
		cursor = next_hidden

	return false


func _highway_is_horizontal() -> bool:
	if map.generator.highway_nodes.size() != 2:
		return true
	var a := Vector2i(
		map.generator.nodes[int(map.generator.highway_nodes[0])]
	)
	var b := Vector2i(
		map.generator.nodes[int(map.generator.highway_nodes[1])]
	)
	return a.y == b.y


func _highway_travel_sign() -> int:
	var neighborhood_center := Vector2i(
		map.generator.neighborhood_rect.get_center()
	)
	var city_center := Vector2i(map.generator.city_rect.get_center())
	if _highway_is_horizontal():
		return 1 if city_center.x >= neighborhood_center.x else -1
	return 1 if city_center.y >= neighborhood_center.y else -1


func _is_venue_node(node_id: int) -> bool:
	var point := Vector2i(map.generator.nodes[node_id])
	var rect = map.generator.venue_block
	return point in [
		rect.position,
		rect.position + Vector2i(rect.size.x, 0),
		rect.position + Vector2i(0, rect.size.y),
		rect.end,
	]


func _sync_drive_camera() -> void:
	if current_node < 0:
		return
	map.set_drive_camera(world_position, drive_forward)


func _set_speed(value: float) -> void:
	speed_index = clampi(
		int(round(value)) - 1,
		0,
		SPEED_MULTIPLIERS.size() - 1
	)
	speed_value_label.text = "SPEED  %s" % SPEED_LABELS[speed_index]


func _finish() -> void:
	running = false
	finished = true
	waiting_for_turn = false
	next_node = -1
	status_label.text = "ARRIVED"
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_A, KEY_LEFT:
			_turn_left()
		KEY_D, KEY_RIGHT:
			_turn_right()
		KEY_W, KEY_UP, KEY_SPACE:
			_run()
		KEY_R:
			_reset()
