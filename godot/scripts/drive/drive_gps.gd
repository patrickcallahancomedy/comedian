extends Control

## Small GPS overview for the driving microgame.
## It does not affect driving. It only mirrors the current fixed map and route.

const MAP = preload("res://scripts/drive/drive_grid_map.gd")

const PADDING := 8.0
const PANEL_COLOR := Color(0.03, 0.035, 0.04, 0.88)
const PANEL_BORDER := Color(0.85, 0.85, 0.80, 0.65)
const NEIGHBORHOOD_COLOR := Color(0.22, 0.38, 0.20)
const CONNECTOR_COLOR := Color(0.58, 0.34, 0.12)
const HIGHWAY_COLOR := Color(0.42, 0.24, 0.34)
const CITY_COLOR := Color(0.27, 0.28, 0.31)
const ROUTE_COLOR := Color(1.0, 0.90, 0.28)
const PLAYER_COLOR := Color(1.0, 1.0, 1.0)
const DESTINATION_COLOR := Color(1.0, 0.42, 0.22)

@onready var drive = $"../CityMap"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	draw_rect(Rect2(Vector2.ZERO, size), PANEL_COLOR, true)
	draw_rect(Rect2(Vector2.ZERO, size), PANEL_BORDER, false, 1.5)

	_draw_map_rect(MAP.NEIGHBORHOOD_RECT, NEIGHBORHOOD_COLOR)
	_draw_map_rect(MAP.CONNECTOR_ONE_RECT, CONNECTOR_COLOR)
	_draw_map_rect(MAP.HIGHWAY_RECT, HIGHWAY_COLOR)
	_draw_city_connector()
	_draw_map_rect(MAP.CITY_RECT, CITY_COLOR)

	var route := _route_points()
	var route_screen := PackedVector2Array()
	for point in route:
		route_screen.append(_map_to_gps(point))
	draw_polyline(route_screen, ROUTE_COLOR, 3.0, true)

	var destination := _map_to_gps(MAP.city_cell_center(MAP.CITY_DESTINATION))
	draw_circle(destination, 4.5, DESTINATION_COLOR)
	draw_circle(destination, 4.5, PANEL_BORDER, false, 1.5)

	if drive != null:
		var player := _map_to_gps(drive.visual_world_position)
		draw_circle(player, 4.0, PLAYER_COLOR)
		draw_circle(player, 4.0, Color(0.05, 0.05, 0.05), false, 1.0)


func _route_points() -> PackedVector2Array:
	# Fixed route for the current proof map.
	# Later the procedural generator can hand the GPS a generated route instead.
	return PackedVector2Array([
		MAP.neighborhood_cell_center(MAP.NEIGHBORHOOD_START),
		MAP.neighborhood_cell_center(Vector2i(1, 2)),
		MAP.neighborhood_cell_center(Vector2i(1, 1)),
		MAP.neighborhood_cell_center(Vector2i(2, 1)),
		MAP.neighborhood_cell_center(MAP.NEIGHBORHOOD_GATE),
		MAP.neighborhood_gate_outside_point(),
		MAP.highway_entry_point(),
		MAP.highway_exit_point(),
		MAP.city_entry_point(),
		MAP.city_cell_center(Vector2i(1, 2)),
		MAP.city_cell_center(Vector2i(2, 2)),
		MAP.city_cell_center(Vector2i(3, 2)),
		MAP.city_cell_center(MAP.CITY_DESTINATION),
	])


func _draw_map_rect(rect: Rect2, color: Color) -> void:
	var top_left := _map_to_gps(rect.position)
	var bottom_right := _map_to_gps(rect.end)
	draw_rect(Rect2(top_left, bottom_right - top_left), color, true)


func _draw_city_connector() -> void:
	var rect := MAP.CONNECTOR_TWO_RECT
	var center_y := rect.get_center().y
	var start_half_width := rect.size.y * 0.5
	var end_half_width := float(MAP.CITY_CELL) * 0.5
	var points := PackedVector2Array([
		_map_to_gps(Vector2(rect.position.x, center_y - start_half_width)),
		_map_to_gps(Vector2(rect.end.x, center_y - end_half_width)),
		_map_to_gps(Vector2(rect.end.x, center_y + end_half_width)),
		_map_to_gps(Vector2(rect.position.x, center_y + start_half_width)),
	])
	draw_colored_polygon(points, CONNECTOR_COLOR)


func _map_to_gps(world_point: Vector2) -> Vector2:
	var available := size - Vector2.ONE * PADDING * 2.0
	var map_size := Vector2(MAP.MAP_SIZE)
	var scale_factor := minf(available.x / map_size.x, available.y / map_size.y)
	var drawn_size := map_size * scale_factor
	var origin := (size - drawn_size) * 0.5
	return origin + world_point * scale_factor
