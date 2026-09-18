class_name CarMinimap
extends Control

## Tiny fixed town map for the Car microgame.
##
## The route is deliberately authored and small. The player should be able to
## glance at the whole trip, see their little car moving on the blue line, and
## work out the next turn without a giant LEFT/RIGHT instruction.

const ROUTE_POINTS := PackedVector2Array([
	Vector2(18, 136),
	Vector2(18, 112),
	Vector2(52, 112),
	Vector2(52, 88),
	Vector2(112, 88),
	Vector2(112, 61),
	Vector2(78, 61),
	Vector2(78, 35),
	Vector2(125, 35),
	Vector2(125, 13),
])

var segment_index: int = 0
var segment_progress: float = 0.0


func set_route_progress(new_segment_index: int, new_segment_progress: float) -> void:
	segment_index = clampi(new_segment_index, 0, ROUTE_POINTS.size() - 2)
	segment_progress = clampf(new_segment_progress, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	# Map background.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.10, 0.98))

	# A tiny town: a few blocks and streets. These are intentionally simple
	# shapes so Patrick can replace the whole visual later without touching logic.
	var road_color := Color(0.27, 0.29, 0.31, 1.0)
	var block_color := Color(0.14, 0.15, 0.17, 1.0)

	for block in [
		Rect2(27, 43, 18, 11),
		Rect2(86, 43, 19, 11),
		Rect2(27, 68, 18, 13),
		Rect2(86, 68, 19, 13),
		Rect2(27, 95, 18, 10),
		Rect2(86, 95, 19, 10),
		Rect2(59, 119, 13, 11),
	]:
		draw_rect(block, block_color)

	for x in [18.0, 52.0, 78.0, 112.0, 125.0]:
		draw_line(Vector2(x, 4), Vector2(x, 142), road_color, 4.0)

	for y in [13.0, 35.0, 61.0, 88.0, 112.0, 136.0]:
		draw_line(Vector2(5, y), Vector2(140, y), road_color, 4.0)

	# GPS route.
	draw_polyline(ROUTE_POINTS, Color(0.12, 0.48, 1.0, 1.0), 4.0, true)

	# Destination.
	var destination := ROUTE_POINTS[ROUTE_POINTS.size() - 1]
	draw_circle(destination, 6.5, Color(0.95, 0.32, 0.28, 1.0))
	draw_circle(destination, 2.5, Color(1.0, 0.95, 0.90, 1.0))

	# Player car.
	var a := ROUTE_POINTS[segment_index]
	var b := ROUTE_POINTS[segment_index + 1]
	var car_position := a.lerp(b, segment_progress)
	var direction := (b - a).normalized()
	var side := Vector2(-direction.y, direction.x)
	var forward := direction * 5.0
	var half_width := side * 3.0
	var car_shape := PackedVector2Array([
		car_position + forward + half_width,
		car_position + forward - half_width,
		car_position - forward - half_width,
		car_position - forward + half_width,
	])
	draw_colored_polygon(car_shape, Color(0.18, 0.58, 1.0, 1.0))
	draw_circle(car_position, 1.5, Color(0.85, 0.95, 1.0, 1.0))
