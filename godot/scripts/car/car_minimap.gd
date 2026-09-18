class_name CarMinimap
extends Control

## Whole-trip map for the Car microgame.
##
## The map does the navigation work. The close-up road deliberately does not
## tell the player which direction is correct.

const ROUTE_POINTS := PackedVector2Array([
	Vector2(18, 132),
	Vector2(18, 108),
	Vector2(49, 108),
	Vector2(49, 83),
	Vector2(104, 83),
	Vector2(104, 57),
	Vector2(75, 57),
	Vector2(75, 33),
	Vector2(123, 33),
	Vector2(123, 12),
])

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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.045, 0.055, 0.05, 0.97))

	var street := Color(0.26, 0.28, 0.27, 1.0)
	var block := Color(0.08, 0.11, 0.085, 1.0)

	for rect in [
		Rect2(26, 40, 15, 12),
		Rect2(84, 40, 16, 12),
		Rect2(26, 65, 15, 11),
		Rect2(84, 65, 16, 11),
		Rect2(26, 90, 15, 10),
		Rect2(84, 90, 16, 10),
		Rect2(57, 116, 11, 9),
	]:
		draw_rect(rect, block)

	for x in [18.0, 49.0, 75.0, 104.0, 123.0]:
		draw_line(Vector2(x, 4), Vector2(x, 138), street, 4.0)

	for y in [12.0, 33.0, 57.0, 83.0, 108.0, 132.0]:
		draw_line(Vector2(5, y), Vector2(138, y), street, 4.0)

	draw_polyline(ROUTE_POINTS, Color(0.12, 0.48, 1.0, 1.0), 4.0, true)

	var destination := ROUTE_POINTS[ROUTE_POINTS.size() - 1]
	draw_circle(destination, 5.5, Color(0.95, 0.30, 0.24, 1.0))
	draw_circle(destination, 2.0, Color(1.0, 0.92, 0.88, 1.0))

	var car_position := _get_car_position()
	draw_circle(car_position, 4.4, Color(0.18, 0.58, 1.0, 1.0))
	draw_circle(car_position, 1.4, Color(0.84, 0.94, 1.0, 1.0))


func _get_car_position() -> Vector2:
	var a := ROUTE_POINTS[segment_index]
	var b := ROUTE_POINTS[segment_index + 1]

	if not detour_active:
		return a.lerp(b, segment_progress)

	# Wrong turn: visibly leave the blue route and curl back toward the same
	# intersection before navigation resumes on the next route segment.
	var incoming := (b - a).normalized()
	var side := Vector2(-incoming.y, incoming.x) * float(detour_direction)
	var branch_end := b + side * 17.0

	if detour_progress < 0.5:
		return b.lerp(branch_end, detour_progress * 2.0)
	return branch_end.lerp(b, (detour_progress - 0.5) * 2.0)
