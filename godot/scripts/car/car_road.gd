class_name CarRoad
extends Control

## Close-up road for DRIVE.
##
## This is the near view of the same tiny maze shown in the minimap. The world
## recenters after every turn so the mechanic stays cheap, readable, and reusable.

var approach_progress: float = 0.0
var selected_turn: int = 0
var detour_active: bool = false
var travel_scroll: float = 0.0


func set_approach_progress(value: float) -> void:
	approach_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func set_selected_turn(value: int) -> void:
	selected_turn = clampi(value, -1, 1)
	queue_redraw()


func set_detour_active(value: bool) -> void:
	detour_active = value
	queue_redraw()


func set_travel_scroll(value: float) -> void:
	travel_scroll = value
	queue_redraw()


func _draw() -> void:
	var ground := Color(0.09, 0.105, 0.075, 1.0)
	var ground_alt := Color(0.115, 0.13, 0.088, 1.0)
	var road_color := Color(0.22, 0.215, 0.195, 1.0)
	var road_edge := Color(0.47, 0.43, 0.34, 1.0)
	var center_color := Color(0.68, 0.58, 0.31, 0.52)

	draw_rect(Rect2(Vector2.ZERO, size), ground)

	# Repeating chunky shapes are placeholder town/hedge silhouettes. They give
	# the road edges some illustrated rhythm without requiring bespoke art yet.
	var stripe_h := 72.0
	for i in range(-1, int(size.y / stripe_h) + 2):
		var y := float(i) * stripe_h + fmod(travel_scroll * 0.22, stripe_h)
		draw_rect(Rect2(0, y, 108, 43), ground_alt)
		draw_rect(Rect2(size.x - 98, y + 24, 98, 39), ground_alt)

	var road_width := 128.0
	var road_x := (size.x - road_width) * 0.5

	draw_rect(Rect2(road_x, 0, road_width, size.y), road_color)
	draw_line(Vector2(road_x, 0), Vector2(road_x, size.y), road_edge, 3.0)
	draw_line(Vector2(road_x + road_width, 0), Vector2(road_x + road_width, size.y), road_edge, 3.0)

	# Forward movement.
	var dash_h := 20.0
	var cycle := 60.0
	for i in range(-2, int(size.y / cycle) + 3):
		var dash_y := float(i) * cycle + fmod(travel_scroll, cycle)
		draw_rect(Rect2(size.x * 0.5 - 1.5, dash_y, 3.0, dash_h), center_color)

	if detour_active:
		# A wrong turn becomes a short extra stretch. The minimap is what reveals
		# that Darren left the intended route.
		return

	# The fork slides toward the car.
	var intersection_y := lerpf(-100.0, size.y - 118.0, approach_progress)
	var cross_h := 106.0
	draw_rect(Rect2(0, intersection_y - cross_h * 0.5, size.x, cross_h), road_color)
	draw_line(
		Vector2(0, intersection_y - cross_h * 0.5),
		Vector2(size.x, intersection_y - cross_h * 0.5),
		road_edge,
		3.0
	)
	draw_line(
		Vector2(0, intersection_y + cross_h * 0.5),
		Vector2(size.x, intersection_y + cross_h * 0.5),
		road_edge,
		3.0
	)

	# Your chosen branch gets the smallest possible confirmation. No giant prompt.
	if selected_turn != 0 and approach_progress > 0.48:
		var branch_x := road_x - 30.0 if selected_turn < 0 else road_x + road_width + 30.0
		draw_circle(Vector2(branch_x, intersection_y), 4.0, Color(0.24, 0.42, 0.78, 0.78))
