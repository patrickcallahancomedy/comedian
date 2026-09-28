extends Label

## GPS presentation for the rebuilt continuous driving world.
## Keeps the approved dark slate banner and 2.5 second update behavior.

const MAP = preload("res://scripts/drive/drive_world_map.gd")

const ROUTE_SHADOW_COLOR := Color(0.02, 0.08, 0.18, 0.52)
const ROUTE_LINE_COLOR := Color(0.10, 0.42, 0.96, 0.98)
const ROUTE_SHADOW_WIDTH_RATIO := 0.48
const ROUTE_LINE_WIDTH_RATIO := 0.32

const BANNER_COLOR := Color(0.10, 0.14, 0.19, 0.96)
const BANNER_TEXT_COLOR := Color.WHITE
const BANNER_SUBTEXT_COLOR := Color(0.88, 0.96, 0.92, 0.92)
const BANNER_MARGIN := 16.0
const BANNER_HEIGHT := 82.0
const BANNER_RADIUS := 12.0
const BANNER_VISIBLE_SECONDS := 2.5
const BANNER_REPEAT_DELAY_SECONDS := 0.2
const MISSED_EXIT_NOTICE_SECONDS := 1.6

@onready var drive = $"../CityMap"
@onready var status_label: Label = $"../StatusLabel"

var last_instruction_key := ""
var last_close_reminder_key := ""
var banner_visible_remaining := 0.0
var banner_repeat_delay_remaining := 0.0
var last_missed_turns := 0
var missed_exit_notice_remaining := 0.0


func _ready() -> void:
	text = ""
	z_index = 2
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if drive != null:
		if drive.missed_turns > last_missed_turns:
			last_missed_turns = drive.missed_turns
			missed_exit_notice_remaining = MISSED_EXIT_NOTICE_SECONDS
		elif drive.missed_turns < last_missed_turns:
			last_missed_turns = drive.missed_turns

	if missed_exit_notice_remaining > 0.0:
		missed_exit_notice_remaining = maxf(
			0.0,
			missed_exit_notice_remaining - delta
		)

	_update_instruction_banner(delta)
	_update_status_visibility()
	queue_redraw()


func _update_status_visibility() -> void:
	if drive == null or status_label == null:
		return
	if not drive.started or drive.drive_complete:
		status_label.show()
	else:
		status_label.hide()


func _update_instruction_banner(delta: float) -> void:
	if drive == null or not drive.started or drive.drive_complete:
		last_instruction_key = ""
		last_close_reminder_key = ""
		banner_visible_remaining = 0.0
		banner_repeat_delay_remaining = 0.0
		return

	var instruction := _current_instruction()
	if instruction.is_empty():
		return

	var instruction_key := String(instruction.get("maneuver_key", ""))
	if instruction_key.is_empty():
		instruction_key = "%s|%s" % [
			String(instruction.get("turn", "")),
			String(instruction.get("title", "")),
		]

	var blocks := int(instruction.get("blocks", -1))
	var is_close := blocks == 1
	var is_persistent := bool(instruction.get("persistent", false))

	if is_persistent:
		last_instruction_key = instruction_key
		banner_visible_remaining = BANNER_VISIBLE_SECONDS
		banner_repeat_delay_remaining = 0.0
		return

	if instruction_key != last_instruction_key:
		last_instruction_key = instruction_key
		last_close_reminder_key = ""
		banner_visible_remaining = BANNER_VISIBLE_SECONDS
		banner_repeat_delay_remaining = 0.0
		return

	if is_close and last_close_reminder_key != instruction_key:
		last_close_reminder_key = instruction_key
		banner_visible_remaining = BANNER_VISIBLE_SECONDS
		banner_repeat_delay_remaining = 0.0
		return

	if banner_visible_remaining > 0.0:
		banner_visible_remaining = maxf(0.0, banner_visible_remaining - delta)
		if banner_visible_remaining <= 0.0 and is_close:
			banner_repeat_delay_remaining = BANNER_REPEAT_DELAY_SECONDS
	elif is_close:
		banner_repeat_delay_remaining = maxf(
			0.0,
			banner_repeat_delay_remaining - delta
		)
		if banner_repeat_delay_remaining <= 0.0:
			banner_visible_remaining = BANNER_VISIBLE_SECONDS


func _draw() -> void:
	if drive == null or not drive.started or drive.drive_complete:
		return
	_draw_route_line()
	_draw_instruction_banner()


func _draw_route_line() -> void:
	if drive.road_kind != "neighborhood" and drive.road_kind != "city":
		return

	var route: Array[String] = drive.current_local_route()
	if route.is_empty():
		return

	var world_points := PackedVector2Array([drive.visual_world_position])
	for node_id in route:
		var point := MAP.node_position(drive.local_area, node_id)
		if world_points[world_points.size() - 1].distance_to(point) > 0.5:
			world_points.append(point)

	if world_points.size() < 2:
		return

	var screen_points := PackedVector2Array()
	for point in world_points:
		screen_points.append(drive._world_to_screen(point))

	var road_width := MAP.LOCAL_ROAD_WIDTH * drive._current_world_zoom()
	draw_polyline(
		screen_points,
		ROUTE_SHADOW_COLOR,
		road_width * ROUTE_SHADOW_WIDTH_RATIO,
		true
	)
	draw_polyline(
		screen_points,
		ROUTE_LINE_COLOR,
		road_width * ROUTE_LINE_WIDTH_RATIO,
		true
	)


func _current_instruction() -> Dictionary:
	if drive.road_kind == "highway" and missed_exit_notice_remaining > 0.0:
		return {
			"turn": "straight",
			"title": "Missed exit",
			"subtitle": "Continue ahead — rerouting",
			"maneuver_key": "highway|missed",
		}

	match drive.road_kind:
		"neighborhood", "city":
			return _local_instruction()
		"onramp":
			return {
				"turn": "straight",
				"title": "Merge onto highway",
				"subtitle": "Continue on ramp",
				"maneuver_key": "onramp|merge",
			}
		"highway":
			if drive.highway_lane < MAP.HIGHWAY_EXIT_LANE:
				return {
					"turn": "right",
					"title": "Move right",
					"subtitle": "Use lane 4 for the exit",
					"maneuver_key": "highway|move_right",
				}
			return {
				"turn": "straight",
				"title": "Stay in lane 4",
				"subtitle": "Exit ahead",
				"maneuver_key": "highway|exit",
			}
		"offramp":
			return {
				"turn": "straight",
				"title": "Take the exit",
				"subtitle": "Continue into the city",
				"maneuver_key": "offramp|city",
			}
		"parking":
			if drive.parking_phase == 0:
				return {
					"turn": "straight",
					"title": "Enter parking lot",
					"subtitle": "Continue ahead",
					"maneuver_key": "parking|enter",
				}
			if drive.parking_phase == 1:
				return {
					"turn": "right",
					"title": "Park on right",
					"subtitle": "",
					"persistent": drive.blocked_this_step,
					"blocks": 0 if drive.blocked_this_step else 1,
					"maneuver_key": "parking|right_space",
				}
			return {
				"turn": "straight",
				"title": "Parking",
				"subtitle": "Pull into the space",
				"maneuver_key": "parking|finish",
			}
	return {}


func _local_instruction() -> Dictionary:
	if (
		drive.road_kind == "city"
		and drive.local_node == MAP.CITY_PARKING_NODE
	):
		return {
			"turn": "right",
			"title": "Turn right",
			"subtitle": "" if drive.blocked_this_step else "Into parking lot",
			"persistent": drive.blocked_this_step,
			"blocks": 0 if drive.blocked_this_step else 1,
			"maneuver_key": "city|parking_entry",
		}

	var route: Array[String] = drive.current_local_route()
	if route.size() < 2:
		return {
			"turn": "straight",
			"title": "Continue straight",
			"subtitle": "Follow the blue route",
			"maneuver_key": "%s|continue" % drive.road_kind,
		}

	var incoming: Vector2i = drive.heading
	for index in range(1, route.size()):
		var from_point := MAP.node_position(drive.local_area, route[index - 1])
		var to_point := MAP.node_position(drive.local_area, route[index])
		var outgoing := MAP.cardinal_direction(from_point, to_point)
		var kind := MAP.turn_kind(incoming, outgoing)

		if kind == "left" or kind == "right":
			var blocks := index
			var at_turn := (
				drive.blocked_this_step
				and index == 1
			)
			return {
				"turn": kind,
				"title": "Turn %s" % kind,
				"subtitle": "" if at_turn else "In %d block%s" % [
					blocks,
					"" if blocks == 1 else "s",
				],
				"blocks": 0 if at_turn else blocks,
				"persistent": at_turn,
				"maneuver_key": "%s|%s|%s" % [
					drive.road_kind,
					kind,
					route[index - 1],
				],
			}
		incoming = outgoing

	if drive.road_kind == "neighborhood":
		return {
			"turn": "straight",
			"title": "Continue straight",
			"subtitle": "Ramp ahead",
			"maneuver_key": "neighborhood|ramp",
		}

	return {
		"turn": "straight",
		"title": "Continue straight",
		"subtitle": "Venue ahead",
		"maneuver_key": "city|venue",
	}


func _draw_instruction_banner() -> void:
	if banner_visible_remaining <= 0.0:
		return

	var instruction := _current_instruction()
	if instruction.is_empty():
		return

	var banner_width := minf(size.x - BANNER_MARGIN * 2.0, 420.0)
	var banner_rect := Rect2(
		Vector2((size.x - banner_width) * 0.5, BANNER_MARGIN),
		Vector2(banner_width, BANNER_HEIGHT)
	)
	draw_style_box(_make_banner_style(), banner_rect)

	var icon_rect := Rect2(
		banner_rect.position + Vector2(14.0, 14.0),
		Vector2(48.0, 48.0)
	)
	_draw_turn_icon(icon_rect, String(instruction.get("turn", "straight")))

	var font := get_theme_default_font()
	var text_x := banner_rect.position.x + 76.0

	draw_string(
		font,
		Vector2(text_x, banner_rect.position.y + 32.0),
		String(instruction.get("title", "Continue")),
		HORIZONTAL_ALIGNMENT_LEFT,
		banner_rect.end.x - text_x - 12.0,
		22,
		BANNER_TEXT_COLOR
	)
	draw_string(
		font,
		Vector2(text_x, banner_rect.position.y + 57.0),
		String(instruction.get("subtitle", "")),
		HORIZONTAL_ALIGNMENT_LEFT,
		banner_rect.end.x - text_x - 12.0,
		14,
		BANNER_SUBTEXT_COLOR
	)


func _make_banner_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BANNER_COLOR
	style.corner_radius_top_left = int(BANNER_RADIUS)
	style.corner_radius_top_right = int(BANNER_RADIUS)
	style.corner_radius_bottom_left = int(BANNER_RADIUS)
	style.corner_radius_bottom_right = int(BANNER_RADIUS)
	return style


func _draw_turn_icon(rect: Rect2, turn: String) -> void:
	var center := rect.get_center()
	var color := BANNER_TEXT_COLOR
	var width := 5.0

	match turn:
		"left":
			var points := PackedVector2Array([
				Vector2(rect.end.x - 8.0, rect.end.y - 8.0),
				Vector2(rect.end.x - 8.0, center.y),
				Vector2(rect.position.x + 12.0, center.y),
			])
			draw_polyline(points, color, width, true)
			draw_line(
				Vector2(rect.position.x + 12.0, center.y),
				Vector2(rect.position.x + 24.0, center.y - 12.0),
				color, width, true
			)
			draw_line(
				Vector2(rect.position.x + 12.0, center.y),
				Vector2(rect.position.x + 24.0, center.y + 12.0),
				color, width, true
			)
		"right":
			var points := PackedVector2Array([
				Vector2(rect.position.x + 8.0, rect.end.y - 8.0),
				Vector2(rect.position.x + 8.0, center.y),
				Vector2(rect.end.x - 12.0, center.y),
			])
			draw_polyline(points, color, width, true)
			draw_line(
				Vector2(rect.end.x - 12.0, center.y),
				Vector2(rect.end.x - 24.0, center.y - 12.0),
				color, width, true
			)
			draw_line(
				Vector2(rect.end.x - 12.0, center.y),
				Vector2(rect.end.x - 24.0, center.y + 12.0),
				color, width, true
			)
		_:
			draw_line(
				Vector2(center.x, rect.end.y - 8.0),
				Vector2(center.x, rect.position.y + 10.0),
				color, width, true
			)
			draw_line(
				Vector2(center.x, rect.position.y + 10.0),
				Vector2(center.x - 11.0, rect.position.y + 21.0),
				color, width, true
			)
			draw_line(
				Vector2(center.x, rect.position.y + 10.0),
				Vector2(center.x + 11.0, rect.position.y + 21.0),
				color, width, true
			)
