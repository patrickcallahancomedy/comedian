class_name DriveRoad
extends Control

## Local road view for the DRIVE microgame.
##
## This only draws the current block: a narrow neighborhood street, obstacles,
## and the upcoming intersection. The real player car is a normal TextureRect
## in the scene, so Patrick can replace or resize the PNG without touching code.

var block_progress: float = 0.0
var lane: int = -1
var queued_turn: int = 0
var upcoming_turn: int = 0
var obstacles: Array[Vector2] = []


func set_drive_state(
	new_progress: float,
	new_lane: int,
	new_turn: int,
	new_upcoming_turn: int,
	new_obstacles: Array[Vector2]
) -> void:
	block_progress = clampf(new_progress, 0.0, 1.0)
	lane = clampi(new_lane, -1, 1)
	queued_turn = clampi(new_turn, -1, 1)
	upcoming_turn = clampi(new_upcoming_turn, -1, 1)
	obstacles = new_obstacles
	queue_redraw()


func get_lane_x(which_lane: int) -> float:
	return size.x * 0.5 + float(which_lane) * 34.0


func get_player_y() -> float:
	return size.y * 0.78


func _draw() -> void:
	var grass := Color(0.12, 0.16, 0.10, 1.0)
	var grass_dark := Color(0.09, 0.12, 0.08, 1.0)
	var curb := Color(0.50, 0.47, 0.39, 1.0)
	var asphalt := Color(0.21, 0.21, 0.20, 1.0)
	var center_line := Color(0.67, 0.57, 0.31, 0.55)

	draw_rect(Rect2(Vector2.ZERO, size), grass)

	# Cheap neighborhood silhouettes so this reads as a street, not a highway.
	for y in range(35, int(size.y), 115):
		draw_rect(Rect2(16, y, 58, 38), grass_dark)
		draw_rect(Rect2(size.x - 74, y + 45, 58, 38), grass_dark)

	var road_left := size.x * 0.5 - 92.0
	var road_right := size.x * 0.5 + 92.0
	draw_rect(Rect2(road_left - 5.0, 0, 194.0, size.y), curb)
	draw_rect(Rect2(road_left, 0, 184.0, size.y), asphalt)

	# Moving dashed center line.
	var scroll := fmod(block_progress * 520.0, 54.0)
	for y in range(-60, int(size.y) + 60, 54):
		draw_rect(
			Rect2(size.x * 0.5 - 1.5, float(y) + scroll, 3.0, 18.0),
			center_line
		)

	# The intersection approaches the car as the block completes.
	if upcoming_turn != 0:
		var intersection_y := get_player_y() - (1.0 - block_progress) * 520.0
		draw_rect(Rect2(0, intersection_y - 42.0, size.x, 84.0), curb)
		draw_rect(Rect2(0, intersection_y - 36.0, size.x, 72.0), asphalt)

		# Tiny selection cue only after the player commits to a turn.
		if queued_turn != 0:
			var cue_x := 42.0 if queued_turn < 0 else size.x - 42.0
			draw_circle(Vector2(cue_x, intersection_y), 6.0, Color(0.25, 0.48, 0.88, 0.9))

	# Obstacles are deliberately primitive placeholders. They can become external
	# car assets later without changing the DRIVE rules.
	for obstacle in obstacles:
		var obstacle_lane := int(obstacle.x)
		var obstacle_progress := obstacle.y
		var y := get_player_y() - (obstacle_progress - block_progress) * 520.0
		if y < -70.0 or y > size.y + 70.0:
			continue
		var x := get_lane_x(obstacle_lane)
		draw_rect(Rect2(x - 21.0, y - 34.0, 42.0, 68.0), Color(0.60, 0.28, 0.20, 1.0))
		draw_rect(Rect2(x - 14.0, y - 23.0, 28.0, 15.0), Color(0.48, 0.64, 0.67, 1.0))
