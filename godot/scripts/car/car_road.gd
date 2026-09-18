class_name CarRoad
extends Control

## Lightweight top-down road renderer for the Car microgame.
##
## This intentionally draws only the boring reusable road. Cars, HUD, phone
## interruptions, and all gameplay remain separate children/nodes.

var scroll_offset: float = 0.0
var intersection_progress: float = -1.0


func set_scroll_offset(value: float) -> void:
	scroll_offset = value
	queue_redraw()


func set_intersection_progress(value: float) -> void:
	intersection_progress = value
	queue_redraw()


func _draw() -> void:
	var road_rect := Rect2(Vector2.ZERO, size)
	draw_rect(road_rect, Color(0.115, 0.12, 0.13, 1.0))

	# Shoulders.
	draw_rect(Rect2(0, 0, 6, size.y), Color(0.68, 0.67, 0.61, 1.0))
	draw_rect(Rect2(size.x - 6, 0, 6, size.y), Color(0.68, 0.67, 0.61, 1.0))

	# Scrolling dashed lane markers.
	var dash_height := 34.0
	var dash_gap := 34.0
	var cycle := dash_height + dash_gap
	var divider_x := [size.x / 3.0, size.x * 2.0 / 3.0]

	for x in divider_x:
		for i in range(-2, int(size.y / cycle) + 3):
			var y := float(i) * cycle + fmod(scroll_offset, cycle)
			draw_rect(
				Rect2(x - 1.5, y, 3.0, dash_height),
				Color(0.72, 0.72, 0.68, 0.52)
			)

	# Every route segment ends at a visible cross street. The player has to be
	# in the correct side lane when it reaches Darren's car.
	if intersection_progress >= 0.0:
		var y := lerpf(-110.0, size.y + 80.0, clampf(intersection_progress, 0.0, 1.0))
		draw_rect(
			Rect2(0, y - 38.0, size.x, 76.0),
			Color(0.145, 0.15, 0.16, 1.0)
		)
		draw_line(Vector2(0, y - 38.0), Vector2(size.x, y - 38.0), Color(0.45, 0.45, 0.42, 0.75), 2.0)
		draw_line(Vector2(0, y + 38.0), Vector2(size.x, y + 38.0), Color(0.45, 0.45, 0.42, 0.75), 2.0)
