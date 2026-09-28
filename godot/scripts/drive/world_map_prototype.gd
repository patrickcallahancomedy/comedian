extends Control

const LAYOUT = preload("res://scripts/drive/world_map_layout.gd")

const PAGE_BG := Color(0.055, 0.06, 0.065)
const WORLD_GRASS := Color(0.29, 0.39, 0.22)
const TREE_COLOR := Color(0.16, 0.27, 0.14)

const LOCAL_SIDEWALK := Color(0.64, 0.61, 0.53)
const LOCAL_ASPHALT := Color(0.16, 0.17, 0.18)
const ARTERIAL_ASPHALT := Color(0.14, 0.15, 0.16)

const HIGHWAY_SHOULDER := Color(0.30, 0.30, 0.27)
const HIGHWAY_ASPHALT := Color(0.12, 0.13, 0.145)
const HIGHWAY_LINE := Color(0.94, 0.92, 0.84)

const RAMP_SHOULDER := Color(0.39, 0.38, 0.34)
const RAMP_ASPHALT := Color(0.145, 0.155, 0.165)
const BRIDGE_SHADOW := Color(0.02, 0.025, 0.03, 0.44)
const BRIDGE_EDGE := Color(0.79, 0.77, 0.70)

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
const INDUSTRIAL_COLORS := [
	Color(0.52, 0.43, 0.32),
	Color(0.42, 0.45, 0.43),
	Color(0.60, 0.48, 0.33),
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

	_draw_world_rect(Rect2(Vector2.ZERO, LAYOUT.WORLD_SIZE), WORLD_GRASS)
	_draw_landscape_texture()

	# Surface streets first.
	for road in LAYOUT.city_roads():
		_draw_surface_road(road, false)
	for road in LAYOUT.neighborhood_roads():
		_draw_surface_road(road, false)
	_draw_surface_road(LAYOUT.neighborhood_collector(), true)
	_draw_surface_road(LAYOUT.north_surface_road(), true)
	_draw_surface_road(LAYOUT.wrong_exit_road(), false)

	# Freeway is the permanent backbone.
	_draw_highway(LAYOUT.westbound_highway())
	_draw_highway(LAYOUT.eastbound_highway())

	# Exit ramps live at freeway grade.
	_draw_ramp(LAYOUT.city_exit())
	_draw_ramp(LAYOUT.wrong_exit())

	# Overpass and loop ramp are layered above the freeway.
	_draw_overpass(LAYOUT.overpass_arterial())
	_draw_ramp(LAYOUT.main_onramp())

	_draw_city_buildings()
	_draw_neighborhood_houses()
	_draw_industrial_cluster()
	_draw_landmarks()
	_draw_ui_labels()


func _update_map_transform() -> void:
	var available := Vector2(
		maxf(1.0, size.x - 18.0),
		maxf(1.0, size.y - 72.0)
	)
	map_scale = minf(
		available.x / LAYOUT.WORLD_SIZE.x,
		available.y / LAYOUT.WORLD_SIZE.y
	)
	var map_size := LAYOUT.WORLD_SIZE * map_scale
	map_origin = Vector2(
		(size.x - map_size.x) * 0.5,
		48.0 + maxf(0.0, (available.y - map_size.y) * 0.5)
	)


func _draw_landscape_texture() -> void:
	for x in range(35, 1170, 72):
		for y in range(70, 1460, 78):
			# Leave denser developed areas clearer.
			if x > 690 and y > 930:
				continue
			if x < 500 and y < 520:
				continue
			if y > 610 and y < 820:
				continue
			_draw_world_circle(
				Vector2(float(x), float(y)),
				3.6,
				TREE_COLOR
			)


func _draw_surface_road(points: PackedVector2Array, arterial: bool) -> void:
	var road_width := (
		LAYOUT.ARTERIAL_ROAD_WIDTH
		if arterial
		else LAYOUT.LOCAL_ROAD_WIDTH
	)
	_draw_world_polyline(
		points,
		LOCAL_SIDEWALK,
		road_width + 9.0
	)
	_draw_world_polyline(
		points,
		ARTERIAL_ASPHALT if arterial else LOCAL_ASPHALT,
		road_width
	)


func _draw_highway(centerline: PackedVector2Array) -> void:
	_draw_world_polyline(
		centerline,
		HIGHWAY_SHOULDER,
		LAYOUT.HIGHWAY_CARRIAGEWAY_WIDTH + 10.0
	)
	_draw_world_polyline(
		centerline,
		HIGHWAY_ASPHALT,
		LAYOUT.HIGHWAY_CARRIAGEWAY_WIDTH
	)

	for lane in range(1, LAYOUT.HIGHWAY_LANES):
		var offset := (
			-LAYOUT.HIGHWAY_CARRIAGEWAY_WIDTH * 0.5
			+ float(lane) * LAYOUT.HIGHWAY_LANE_WIDTH
		)
		_draw_dashed_polyline(
			_offset_polyline(centerline, offset),
			HIGHWAY_LINE,
			1.0
		)

	_draw_world_polyline(
		_offset_polyline(
			centerline,
			-LAYOUT.HIGHWAY_CARRIAGEWAY_WIDTH * 0.5
		),
		HIGHWAY_LINE,
		1.2
	)
	_draw_world_polyline(
		_offset_polyline(
			centerline,
			LAYOUT.HIGHWAY_CARRIAGEWAY_WIDTH * 0.5
		),
		HIGHWAY_LINE,
		1.2
	)


func _draw_ramp(points: PackedVector2Array) -> void:
	_draw_world_polyline(
		points,
		RAMP_SHOULDER,
		LAYOUT.RAMP_ROAD_WIDTH + 8.0
	)
	_draw_world_polyline(
		points,
		RAMP_ASPHALT,
		LAYOUT.RAMP_ROAD_WIDTH
	)


func _draw_overpass(points: PackedVector2Array) -> void:
	var shadow := PackedVector2Array()
	for point in points:
		shadow.append(point + Vector2(6.0, 8.0))

	_draw_world_polyline(
		shadow,
		BRIDGE_SHADOW,
		LAYOUT.ARTERIAL_ROAD_WIDTH + 14.0
	)
	_draw_world_polyline(
		points,
		LOCAL_SIDEWALK,
		LAYOUT.ARTERIAL_ROAD_WIDTH + 9.0
	)
	_draw_world_polyline(
		points,
		ARTERIAL_ASPHALT,
		LAYOUT.ARTERIAL_ROAD_WIDTH
	)
	_draw_world_polyline(
		_offset_polyline(
			points,
			-LAYOUT.ARTERIAL_ROAD_WIDTH * 0.5
		),
		BRIDGE_EDGE,
		1.2
	)
	_draw_world_polyline(
		_offset_polyline(
			points,
			LAYOUT.ARTERIAL_ROAD_WIDTH * 0.5
		),
		BRIDGE_EDGE,
		1.2
	)


func _draw_city_buildings() -> void:
	var positions := [
		Vector2(70, 120), Vector2(165, 115), Vector2(270, 125),
		Vector2(380, 160), Vector2(55, 245), Vector2(265, 245),
		Vector2(385, 285), Vector2(55, 370), Vector2(275, 365),
		Vector2(400, 410),
	]
	for index in range(positions.size()):
		var size_variant := Vector2(
			58.0 + float(index % 3) * 10.0,
			52.0 + float(index % 2) * 14.0
		)
		_draw_world_rect(
			Rect2(positions[index], size_variant),
			BUILDING_COLORS[index % BUILDING_COLORS.size()]
		)


func _draw_neighborhood_houses() -> void:
	var positions := [
		Vector2(785, 1030), Vector2(885, 995), Vector2(1010, 1025),
		Vector2(745, 1125), Vector2(890, 1120), Vector2(1025, 1120),
		Vector2(760, 1260), Vector2(885, 1275), Vector2(1030, 1255),
		Vector2(825, 1350), Vector2(980, 1340),
	]
	for index in range(positions.size()):
		_draw_world_rect(
			Rect2(positions[index], Vector2(48, 34)),
			HOUSE_COLORS[index % HOUSE_COLORS.size()]
		)


func _draw_industrial_cluster() -> void:
	var positions := [
		Vector2(930, 400),
		Vector2(1000, 405),
		Vector2(1065, 425),
		Vector2(980, 475),
	]
	for index in range(positions.size()):
		_draw_world_rect(
			Rect2(positions[index], Vector2(52, 30)),
			INDUSTRIAL_COLORS[index % INDUSTRIAL_COLORS.size()]
		)


func _draw_landmarks() -> void:
	_draw_world_rect(LAYOUT.VENUE_PARKING_RECT, Color(0.13, 0.14, 0.15))
	_draw_world_rect(LAYOUT.VENUE_RECT, Color(0.17, 0.14, 0.13))
	_draw_world_rect(
		Rect2(
			LAYOUT.VENUE_RECT.position + Vector2(9, 12),
			Vector2(LAYOUT.VENUE_RECT.size.x - 18, 14)
		),
		Color(0.77, 0.45, 0.21)
	)
	_draw_world_rect(LAYOUT.HOME_RECT, Color(0.76, 0.55, 0.38))

	_draw_pin(LAYOUT.VENUE_RECT.get_center(), Color(0.92, 0.32, 0.24))
	_draw_pin(LAYOUT.HOME_RECT.get_center(), Color(0.15, 0.43, 0.96))


func _draw_ui_labels() -> void:
	var font := get_theme_default_font()
	draw_string(
		font,
		Vector2(16, 26),
		"COMEDIAN — MAP STUDY 02",
		HORIZONTAL_ALIGNMENT_LEFT,
		size.x - 32.0,
		15,
		Color(0.93, 0.93, 0.91)
	)
	draw_string(
		font,
		Vector2(16, size.y - 13),
		"fixed scale • roads first • no gameplay",
		HORIZONTAL_ALIGNMENT_LEFT,
		size.x - 32.0,
		10,
		Color(0.68, 0.70, 0.68)
	)

	_draw_world_label("HOME", LAYOUT.HOME_RECT.position + Vector2(-8, -12), 9)
	_draw_world_label("VENUE", LAYOUT.VENUE_RECT.position + Vector2(-4, -10), 9)


func _draw_world_label(label: String, world_point: Vector2, font_size: int) -> void:
	var font := get_theme_default_font()
	draw_string(
		font,
		_to_screen(world_point),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		120.0 * map_scale,
		font_size,
		Color(0.96, 0.96, 0.92, 0.92)
	)


func _draw_pin(world_point: Vector2, color: Color) -> void:
	var screen := _to_screen(world_point)
	draw_circle(screen, maxf(3.2, 7.0 * map_scale), color)
	draw_circle(screen, maxf(1.6, 3.2 * map_scale), Color.WHITE)


func _draw_dashed_polyline(
	points: PackedVector2Array,
	color: Color,
	world_width: float
) -> void:
	if points.size() < 2:
		return
	for index in range(points.size() - 1):
		if index % 3 == 2:
			continue
		_draw_world_line(
			points[index],
			points[index + 1],
			color,
			world_width
		)


func _offset_polyline(
	points: PackedVector2Array,
	offset: float
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(points.size()):
		var previous := points[maxi(0, index - 1)]
		var next := points[mini(points.size() - 1, index + 1)]
		var tangent := (next - previous).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		result.append(points[index] + normal * offset)
	return result


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
