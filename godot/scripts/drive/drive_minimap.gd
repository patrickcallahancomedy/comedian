class_name DriveMinimap
extends Control

## Complete route for DRIVE.
##
## This is intentionally simple and fully visible from the start. The player
## glances here to remember the next turn while the local road view stays close.

const ROUTE := PackedVector2Array([
	Vector2(18, 132),
	Vector2(18, 98),
	Vector2(72, 98),
	Vector2(72, 62),
	Vector2(124, 62),
	Vector2(124, 18),
])

const EXTRA_ROADS := [
	PackedVector2Array([Vector2(18, 116), Vector2(52, 116)]),
	PackedVector2Array([Vector2(45, 98), Vector2(45, 78)]),
	PackedVector2Array([Vector2(72, 80), Vector2(108, 80)]),
	PackedVector2Array([Vector2(100, 62), Vector2(100, 42)]),
	PackedVector2Array([Vector2(92, 40), Vector2(124, 40)]),
]

var segment_index: int = 0
var segment_progress: float = 0.0


func set_route_progress(new_segment: int, new_progress: float) -> void:
	segment_index = clampi(new_segment, 0, ROUTE.size() - 2)
	segment_progress = clampf(new_progress, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.11, 0.19, 0.10, 1.0))

	for street in EXTRA_ROADS:
		draw_polyline(street, Color(0.31, 0.30, 0.27, 1.0), 7.0, true)

	draw_polyline(ROUTE, Color(0.31, 0.30, 0.27, 1.0), 8.0, true)
	draw_polyline(ROUTE, Color(0.18, 0.45, 0.92, 1.0), 3.5, true)

	# Destination.
	var destination := ROUTE[ROUTE.size() - 1]
	draw_circle(destination, 5.0, Color(0.78, 0.25, 0.20, 1.0))

	# Tiny car position.
	var a := ROUTE[segment_index]
	var b := ROUTE[segment_index + 1]
	var car := a.lerp(b, segment_progress)
	draw_circle(car, 4.0, Color(0.20, 0.48, 0.98, 1.0))
