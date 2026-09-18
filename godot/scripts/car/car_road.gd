class_name CarRoad
extends Control

## Close-up "maze road" renderer.
##
## The car always moves forward. The player only decides LEFT or RIGHT at each
## intersection. The world recenters after every turn so this stays tiny,
## readable, and reusable.

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
	var field := Color(0.055, 0.09, 0.065, 1.0)
	var field_alt := Color(0.07, 0.115, 0.075, 1.0)
	var road_color := Color(0.16, 0.17, 0.18, 1.0)
	var edge_color := Color(0.38, 0.40, 0.36, 1.0)
	var center_color := Color(0.63, 0.57, 0.26, 0.72)

	draw_rect(Rect2(Vector2.ZERO, size), field)

	# Simple repeating "walls" around the road so it reads more like navigating
	# through a small maze than driving down a giant highway.
	var stripe_h := 56.0
	for i in range(-1, int(size.y / stripe_h) + 2):
		var y := float(i) * stripe_h + fmod(travel_scroll * 0.25, stripe_h)
		draw_rect(Rect2(0, y, 102, 34), field_alt)
		draw_rect(Rect2(size.x - 102, y + 18, 102, 34), field_alt)

	var road_width := 126.0
	var road_x := (size.x - road_width) * 0.5

	draw_rect(Rect2(road_x, 0, road_width, size.y), road_color)
	draw_line(Vector2(road_x, 0), Vector2(road_x, size.y), edge_color, 3.0)
	draw_line(Vector2(road_x + road_width, 0), Vector2(road_x + road_width, size.y), edge_color, 3.0)

	# A subtle moving center line gives forward motion without turning this back
	# into a lane-dodging game.
	var dash_h := 24.0
	var cycle := 64.0
	for i in range(-2, int(size.y / cycle) + 3):
		var dash_y := float(i) * cycle + fmod(travel_scroll, cycle)
		draw_rect(Rect2(size.x * 0.5 - 1.5, dash_y, 3.0, dash_h), center_color)

	if detour_active:
		# During a wrong-turn detour, keep the close-up view deliberately vague.
		# The minimap is what tells the player they left the blue route.
		return

	# The next intersection approaches the car from the top.
	var intersection_y := lerpf(-95.0, size.y - 118.0, approach_progress)
	var cross_h := 112.0
	draw_rect(Rect2(0, intersection_y - cross_h * 0.5, size.x, cross_h), road_color)
	draw_line(Vector2(0, intersection_y - cross_h * 0.5), Vector2(size.x, intersection_y - cross_h * 0.5), edge_color, 3.0)
	draw_line(Vector2(0, intersection_y + cross_h * 0.5), Vector2(size.x, intersection_y + cross_h * 0.5), edge_color, 3.0)

	# The selected direction is shown only as a small mark on the road itself.
	# No giant turn prompt.
	if selected_turn != 0 and approach_progress > 0.45:
		var marker_x := road_x - 35.0 if selected_turn < 0 else road_x + road_width + 35.0
		draw_circle(Vector2(marker_x, intersection_y), 5.0, Color(0.18, 0.50, 1.0, 0.9))
