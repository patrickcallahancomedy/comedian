extends Control
#constants
# These are the main tuning values for the current DRIVE prototype.
# They are exposed in the Inspector so we can change feel/scale without rewriting code.
@export var grid_size: int = 5
@export var block_size: float = 650.0
@export var road_width: float = 380.0
@export var roads_to_remove: int = 8
@export var drive_speed: float = 0.35

#variables
#build map
# The generated city lives in these two collections.
# intersections = every possible point Darren can reach.
# roads = the actual connections between those points.
var intersections: Array[Vector2i] = []
var roads: Array = []
var rng := RandomNumberGenerator.new()
#shortest route calc
# These values describe where Darren starts, where he is going,
# and the current GPS route between those two points.
var start_intersection := Vector2i(0, 4)
var destination_intersection := Vector2i(4, 0)
var shortest_route: Array[Vector2i] = []
#drive time calc
# These values describe Darren's live position and movement through the city.
# current_intersection is exact game logic; camera_position can sit between intersections
# so the city can slide smoothly underneath the stationary car.
var current_intersection := Vector2i(0, 4)
var camera_position := Vector2(0, 4)
var is_driving: bool = false
var target_intersection := Vector2i(0, 4)
var camera_target := Vector2(0, 4)
var heading := Vector2i(0, -1)
var view_rotation: float = 0.0
var target_view_rotation: float = 0.0
#drive time stats
# These are result values we can eventually hand back to the larger COMEDIAN game.
var wrong_turns: int = 0
var drive_time: float = 0.0


#touch / keyboard controls
# The buttons and keyboard both call the same movement functions below.
@onready var left_button: Button = $"../TouchControls/LeftButton"
@onready var forward_button: Button = $"../TouchControls/ForwardButton"
@onready var right_button: Button = $"../TouchControls/RightButton"

#functions
# Scene setup.
# Builds a fresh procedural city, finds the first GPS route,
# and connects the on-screen controls to the driving functions.
func _ready() -> void:
	# Give each run a different procedural road layout.
	rng.randomize()

	# Build the city in three passes: points, roads, then safe random removals.
	_build_intersections()
	_build_roads()
	_remove_random_roads()
	
	# Calculate the initial GPS route before the player starts driving.
	shortest_route = _find_shortest_route(
		current_intersection,
		destination_intersection
	)
	
	left_button.pressed.connect(_turn_left)
	forward_button.pressed.connect(_move_forward)
	right_button.pressed.connect(_turn_right)

	print("City connected: ", _city_is_connected())
#end of ready()

# Build every possible intersection in the square grid.
# Example: grid_size 5 creates coordinates from (0,0) through (4,4).
func _build_intersections() -> void:
	intersections.clear()

	for y in range(grid_size):
		for x in range(grid_size):
			intersections.append(Vector2i(x, y))
			
#end of _build interactions

# Build the starting road network.
# Each road is stored as a dictionary so we can later add properties like
# length, road type, one-way direction, speed, etc. without changing every system.
func _build_roads() -> void:
	roads.clear()

	for y in range(grid_size):
		for x in range(grid_size):

			# Connect to the intersection on the right.
			if x < grid_size - 1:
				roads.append({
					"from": Vector2i(x, y),
					"to": Vector2i(x + 1, y),
					"length": 1,
					"one_way": false
				})

			# Connect to the intersection below.
			if y < grid_size - 1:
				roads.append({
					"from": Vector2i(x, y),
					"to": Vector2i(x, y + 1),
					"length": 1,
					"one_way": false
				})
				
	# TEMP TEST LEFT IN CURRENT BUILD:
	# Force one road to be one-way so the data structure can be tested later.
	# This is not yet connected to tickets or driving restrictions.
	if roads.size() > 0:
		roads[0]["one_way"] = true
#end of build roads

# Runs every frame.
# This is the heart of the current driving prototype:
# 1. smoothly rotate the city when Darren turns,
# 2. smoothly slide the city while Darren drives,
# 3. detect arrival at intersections,
# 4. reroute the GPS and decide what happens next.
func _process(delta: float) -> void:
	# Smoothly rotate the city underneath the fixed car.
	if not is_equal_approx(view_rotation, target_view_rotation):
		view_rotation = lerp_angle(
			view_rotation,
			target_view_rotation,
			minf(1.0, delta * 10.0)
		)

	# Only advance movement/time after GO has started the drive.
	if is_driving:
		drive_time += delta

		var target_position := Vector2(target_intersection)

		# Smoothly move the city until Darren reaches the next intersection.
		camera_position = camera_position.move_toward(
			target_position,
			drive_speed * delta
		)

		# Darren has reached the intersection.
		if camera_position.is_equal_approx(target_position):
			camera_position = target_position
			current_intersection = target_intersection

			# Darren is now logically at this intersection, so recalculate the GPS
			# from his real position before deciding which road he takes next.
			shortest_route = _find_shortest_route(
				current_intersection,
				destination_intersection
			)

			# Destination reached.
			if current_intersection == destination_intersection:
				is_driving = false

				print("ARRIVED")
				print("Drive time: ", snappedf(drive_time, 0.1), " seconds")
				print("Wrong turns: ", wrong_turns)

				queue_redraw()
				return

			# Look one intersection ahead in Darren's current heading.
			# Because heading can change while he is moving, this creates the current
			# "drift / queued turn" behavior: be facing the right way when you arrive.
			var next_intersection := current_intersection + heading

			if (
				intersections.has(next_intersection)
				and _road_exists_between(current_intersection, next_intersection)
			):
				# Compare Darren's choice with the GPS recommendation.
				if shortest_route.size() >= 2:
					var recommended_direction: Vector2i = (
						shortest_route[1] - current_intersection
					)

					if heading != recommended_direction:
						wrong_turns += 1
						print("Wrong turns: ", wrong_turns)

				# Continue driving in Darren's chosen direction.
				target_intersection = next_intersection

				# Immediately reroute from the intersection we're now
				# approaching so the GPS gives the player time to react.
				shortest_route = _find_shortest_route(
					target_intersection,
					destination_intersection
				)

			else:
				# No road exists in the direction Darren is facing, so the current
				# prototype stops instead of letting him drive off the road.
				is_driving = false

	queue_redraw()

#end of process

# Convert a city intersection into an on-screen position.
# The car stays fixed. Instead, every road/intersection is positioned relative
# to Darren and then rotated so the map moves underneath him.
func _city_to_screen(intersection: Vector2i) -> Vector2:
	# Darren stays fixed in the center of the screen.
	# Every city point is drawn relative to Darren, then rotated so his
	# current heading always appears to point toward the top of the screen.
	var grid_offset := Vector2(intersection) - camera_position
	var world_offset := Vector2(grid_offset.x, grid_offset.y) * block_size
	var rotated_offset := world_offset.rotated(view_rotation)

	return size * 0.5 + rotated_offset
#end city to screen


# Draw the current debug version of the city.
# This is only the renderer: it reads the generated city data and paints roads,
# intersections, GPS route, destination, and debug markers to the screen.
func _draw() -> void:
	var road_color := Color(0.2, 0.2, 0.2)

	# Draw the roads from the same generated city data.
	for road in roads:
		var road_start := _city_to_screen(_road_start(road))
		var road_end := _city_to_screen(_road_end(road))
	
		draw_line(
			road_start,
			road_end,
			road_color,
			road_width
		)

	# Draw every intersection.
	for intersection in intersections:
		var point := _city_to_screen(intersection)
		draw_circle(point, 5.0, Color.RED)

	# Draw the current shortest GPS route.
	for i in range(shortest_route.size() - 1):
		var a := _city_to_screen(shortest_route[i])
		var b := _city_to_screen(shortest_route[i + 1])

		draw_line(
			a,
			b,
			Color.YELLOW,
			4.0
		)

	# Darren never moves visually. The city moves underneath him.
	var current_point := size * 0.5
	var destination_point := _city_to_screen(destination_intersection)

	draw_circle(current_point, 10.0, Color.GREEN)
	draw_circle(destination_point, 10.0, Color.BLUE)

	# Because the world rotates opposite Darren's heading, this debug marker
	# should stay pointing toward the top of the screen.
	draw_line(
		current_point,
		current_point + Vector2.UP * 22.0,
		Color.GREEN,
		5.0
	)
	
	
#end of draw

# Safety check for procedural generation.
# Returns true only if every intersection can still be reached from every other
# part of the city after roads have been removed.
func _city_is_connected() -> bool:
	if intersections.is_empty():
		return true

	# Start at one intersection and flood through every connected road.
	# If we can visit every intersection, the generated city is still usable.
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []

	var first_intersection: Vector2i = intersections[0]
	queue.append(first_intersection)
	visited[first_intersection] = true

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()

		for road in roads:
			var a: Vector2i = _road_start(road)
			var b: Vector2i = _road_end(road)

			var neighbor := Vector2i.ZERO
			var found_neighbor := false

			if a == current:
				neighbor = b
				found_neighbor = true
			elif b == current:
				neighbor = a
				found_neighbor = true

			if found_neighbor and not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)

	return visited.size() == intersections.size()
#end of city is connected

# Procedurally remove roads to make each city layout different.
# A road removal is only kept if _city_is_connected() says the city still works.
func _remove_random_roads() -> void:
	var removed_count := 0
	var attempts := 0

	while removed_count < roads_to_remove and attempts < 100:
		attempts += 1

		var road_index := rng.randi_range(0, roads.size() - 1)
		var removed_road = roads[road_index]

		# Temporarily remove the candidate road.
		roads.remove_at(road_index)

		# Keep the removal only if the whole city is still connected.
		if _city_is_connected():
			removed_count += 1
		else:
			roads.insert(road_index, removed_road)
#end of remove random roads

# GPS / pathfinding.
# Uses a breadth-first search because every current road segment has equal cost.
# Returns an ordered list of intersections from start_node to end_node.
func _find_shortest_route(
	start_node: Vector2i,
	end_node: Vector2i
) -> Array[Vector2i]:

	# queue = intersections still waiting to be checked.
	# came_from = how we reached each intersection so we can rebuild the route later.
	var queue: Array[Vector2i] = [start_node]
	var came_from: Dictionary = {}

	came_from[start_node] = start_node

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()

		if current == end_node:
			break

		for road in roads:
			var a: Vector2i =  _road_start(road)
			var b: Vector2i = _road_end(road)

			var neighbor := Vector2i.ZERO
			var found_neighbor := false

			if a == current:
				neighbor = b
				found_neighbor = true
			elif b == current:
				neighbor = a
				found_neighbor = true

			if found_neighbor and not came_from.has(neighbor):
				came_from[neighbor] = current
				queue.append(neighbor)

	# Rebuild the final route backwards from destination to start.
	var route: Array[Vector2i] = []

	if not came_from.has(end_node):
		return route

	var current := end_node

	while current != start_node:
		route.push_front(current)
		current = came_from[current]

	route.push_front(start_node)

	return route
#end of find shortest route

# Simple yes/no road check used by the driving code.
# The actual road lookup is handled by _get_road_between() below.
func _road_exists_between(a: Vector2i, b: Vector2i) -> bool:
	return _get_road_between(a, b) != null
#end road exist between

# Older one-intersection movement helper kept for debugging/reference.
# It instantly changes Darren's logical intersection instead of using the
# continuous driving system in _process().
func _try_move(direction: Vector2i) -> void:
	var next_intersection := current_intersection + direction

	if not intersections.has(next_intersection):
		return

	if not _road_exists_between(current_intersection, next_intersection):
		return

	current_intersection = next_intersection
	camera_target = Vector2(current_intersection)

	shortest_route = _find_shortest_route(
		current_intersection,
		destination_intersection
	)
	queue_redraw()
#end try inbetween

# Turn Darren's logical heading left.
# The car sprite stays still; target_view_rotation rotates the city underneath it.
func _turn_left() -> void:
	heading = Vector2i(heading.y, -heading.x)
	target_view_rotation += PI / 2.0
#end turn left

# Turn Darren's logical heading right.
# The car sprite stays still; target_view_rotation rotates the city underneath it.
func _turn_right() -> void:
	heading = Vector2i(-heading.y, heading.x)
	target_view_rotation -= PI / 2.0
#end turn right

# Start the drive.
# GO only begins movement if there is a legal road directly in front of Darren.
# Once driving, _process() handles continuous movement from intersection to intersection.
func _move_forward() -> void:
	if is_driving:
		return
		
	var next_intersection := current_intersection + heading

	if not intersections.has(next_intersection):
		return

	if not _road_exists_between(current_intersection, next_intersection):
		return

	target_intersection = next_intersection
	is_driving = true
#end move forward

# Desktop test controls.
# A = turn left, D = turn right, W = start driving.
# These call the same functions as the touch buttons so both control schemes stay in sync.
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	if not event.pressed:
		return

	match event.keycode:
		KEY_A:
			_turn_left()

		KEY_D:
			_turn_right()

		KEY_W:
			_move_forward()
			
#end unhandled key input

#helper functions
# These helpers keep the rest of the script from caring how a road is stored.
# That lets us upgrade road data later without hunting through every function.

# Return the starting intersection stored inside a road.
# Supports both the newer dictionary format and the older two-item array format.
func _road_start(road) -> Vector2i:
	if typeof(road) == TYPE_DICTIONARY:
		return road["from"]

	return road[0]
#end road start

# Return the ending intersection stored inside a road.
# Supports both the newer dictionary format and the older two-item array format.
func _road_end(road) -> Vector2i:
	if typeof(road) == TYPE_DICTIONARY:
		return road["to"]

	return road[1]
#end road end

# Find and return the actual road object connecting two intersections.
# Returns null if those intersections are not directly connected.
func _get_road_between(a: Vector2i, b: Vector2i):
	for road in roads:
		var road_a: Vector2i = _road_start(road)
		var road_b: Vector2i = _road_end(road)

		if (road_a == a and road_b == b) or (road_a == b and road_b == a):
			return road

	return null
#end get road between

# Check whether Darren is travelling against a one-way road.
# For a one-way road, the legal direction is always from road["from"] to road["to"].
# This exists for the future ticket / license consequence system and is not active yet.
func _is_wrong_way(
	road,
	travel_from: Vector2i,
	travel_to: Vector2i
) -> bool:

	if not road["one_way"]:
		return false

	var legal_from: Vector2i = _road_start(road)
	var legal_to: Vector2i = _road_end(road)

	return travel_from != legal_from or travel_to != legal_to
#end is wrong way
