extends Label

const BANNER_COLOR := Color(0.10, 0.14, 0.19, 0.96)
const BANNER_TEXT_COLOR := Color.WHITE
const BANNER_SUBTEXT_COLOR := Color(0.88, 0.92, 0.92, 0.94)
const BANNER_VISIBLE_SECONDS := 2.5
const BANNER_MARGIN := 16.0
const BANNER_HEIGHT := 82.0
const BANNER_RADIUS := 12.0

@onready var drive = $"../RoadWorld"
@onready var status_label: Label = $"../StatusLabel"

var last_key := ""
var visible_remaining := 0.0


func _ready() -> void:
	text = ""
	z_index = 4
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0


func _process(delta: float) -> void:
	if drive == null:
		return

	status_label.visible = not drive.started or drive.drive_complete

	if not drive.started or drive.drive_complete:
		last_key = ""
		visible_remaining = 0.0
		queue_redraw()
		return

	var instruction: Dictionary = drive.next_route_instruction()
	var key := String(instruction.get("key", ""))

	if key != last_key:
		last_key = key
		visible_remaining = BANNER_VISIBLE_SECONDS
	elif _at_relevant_junction():
		visible_remaining = BANNER_VISIBLE_SECONDS
	else:
		visible_remaining = maxf(0.0, visible_remaining - delta)

	queue_redraw()


func _at_relevant_junction() -> bool:
	if drive.next_node < 0:
		return false
	return (
		drive.visual_world_position.distance_to(
			drive.network.nodes[drive.next_node]
		) <= 38.0
	)


func _draw() -> void:
	if drive == null or not drive.started or drive.drive_complete:
		return
	if visible_remaining <= 0.0:
		return

	var instruction: Dictionary = drive.next_route_instruction()
	if instruction.is_empty():
		return

	var banner_width := minf(size.x - BANNER_MARGIN * 2.0, 420.0)
	var banner_rect := Rect2(
		Vector2((size.x - banner_width) * 0.5, BANNER_MARGIN),
		Vector2(banner_width, BANNER_HEIGHT)
	)
	draw_style_box(_banner_style(), banner_rect)

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


func _banner_style() -> StyleBoxFlat:
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
