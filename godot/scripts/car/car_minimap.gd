class_name CarMinimap
extends Control

## Whole-trip map for DRIVE.
##
## This is intentionally closer to a tiny corn maze than a navigation app.
## The player sees the whole little street puzzle, the blue route, their car,
## and the destination. No text tells them which turn to make.

const ROUTE_POINTS := PackedVector2Array([
	Vector2(16, 128),
	Vector2(16, 106),
	Vector2(48, 106),
	Vector2(48, 82),
	Vector2(104, 82),
	Vector2(104, 58),
	Vector2(76, 58),
	Vector2(76, 34),
	Vector2(124, 34),
	Vector2(124, 14),
])

const MAZE_SEGMENTS := [
	[Vector2(16, 138), Vector2(16, 96)],
	[Vector2(6, 106), Vector2(62, 106)],
	[Vector2(48, 118), Vector2(48, 70)],
	[Vector2(26, 82), Vector2(132, 82)],
	[Vector2(104, 94), Vector2(104, 46)],
	[Vector2(58, 58), Vector2(132, 58)],
	[Vector2(76, 70), Vector2(76, 22)],
	[Vector2(42, 34), Vector2(136, 34)],
	[Vector2(124, 46), Vector2(124, 7)],

	# Little wrong-looking branches / dead ends.
	[Vector2(31, 106), Vector2(31, 126)],
	[Vector2(62, 82), Vector2(62, 94)],
	[Vector2(116, 82), Vector2(116, 96)],
	[Vector2(104, 48), Vector2(132, 48)],
	[Vector2(58, 58), Vector2(58, 44)],
	[Vector2(76, 22), Vector2(92, 22)],
]

var segment_index: int = 0
var segment_progress: float = 0.0
var detour_active: bool = false
var detour_direction: int = 1
var detour_progress: float = 0.0


func set_route_progress(new_segment_index: int, new_segment_progress: float) -> void:
	segment_index = clampi(new_segment_index, 0, ROUTE_POINTS.size() - 2)
	segment_progress = clampf(new_segment_progress, 0.0, 1.0)
	queue_redraw()


func set_detour(active: bool, direction: int = 1, progress: float = 0.0) -> void:
	detour_active = active
	detour_direction = -1 if direction < 0 else 1
	detour_progress = clampf(progress, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var paper_dark := Color(0.075, 0.082, 0.068, 1.0)
	var maze_wall := Color(0.12, 0.15, 0.105, 1.0)
	var street_shadow := Color(0.16, 0.15, 0.135, 1.0)
	var street := Color(0.34, 0.32, 0.275, 1.0)
	var route_blue := Color(0.18, 0.43, 0.82, 1.0)

	draw_rect(Rect2(Vector2.ZERO, size), paper_dark)

	# Loose block shapes make the map feel like a tiny place rather than a grid UI.
	for rect in [
		Rect2(24, 8, 28, 20),
		Rect2(93, 8, 20, 18),
		Rect2(7, 40, 39, 50),
		Rect2(84, 40, 14, 11),
		Rect2(112, 64, 24, 12),
		Rect2(58, 88, 35, 12),
		Rect2(67, 113, 48, 23),
		Rect2(25, 115, 18, 17),
	]:
		draw_rect(rect, maze_wall)

	# Road network.
	for segment in MAZE_SEGMENTS:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		draw_line(a, b, street_shadow, 8.0, true)
		draw_line(a, b, street, 5.0, true)

	# The only explicit navigation information.
	draw_polyline(ROUTE_POINTS, route_blue, 4.0, true)

	var destination := ROUTE_POINTS[ROUTE_POINTS.size() - 1]
	draw_circle(destination, 6.0, Color(0.72, 0.26, 0.22, 1.0))
	draw_circle(destination, 2.2, Color(0.88, 0.82, 0.70, 1.0))

	var car_position := _get_car_position()
	var next_index := mini(segment_index + 1, ROUTE_POINTS.size() - 1)
	var direction := (ROUTE_POINTS[next_index] - ROUTE_POINTS[segment_index]).normalized()
	if detour_active:
		direction = Vector2(float(detour_direction), 0.0)

	var side := Vector2(-direction.y, direction.x)
	var nose := car_position + direction * 4.5
	var rear := car_position - direction * 4.0
	var car_shape := PackedVector2Array([
		nose,
		rear + side * 3.0,
		rear - side * 3.0,
	])
	draw_colored_polygon(car_shape, Color(0.22, 0.44, 0.90, 1.0))


func _get_car_position() -> Vector2:
	var a := ROUTE_POINTS[segment_index]
	var b := ROUTE_POINTS[segment_index + 1]

	if not detour_active:
		return a.lerp(b, segment_progress)

	# Wrong turn: leave the blue path briefly and curl back to the same junction.
	var incoming := (b - a).normalized()
	var side := Vector2(-incoming.y, incoming.x) * float(detour_direction)
	var branch_end := b + side * 16.0

	if detour_progress < 0.5:
		return b.lerp(branch_end, detour_progress * 2.0)
	return branch_end.lerp(b, (detour_progress - 0.5) * 2.0)
