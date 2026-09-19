extends Control
#constants
@export var grid_size: int = 5
@export var block_size: float = 70.0
@export var road_width: float = 8.0
@export var roads_to_remove: int = 8

#variables
var intersections: Array[Vector2i] = []
var roads: Array = []
var start_intersection := Vector2i(0, 4)
var destination_intersection := Vector2i(4, 0)
var shortest_route: Array[Vector2i] = []
var rng := RandomNumberGenerator.new()
var current_intersection := Vector2i(0, 4)
var heading := Vector2i(0, -1)

#functions
func _ready() -> void:
	rng.randomize()

	_build_intersections()
	_build_roads()
	_remove_random_roads()
	
	shortest_route = _find_shortest_route(
		current_intersection,
		destination_intersection
	)
	
	print("City connected: ", _city_is_connected())
#end of ready()

func _build_intersections() -> void:
	intersections.clear()

	for y in range(grid_size):
		for x in range(grid_size):
			intersections.append(Vector2i(x, y))
			
#end of _build interactions

func _build_roads() -> void:
	roads.clear()

	for y in range(grid_size):
		for x in range(grid_size):

			# Connect to the intersection on the right.
			if x < grid_size - 1:
				roads.append([
					Vector2i(x, y),
					Vector2i(x + 1, y)
				])

			# Connect to the intersection below.
			if y < grid_size - 1:
				roads.append([
					Vector2i(x, y),
					Vector2i(x, y + 1)
				])
				
#end of build roads

func _draw() -> void:
	var city_width := (grid_size - 1) * block_size
	var city_height := (grid_size - 1) * block_size

	# Center the city on the screen.
	var start := Vector2(
		(size.x - city_width) / 2.0,
		(size.y - city_height) / 2.0
	)

	var road_color := Color(0.2, 0.2, 0.2)

	# Draw every road stored in our roads list.
	for road in roads:
		var start_intersection: Vector2i = road[0]
		var end_intersection: Vector2i = road[1]

		var road_start := start + Vector2(start_intersection) * block_size
		var road_end := start + Vector2(end_intersection) * block_size

		draw_line(
			road_start,
			road_end,
			road_color,
			road_width
		)

	# Draw a red dot at every intersection.
	for intersection in intersections:
		var point := start + Vector2(intersection) * block_size
		draw_circle(point, 5.0, Color.RED)
		
		
	for i in range(shortest_route.size() - 1):
		var a := start + Vector2(shortest_route[i]) * block_size
		var b := start + Vector2(shortest_route[i + 1]) * block_size

		draw_line(
			a,
			b,
			Color.YELLOW,
			4.0
	)
	var current_point := start + Vector2(current_intersection) * block_size
	var destination_point := start + Vector2(destination_intersection) * block_size

	draw_circle(current_point, 10.0, Color.GREEN)
	var heading_end := current_point + Vector2(heading) * 22.0

	draw_line(
		current_point,
		heading_end,
		Color.GREEN,
		5.0
	)
	draw_circle(destination_point, 10.0, Color.BLUE)
#end of draw

func _city_is_connected() -> bool:
	if intersections.is_empty():
		return true

	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []

	var first_intersection: Vector2i = intersections[0]
	queue.append(first_intersection)
	visited[first_intersection] = true

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()

		for road in roads:
			var a: Vector2i = road[0]
			var b: Vector2i = road[1]

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

func _remove_random_roads() -> void:
	var removed_count := 0
	var attempts := 0

	while removed_count < roads_to_remove and attempts < 100:
		attempts += 1

		var road_index := rng.randi_range(0, roads.size() - 1)
		var removed_road = roads[road_index]

		roads.remove_at(road_index)

		if _city_is_connected():
			removed_count += 1
		else:
			roads.insert(road_index, removed_road)
#end of remove random roads

func _find_shortest_route(
	start_node: Vector2i,
	end_node: Vector2i
) -> Array[Vector2i]:

	var queue: Array[Vector2i] = [start_node]
	var came_from: Dictionary = {}

	came_from[start_node] = start_node

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()

		if current == end_node:
			break

		for road in roads:
			var a: Vector2i = road[0]
			var b: Vector2i = road[1]

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

func _road_exists_between(a: Vector2i, b: Vector2i) -> bool:
	for road in roads:
		var road_a: Vector2i = road[0]
		var road_b: Vector2i = road[1]

		if (road_a == a and road_b == b) or (road_a == b and road_b == a):
			return true

	return false
#end road exist between

func _try_move(direction: Vector2i) -> void:
	var next_intersection := current_intersection + direction

	if not intersections.has(next_intersection):
		return

	if not _road_exists_between(current_intersection, next_intersection):
		return

	current_intersection = next_intersection

	shortest_route = _find_shortest_route(
		current_intersection,
		destination_intersection
	)
	queue_redraw()
#end try inbetween

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	if not event.pressed:
		return

	match event.keycode:
		KEY_UP:
			_try_move(Vector2i(0, -1))
		KEY_DOWN:
			_try_move(Vector2i(0, 1))
		KEY_LEFT:
			_try_move(Vector2i(-1, 0))
		KEY_RIGHT:
			_try_move(Vector2i(1, 0))
		KEY_A:
			heading = Vector2i(heading.y, -heading.x)
			queue_redraw()
		KEY_D:
			heading = Vector2i(-heading.y, heading.x)
			queue_redraw()
		KEY_W:
			_try_move(heading)
			
#end unhandled key input
