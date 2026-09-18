class_name CarMinimap
extends Control

## Tiny-town-rug minimap for DRIVE.
##
## This is intentionally more toy-like than the main view: tiny colored houses,
## trees, ponds, roads, Darren, destination, and the blue route.

var car_world_position := CarRouteData.ROUTE[0]
var car_world_direction := Vector2.UP


func set_car_world_state(world_position: Vector2, world_direction: Vector2) -> void:
	car_world_position = world_position
	if world_direction.length_squared() > 0.001:
		car_world_direction = world_direction.normalized()
	queue_redraw()


func _map_point(world: Vector2) -> Vector2:
	var margin := 6.0
	var usable := size - Vector2(margin * 2.0, margin * 2.0)
	var bounds := CarRouteData.MAP_MAX - CarRouteData.MAP_MIN
	var normalized := (world - CarRouteData.MAP_MIN) / bounds
	return Vector2(
		margin + normalized.x * usable.x,
		margin + normalized.y * usable.y
	)


func _map_scale() -> float:
	return minf(size.x / 775.0, size.y / 900.0)


func _draw_street(a_world: Vector2, b_world: Vector2) -> void:
	var a := _map_point(a_world)
	var b := _map_point(b_world)
	draw_line(a, b, Color(0.10, 0.10, 0.095, 1.0), 8.0, true)
	draw_line(a, b, Color(0.31, 0.30, 0.27, 1.0), 5.0, true)


func _draw_tiny_house(world: Vector2, index: int) -> void:
	var p := _map_point(world)
	var colors := [
		Color(0.70, 0.30, 0.23, 1.0),
		Color(0.28, 0.49, 0.66, 1.0),
		Color(0.78, 0.63, 0.25, 1.0),
	]
	var c: Color = colors[clampi(index, 0, colors.size() - 1)]
	draw_rect(Rect2(p - Vector2(5, 3), Vector2(10, 7)), c)
	var roof := PackedVector2Array([
		p + Vector2(-6, -3),
		p + Vector2(0, -8),
		p + Vector2(6, -3),
	])
	draw_colored_polygon(roof, Color(0.35, 0.20, 0.16, 1.0))


func _draw_tiny_tree(world: Vector2) -> void:
	var p := _map_point(world)
	draw_circle(p, 4.0, Color(0.14, 0.31, 0.13, 1.0))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.24, 0.11, 1.0))

	for i in range(CarRouteData.ROUTE.size() - 1):
		_draw_street(CarRouteData.ROUTE[i], CarRouteData.ROUTE[i + 1])
	for street in CarRouteData.EXTRA_STREETS:
		_draw_street(street[0], street[1])

	for item in CarRouteData.DECOR:
		var kind := str(item.get("type", ""))
		var pos: Vector2 = item.get("pos", Vector2.ZERO)
		match kind:
			"house", "shop":
				_draw_tiny_house(pos, int(item.get("color", 0)))
			"tree":
				_draw_tiny_tree(pos)
			"pond":
				draw_circle(_map_point(pos), 7.0, Color(0.18, 0.42, 0.62, 1.0))
			"club":
				var club := _map_point(pos)
				draw_rect(Rect2(club - Vector2(6, 5), Vector2(12, 10)), Color(0.66, 0.22, 0.20, 1.0))
				draw_circle(club + Vector2(0, -7), 3.0, Color(0.84, 0.68, 0.28, 1.0))

	# Blue GPS route sits on top of the rug.
	var route := PackedVector2Array()
	for point in CarRouteData.ROUTE:
		route.append(_map_point(point))
	draw_polyline(route, Color(0.16, 0.46, 0.95, 1.0), 3.5, true)

	var destination := _map_point(CarRouteData.ROUTE[CarRouteData.ROUTE.size() - 1])
	draw_circle(destination, 4.0, Color(0.84, 0.23, 0.20, 1.0))

	# Tiny car.
	var car := _map_point(car_world_position)
	var direction := car_world_direction.normalized()
	var side := Vector2(-direction.y, direction.x)
	var car_shape := PackedVector2Array([
		car + direction * 4.5,
		car - direction * 3.5 + side * 2.6,
		car - direction * 3.5 - side * 2.6,
	])
	draw_colored_polygon(car_shape, Color(0.18, 0.42, 0.88, 1.0))
