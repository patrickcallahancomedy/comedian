extends Label

## Minimal navigation display for the driving microgame.
## Reads the current drive state and shows only the next useful instruction.
## It does not alter driving, routing, speed, scale, or map geometry.

const MAP = preload("res://scripts/drive/drive_grid_map.gd")

@onready var drive = $"../CityMap"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_instruction()


func _process(_delta: float) -> void:
	_update_instruction()


func _update_instruction() -> void:
	text = get_instruction()


func get_instruction() -> String:
	if drive == null:
		return ""

	if drive.drive_complete:
		return "✓  ARRIVED"

	if not drive.started:
		return "↑  ROUTE READY"

	match drive.road_kind:
		"neighborhood":
			return _grid_instruction(
				drive.heading,
				_neighborhood_desired_direction(drive.neighborhood_cell),
				_neighborhood_blocks_remaining(drive.neighborhood_cell)
			)
		"connector_one":
			return "↑  ON-RAMP"
		"highway":
			if drive.queued_highway_lane < MAP.HIGHWAY_EXIT_LANE:
				return "→  MERGE TO LANE 4"
			if drive.queued_highway_lane > MAP.HIGHWAY_EXIT_LANE:
				return "←  MERGE TO LANE 4"
			return "↑  EXIT AHEAD"
		"connector_two":
			return "↑  CITY AHEAD"
		"city":
			return _grid_instruction(
				drive.heading,
				_city_desired_direction(drive.city_cell),
				_city_blocks_remaining(drive.city_cell)
			)

	return ""


func _neighborhood_desired_direction(cell: Vector2i) -> Vector2i:
	if cell.y > MAP.NEIGHBORHOOD_GATE.y:
		return Vector2i.UP
	if cell.y < MAP.NEIGHBORHOOD_GATE.y:
		return Vector2i.DOWN
	if cell.x < MAP.NEIGHBORHOOD_GATE.x:
		return Vector2i.RIGHT
	if cell.x > MAP.NEIGHBORHOOD_GATE.x:
		return Vector2i.LEFT
	return MAP.NEIGHBORHOOD_GATE_SIDE


func _neighborhood_blocks_remaining(cell: Vector2i) -> int:
	var desired := _neighborhood_desired_direction(cell)
	if desired == Vector2i.UP or desired == Vector2i.DOWN:
		return absi(cell.y - MAP.NEIGHBORHOOD_GATE.y)
	if cell == MAP.NEIGHBORHOOD_GATE:
		return 1
	return absi(cell.x - MAP.NEIGHBORHOOD_GATE.x)


func _city_desired_direction(cell: Vector2i) -> Vector2i:
	if cell.x < MAP.CITY_DESTINATION.x:
		return Vector2i.RIGHT
	if cell.x > MAP.CITY_DESTINATION.x:
		return Vector2i.LEFT
	if cell.y > MAP.CITY_DESTINATION.y:
		return Vector2i.UP
	if cell.y < MAP.CITY_DESTINATION.y:
		return Vector2i.DOWN
	return drive.heading


func _city_blocks_remaining(cell: Vector2i) -> int:
	var desired := _city_desired_direction(cell)
	if desired == Vector2i.LEFT or desired == Vector2i.RIGHT:
		return absi(cell.x - MAP.CITY_DESTINATION.x)
	return absi(cell.y - MAP.CITY_DESTINATION.y)


func _grid_instruction(
	current_heading: Vector2i,
	desired_direction: Vector2i,
	blocks_remaining: int
) -> String:
	# Direction wording is relative to the car, matching the player's controls.
	var arrow_and_word := "↑  STRAIGHT"

	if desired_direction == current_heading:
		arrow_and_word = "↑  STRAIGHT"
	elif desired_direction == Vector2i(current_heading.y, -current_heading.x):
		arrow_and_word = "←  LEFT"
	elif desired_direction == Vector2i(-current_heading.y, current_heading.x):
		arrow_and_word = "→  RIGHT"
	else:
		arrow_and_word = "↶  TURN AROUND"

	if blocks_remaining <= 0:
		return arrow_and_word
	if blocks_remaining == 1:
		return "%s  •  1 BLOCK" % arrow_and_word
	return "%s  •  %d BLOCKS" % [arrow_and_word, blocks_remaining]
