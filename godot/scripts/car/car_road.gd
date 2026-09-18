class_name CarRoad
extends Control

## Close-up top-down neighborhood for DRIVE.
##
## The world scrolls AND rotates around Darren so his car always points forward
## on screen. That makes LEFT and RIGHT literal, while the minimap remains
## north-up like a tiny-town rug.

var car_world_position := Vector2.ZERO
var car_world_direction := Vector2.UP

var _view_rotation: float = 0.0
var _target_view_rotation: float = 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_view_rotation = lerp_angle(_view_rotation, _target_view_rotation, minf(1.0, delta * 7.5))
	queue_redraw()


func set_car_world_state(world_position: Vector2, world_direction: Vector2) -> void:
	car_world_position = world_position
	if world_direction.length_squared() > 0.001:
		car_world_direction = world_direction.normalized()
		var heading := atan2(car_world_direction.y, car_world_direction.x)
		_target_view_rotation = -PI * 0.5 - heading
	queue_redraw()


func _world_to_screen(world: Vector2) -> Vector2:
	var anchor := Vector2(size.x * 0.5, size.y * 0.72)
	var local := world - car_world_position
	return local.rotated(_view_rotation) + anchor


func _draw_street(a_world: Vector2, b_world: Vector2) -> void:
	var a := _world_to_screen(a_world)
	var b := _world_to_screen(b_world)
	var curb := Color(0.55, 0.50, 0.39, 1.0)
	var road := Color(0.235, 0.225, 0.205, 1.0)
	var line := Color(0.69, 0.59, 0.32, 0.45)

	draw_line(a, b, curb, 70.0, true)
	draw_line(a, b, road, 60.0, true)

	var distance := a.distance_to(b)
	if distance < 1.0:
		return
	var direction := (b - a).normalized()
	var cursor := 10.0
	while cursor < distance:
		var start := a + direction * cursor
		var finish := a + direction * minf(cursor + 17.0, distance)
		draw_line(start, finish, line, 2.4, true)
		cursor += 48.0


func _draw_tree(world: Vector2) -> void:
	var p := _world_to_screen(world)
	draw_circle(p + Vector2(2, 4), 15.0, Color(0.08, 0.13, 0.075, 0.55))
	draw_rect(Rect2(p.x - 3, p.y + 6, 6, 13), Color(0.28, 0.20, 0.13, 1.0))
	draw_circle(p, 14.0, Color(0.16, 0.26, 0.13, 1.0))
	draw_circle(p + Vector2(-8, 3), 8.0, Color(0.19, 0.30, 0.15, 1.0))


func _house_color(index: int) -> Color:
	var colors := [
		Color(0.63, 0.31, 0.23, 1.0),
		Color(0.27, 0.43, 0.52, 1.0),
		Color(0.66, 0.54, 0.27, 1.0),
	]
	return colors[clampi(index, 0, colors.size() - 1)]


func _draw_house(world: Vector2, index: int) -> void:
	var p := _world_to_screen(world)
	var body := _house_color(index)
	draw_rect(Rect2(p - Vector2(22, 14), Vector2(44, 30)), body)
	var roof := PackedVector2Array([
		p + Vector2(-27, -14),
		p + Vector2(0, -32),
		p + Vector2(27, -14),
	])
	draw_colored_polygon(roof, Color(0.30, 0.20, 0.17, 1.0))
	draw_rect(Rect2(p.x - 5, p.y + 1, 10, 15), Color(0.23, 0.16, 0.12, 1.0))
	draw_rect(Rect2(p.x - 17, p.y - 6, 8, 8), Color(0.71, 0.76, 0.67, 1.0))
	draw_rect(Rect2(p.x + 9, p.y - 6, 8, 8), Color(0.71, 0.76, 0.67, 1.0))


func _draw_shop(world: Vector2, index: int) -> void:
	var p := _world_to_screen(world)
	var body := _house_color(index)
	draw_rect(Rect2(p - Vector2(28, 16), Vector2(56, 32)), body)
	draw_rect(Rect2(p.x - 29, p.y - 20, 58, 8), Color(0.76, 0.66, 0.42, 1.0))
	draw_rect(Rect2(p.x - 18, p.y - 5, 12, 14), Color(0.66, 0.77, 0.74, 1.0))
	draw_rect(Rect2(p.x + 6, p.y - 5, 12, 14), Color(0.66, 0.77, 0.74, 1.0))


func _draw_pond(world: Vector2) -> void:
	var p := _world_to_screen(world)
	draw_circle(p, 30.0, Color(0.18, 0.34, 0.44, 1.0))
	draw_circle(p + Vector2(18, 7), 18.0, Color(0.18, 0.34, 0.44, 1.0))


func _draw_club(world: Vector2) -> void:
	var p := _world_to_screen(world)
	draw_rect(Rect2(p - Vector2(32, 22), Vector2(64, 44)), Color(0.45, 0.20, 0.18, 1.0))
	draw_rect(Rect2(p.x - 24, p.y - 30, 48, 15), Color(0.72, 0.55, 0.28, 1.0))
	draw_rect(Rect2(p.x - 7, p.y + 1, 14, 21), Color(0.12, 0.09, 0.08, 1.0))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.105, 0.125, 0.085, 1.0))

	# Entire street network. Near intersections now look like neighborhood
	# intersections, not a highway spawning crossbars.
	for i in range(CarRouteData.ROUTE.size() - 1):
		_draw_street(CarRouteData.ROUTE[i], CarRouteData.ROUTE[i + 1])
	for loop in CarRouteData.WRONG_LOOPS:
		for i in range(loop.size() - 1):
			_draw_street(loop[i], loop[i + 1])
	for street in CarRouteData.EXTRA_STREETS:
		_draw_street(street[0], street[1])

	# Small reusable illustrated placeholders. Final assets can replace these
	# without changing DRIVE logic.
	for item in CarRouteData.DECOR:
		var kind := str(item.get("type", ""))
		var pos: Vector2 = item.get("pos", Vector2.ZERO)
		match kind:
			"tree":
				_draw_tree(pos)
			"house":
				_draw_house(pos, int(item.get("color", 0)))
			"shop":
				_draw_shop(pos, int(item.get("color", 0)))
			"pond":
				_draw_pond(pos)
			"club":
				_draw_club(pos)
