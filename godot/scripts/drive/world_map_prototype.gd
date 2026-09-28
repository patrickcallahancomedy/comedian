extends Control

const LAYOUT = preload("res://scripts/drive/world_map_layout.gd")

const PAGE_BG := Color(0.055, 0.06, 0.065)
const MAP_BG := Color(0.24, 0.34, 0.20)
const MAP_BORDER := Color(0.55, 0.57, 0.52, 0.40)

const NEIGHBORHOOD_GROUND := Color(0.30, 0.43, 0.24)
const CITY_GROUND := Color(0.29, 0.31, 0.28)
const INDUSTRIAL_GROUND := Color(0.36, 0.34, 0.27)

const LOCAL_SIDEWALK := Color(0.69, 0.66, 0.58)
const LOCAL_ASPHALT := Color(0.16, 0.18, 0.20)
const CITY_ASPHALT := Color(0.14, 0.15, 0.17)

const HIGHWAY_ASPHALT := Color(0.13, 0.14, 0.16)
const HIGHWAY_ASPHALT_ALT := Color(0.15, 0.16, 0.18)
const HIGHWAY_SHOULDER := Color(0.27, 0.27, 0.25)
const HIGHWAY_LINE := Color(0.93, 0.91, 0.82)
const HIGHWAY_MEDIAN := Color(0.27, 0.38, 0.23)

const RAMP_SHADOW := Color(0.03, 0.035, 0.04, 0.42)
const RAMP_SHOULDER := Color(0.44, 0.42, 0.36)
const RAMP_ASPHALT := Color(0.17, 0.18, 0.19)
const RAMP_EDGE := Color(0.94, 0.92, 0.84)

const HOUSE_COLORS := [
	Color(0.66, 0.46, 0.30),
	Color(0.48, 0.59, 0.65),
	Color(0.73, 0.60, 0.38),
	Color(0.58, 0.52, 0.43),
	Color(0.69, 0.40, 0.34),
]
const BUILDING_COLORS := [
	Color(0.25, 0.27, 0.28),
	Color(0.31, 0.30, 0.27),
	Color(0.35, 0.31, 0.26),
	Color(0.24, 0.29, 0.31),
]

var map_scale := 1.0
var map_origin := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAGE_BG, true)
	_update_map_transform()

	var world_screen_rect := Rect2(
		map_origin,
		LAYOUT.WORLD_SIZE * map_scale
	)
	draw_rect(world_screen_rect, MAP_BG, true)
	draw_rect(world_screen_rect, MAP_BORDER, false, 1.0)

	_draw_zone_blocks()
	_draw_local_districts()
	_draw_highways()
	_draw_exit_roads()
	_draw_main_overpass()
	_draw_buildings()
	_draw_landmarks()
	_draw_labels()


func _update_map_transform() -> void:
	var available := Vector2(
		maxf(1.0, size.x - 24.0),
		maxf(1.0, size.y - 112.0)
	)
	map_scale = minf(
		available.x / LAYOUT.WORLD_SIZE.x,
		available.y / LAYOUT.WORLD_SIZE.y
	)
	var map_size := LAYOUT.WORLD_SIZE * map_scale
	map_origin = Vector2(
		(size.x - map_size.x) * 0.5,
		68.0 + maxf(0.0, (available.y - map_size.y) * 0.5)
	)


func _draw_zone_blocks() -> void:
	_draw_world_rect(
		Rect2(55, 105, 390, 330),
		CITY_GROUND
	)
	_draw_world_rect(
		Rect2(615, 720, 350, 365),
		NEIGHBORHOOD_GROUND
	)
	_draw_world_rect(
		Rect2(815, 370, 170, 120),
		INDUSTRIAL_GROUND
	)

	# A little undeveloped buffer around the interchange helps the road
	# structure read clearly at the full-map scale.
	for x in range(455, 795, 68):
		for y in range(310, 470, 68):
			_draw_world_circle(
				Vector2(float(x), float(y)),
				5.0,
				Color(0.18, 0.29, 0.17)
			)


func _draw_local_districts() -> void:
	for road in LAYOUT.CITY_ROADS:
		_draw_road(road, true)

	for road in LAYOUT.NEIGHBORHOOD_ROADS:
		_draw_road(road, false)

	_draw_road(LAYOUT.NEIGHBORHOOD_FEEDER, false)
	_draw_road(LAYOUT.CITY_ENTRY_ROAD, true)
	_draw_road(LAYOUT.WRONG_EXIT_ROAD, false)


func _draw_road(points: PackedVector2Array, city: bool) -> void:
	var sidewalk_width := LAYOUT.LOCAL_SIDEWALK_WIDTH
	var asphalt_width := LAYOUT.LOCAL_ROAD_WIDTH
	_draw_world_polyline(points, LOCAL_SIDEWALK, sidewalk_width)
	_draw_world_polyline(
		points,
		CITY_ASPHALT if city else LOCAL_ASPHALT,
		asphalt_width
	)


func _draw_highways() -> void:
	_draw_highway_carriageway(LAYOUT.WESTBOUND_HIGHWAY)
	_draw_highway_carriageway(LAYOUT.EASTBOUND_HIGHWAY)

	var median := Rect2(
		Vector2(
			LAYOUT.WESTBOUND_HIGHWAY.position.x,
			LAYOUT.WESTBOUND_HIGHWAY.end.y
		),
		Vector2(
			LAYOUT.WESTBOUND_HIGHWAY.size.x,
			LAYOUT.EASTBOUND_HIGHWAY.position.y
				- LAYOUT.WESTBOUND_HIGHWAY.end.y
		)
	)
	_draw_world_rect(median, HIGHWAY_MEDIAN)


func _draw_highway_carriageway(rect: Rect2) -> void:
	var shoulder_rect := rect.grow(LAYOUT.HIGHWAY_SHOULDER)
	_draw_world_rect(shoulder_rect, HIGHWAY_SHOULDER)

	for lane in range(LAYOUT.HIGHWAY_LANES):
		var lane_rect := Rect2(
			Vector2(
				rect.position.x,
				rect.position.y + lane * LAYOUT.HIGHWAY_LANE_WIDTH
			),
			Vector2(rect.size.x, LAYOUT.HIGHWAY_LANE_WIDTH)
		)
		_draw_world_rect(
			lane_rect,
			HIGHWAY_ASPHALT_ALT if lane % 2 == 1 else HIGHWAY_ASPHALT
		)

	for lane in range(1, LAYOUT.HIGHWAY_LANES):
		var lane_y := rect.position.y + lane * LAYOUT.HIGHWAY_LANE_WIDTH
		var dash_x := rect.position.x + 12.0
		while dash_x < rect.end.x:
			_draw_world_line(
				Vector2(dash_x, lane_y),
				Vector2(minf(dash_x + 18.0, rect.end.x), lane_y),
				HIGHWAY_LINE,
				1.0
			)
			dash_x += 36.0

	_draw_world_line(
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		HIGHWAY_LINE,
		1.3
	)
	_draw_world_line(
		Vector2(rect.position.x, rect.end.y),
		rect.end,
		HIGHWAY_LINE,
		1.3
	)


func _draw_exit_roads() -> void:
	_draw_ramp(LAYOUT.city_exit(), false)
	_draw_ramp(LAYOUT.wrong_exit(), false)


func _draw_main_overpass() -> void:
	var ramp := LAYOUT.main_onramp()

	# Shadow makes only the crossing portion read as elevated while the same
	# physical road remains connected before and after the bridge.
	var shadow_points := PackedVector2Array()
	for point in ramp:
		shadow_points.append(point + Vector2(5.0, 6.0))
	_draw_world_polyline(
		shadow_points,
		RAMP_SHADOW,
		LAYOUT.LOCAL_ROAD_WIDTH + 13.0
	)

	_draw_ramp(ramp, true)


func _draw_ramp(points: PackedVector2Array, emphasize: bool) -> void:
	var shoulder_width := (
		LAYOUT.LOCAL_ROAD_WIDTH + 10.0
		if emphasize
		else LAYOUT.LOCAL_ROAD_WIDTH + 6.0
	)
	_draw_world_polyline(points, RAMP_SHOULDER, shoulder_width)
	_draw_world_polyline(points, RAMP_ASPHALT, LAYOUT.LOCAL_ROAD_WIDTH)

	# Thin edges keep ramps legible without turning this into finished art.
	if points.size() >= 2:
		_draw_world_circle(points[0], 2.6, RAMP_EDGE)
		_draw_world_circle(points[points.size() - 1], 2.6, RAMP_EDGE)


func _draw_buildings() -> void:
	# City blocks.
	for row in range(2):
		for column in range(3):
			var base := Vector2(
				110.0 + float(column) * 100.0,
				175.0 + float(row) * 125.0
			)
			_draw_world_rect(
				Rect2(base, Vector2(56, 58)),
				BUILDING_COLORS[(row * 3 + column) % BUILDING_COLORS.size()]
			)

	# Neighborhood houses sit inside the road blocks.
	for row in range(2):
		for column in range(2):
			var base := Vector2(
				680.0 + float(column) * 130.0,
				795.0 + float(row) * 140.0
			)
			for house_index in range(4):
				var offset := Vector2(
					float(house_index % 2) * 58.0,
					float(house_index / 2) * 52.0
				)
				_draw_world_rect(
					Rect2(base + offset, Vector2(38, 26)),
					HOUSE_COLORS[
						(row * 4 + column * 2 + house_index)
						% HOUSE_COLORS.size()
					]
				)

	# Wrong-exit roadside cluster.
	for index in range(3):
		_draw_world_rect(
			Rect2(
				Vector2(842.0 + float(index) * 43.0, 383.0),
				Vector2(30, 24)
			),
			Color(0.52, 0.43, 0.32)
		)


func _draw_landmarks() -> void:
	_draw_world_rect(LAYOUT.VENUE_PARKING_RECT, Color(0.15, 0.16, 0.17))
	_draw_world_rect(LAYOUT.VENUE_RECT, Color(0.18, 0.15, 0.14))
	_draw_world_rect(
		Rect2(
			LAYOUT.VENUE_RECT.position + Vector2(8, 10),
			Vector2(LAYOUT.VENUE_RECT.size.x - 16, 14)
		),
		Color(0.77, 0.45, 0.21)
	)

	_draw_world_rect(LAYOUT.HOME_RECT, Color(0.77, 0.56, 0.39))

	_draw_pin(
		LAYOUT.HOME_RECT.get_center(),
		Color(0.16, 0.46, 0.95)
	)
	_draw_pin(
		LAYOUT.VENUE_RECT.get_center(),
		Color(0.91, 0.35, 0.26)
	)


func _draw_labels() -> void:
	var font := get_theme_default_font()
	draw_string(
		font,
		Vector2(18, 32),
		"COMEDIAN — WORLD MAP PROTOTYPE",
		HORIZONTAL_ALIGNMENT_LEFT,
		size.x - 36.0,
		18,
		Color(0.94, 0.94, 0.92)
	)
	draw_string(
		font,
		Vector2(18, size.y - 22),
		"Fixed scale • geography only • no gameplay",
		HORIZONTAL_ALIGNMENT_LEFT,
		size.x - 36.0,
		12,
		Color(0.70, 0.72, 0.70)
	)

	_draw_world_label("CITY", Vector2(225, 118), 18)
	_draw_world_label("HIGHWAY", Vector2(480, 580), 15)
	_draw_world_label("NEIGHBORHOOD", Vector2(730, 1110), 16)
	_draw_world_label("WRONG EXIT", Vector2(835, 365), 10)
	_draw_world_label("HOME", Vector2(792, 995), 10)
	_draw_world_label("VENUE", Vector2(100, 165), 10)


func _draw_world_label(label: String, world_point: Vector2, font_size: int) -> void:
	var font := get_theme_default_font()
	var screen := _to_screen(world_point)
	draw_string(
		font,
		screen,
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		220.0 * map_scale,
		font_size,
		Color(0.96, 0.96, 0.91, 0.90)
	)


func _draw_pin(world_point: Vector2, color: Color) -> void:
	var screen := _to_screen(world_point)
	draw_circle(screen, maxf(3.5, 8.0 * map_scale), color)
	draw_circle(
		screen,
		maxf(2.0, 4.0 * map_scale),
		Color.WHITE
	)


func _draw_world_circle(
	world_point: Vector2,
	world_radius: float,
	color: Color
) -> void:
	draw_circle(_to_screen(world_point), world_radius * map_scale, color)


func _draw_world_rect(rect: Rect2, color: Color) -> void:
	draw_rect(
		Rect2(_to_screen(rect.position), rect.size * map_scale),
		color,
		true
	)


func _draw_world_line(
	a: Vector2,
	b: Vector2,
	color: Color,
	world_width: float
) -> void:
	draw_line(
		_to_screen(a),
		_to_screen(b),
		color,
		maxf(1.0, world_width * map_scale),
		true
	)


func _draw_world_polyline(
	points: PackedVector2Array,
	color: Color,
	world_width: float
) -> void:
	if points.size() < 2:
		return
	var screen_points := PackedVector2Array()
	for point in points:
		screen_points.append(_to_screen(point))
	draw_polyline(
		screen_points,
		color,
		maxf(1.0, world_width * map_scale),
		true
	)


func _to_screen(world_point: Vector2) -> Vector2:
	return map_origin + world_point * map_scale
