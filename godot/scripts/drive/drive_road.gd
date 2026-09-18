class_name DriveRoad
extends Control

## DRIVE — Step 1 road.
##
## Static placeholder only. No scrolling, turns, obstacles, minimap, or state.
## Patrick can replace this later without changing the player-car node.

func _draw() -> void:
	var grass := Color(0.12, 0.16, 0.10, 1.0)
	var curb := Color(0.50, 0.47, 0.39, 1.0)
	var asphalt := Color(0.21, 0.21, 0.20, 1.0)
	var center_line := Color(0.67, 0.57, 0.31, 0.55)

	draw_rect(Rect2(Vector2.ZERO, size), grass)

	var road_width := 184.0
	var road_left := (size.x - road_width) * 0.5

	draw_rect(Rect2(road_left - 5.0, 0, road_width + 10.0, size.y), curb)
	draw_rect(Rect2(road_left, 0, road_width, size.y), asphalt)

	for y in range(-20, int(size.y) + 40, 54):
		draw_rect(
			Rect2(size.x * 0.5 - 1.5, float(y), 3.0, 18.0),
			center_line
		)
