class_name CarMinimap
extends Control

## Whole tiny town for DRIVE.
##
## The player can see the entire maze, the blue route, Darren, and the mic.
## There are no written turn instructions.

var car_world_position := CarRouteData.ROUTE[0]
var car_world_direction := Vector2.UP


func set_car_world_state(world_position: Vector2, world_direction: Vector2) -> void:
	car_world_position = world_position
	if world_direction.length_squared() > 0.001:
		car_world_direction = world_direction.normalized()
	queue_redraw()


func _map_point(world: Vector2) -> Vector2:
	var margin := 8.0
	var usable := size - Vector2(margin * 2.0, margin * 2.0)
	var bounds := CarRouteData.MAP_MAX - CarRouteData.MAP_MIN
	var normalized := (world - CarRouteData.MAP_MIN) / bounds
	# World Y increases downward already, so no flip is needed.
	return Vector2(
		margin + normalized.x * usable.x,
		margin + normalized.y * usable.y
	)


func _draw_street(polyline: PackedVector2Array, width: float) -> void:
	if polyline.size() < 2:
		return
	var mapped := PackedVector2Array()
	for point in polyline:
		mapped.append(_map_point(point))
	draw_polyline(mapped, Color(0.33, 0.31, 0.27, 1.0), width, true)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.075, 0.062, 0.98))

	for detour in CarRouteData.DETOURS:
		_draw_street(detour, 2.2)
	for street in CarRouteData.EXTRA_STREETS:
		_draw_street(street, 2.2)
	_draw_street(CarRouteData.ROUTE, 2.8)

	var route := PackedVector2Array()
	for point in CarRouteData.ROUTE:
		route.append(_map_point(point))
	draw_polyline(route, Color(0.18, 0.43, 0.82, 1.0), 3.0, true)

	var destination := _map_point(CarRouteData.ROUTE[CarRouteData.ROUTE.size() - 1])
	draw_circle(destination, 5.2, Color(0.72, 0.26, 0.22, 1.0))
	draw_circle(destination, 1.8, Color(0.88, 0.82, 0.70, 1.0))

	var car := _map_point(car_world_position)
	var dir := car_world_direction.normalized()
	var side := Vector2(-dir.y, dir.x)
	var shape := PackedVector2Array([
		car + dir * 4.5,
		car - dir * 3.5 + side * 2.6,
		car - dir * 3.5 - side * 2.6,
	])
	draw_colored_polygon(shape, Color(0.22, 0.44, 0.90, 1.0))
