class_name CarRoad
extends Control

## Actual moving town view for DRIVE.
##
## The car's world position is supplied by car_module.gd. This renderer scrolls
## the little authored town underneath a mostly fixed car, so intersections
## physically approach and pass instead of appearing as a timer graphic.

var car_world_position := Vector2.ZERO
var car_world_direction := Vector2.UP


func set_car_world_state(world_position: Vector2, world_direction: Vector2) -> void:
	car_world_position = world_position
	if world_direction.length_squared() > 0.001:
		car_world_direction = world_direction.normalized()
	queue_redraw()


func _world_to_screen(world: Vector2) -> Vector2:
	var anchor := Vector2(size.x * 0.5, size.y * 0.72)
	return world - car_world_position + anchor


func _draw_road_segment(a_world: Vector2, b_world: Vector2) -> void:
	var a := _world_to_screen(a_world)
	var b := _world_to_screen(b_world)
	var edge := Color(0.47, 0.43, 0.34, 1.0)
	var asphalt := Color(0.22, 0.215, 0.195, 1.0)
	var line := Color(0.68, 0.58, 0.31, 0.42)

	draw_line(a, b, edge, 92.0, true)
	draw_line(a, b, asphalt, 82.0, true)

	# Cheap dashed center line.
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var direction := (b - a).normalized()
	var dash := 18.0
	var gap := 34.0
	var cursor := 8.0
	while cursor < length:
		var start := a + direction * cursor
		var finish := a + direction * minf(cursor + dash, length)
		draw_line(start, finish, line, 3.0, true)
		cursor += dash + gap


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.105, 0.075, 1.0))

	# Muted block masses around the road. These are placeholders for Patrick's
	# final illustrated environment assets, not a new art direction.
	var block_color := Color(0.12, 0.135, 0.09, 1.0)
	for world_rect in [
		Rect2(-110, 705, 90, 72),
		Rect2(42, 680, 78, 82),
		Rect2(215, 665, 90, 78),
		Rect2(365, 650, 95, 82),
		Rect2(-100, 500, 105, 82),
		Rect2(215, 530, 82, 72),
		Rect2(390, 520, 95, 72),
		Rect2(-85, 320, 95, 78),
		Rect2(210, 380, 85, 68),
		Rect2(390, 350, 88, 72),
		Rect2(-80, 140, 88, 72),
		Rect2(210, 220, 82, 66),
		Rect2(390, 175, 92, 68),
	]:
		var top_left := _world_to_screen(world_rect.position)
		draw_rect(Rect2(top_left, world_rect.size), block_color)

	# Route streets.
	for i in range(CarRouteData.ROUTE.size() - 1):
		_draw_road_segment(CarRouteData.ROUTE[i], CarRouteData.ROUTE[i + 1])

	# Wrong-turn loops.
	for detour in CarRouteData.DETOURS:
		for i in range(detour.size() - 1):
			_draw_road_segment(detour[i], detour[i + 1])

	# A few extra streets make the world read like a tiny maze.
	for street in CarRouteData.EXTRA_STREETS:
		_draw_road_segment(street[0], street[1])
