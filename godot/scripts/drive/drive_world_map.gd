class_name DriveWorldMap
extends RefCounted

## COMEDIAN driving world rebuild.
## One physical world: neighborhood -> ramp -> freeway -> exit -> city -> venue.
## Geometry lives here; drawing, movement, GPS, and tests all consume it.

const WORLD_RECT := Rect2(0, 0, 1800, 1100)

const LOCAL_ROAD_WIDTH := 18.0
const LOCAL_SIDEWALK_WIDTH := 26.0
const HIGHWAY_LANES := 4
const HIGHWAY_LANE_WIDTH := 12.0
const HIGHWAY_ENTRY_LANE := 3
const HIGHWAY_EXIT_LANE := 3

# Two freeway carriageways are visible so the world reads like an interchange.
# Darren drives west on the lower carriageway.
const HIGHWAY_RECT := Rect2(300, 440, 1200, 48)
const OPPOSITE_HIGHWAY_RECT := Rect2(300, 376, 1200, 48)
const HIGHWAY_ENTRY_X := 1120.0
const HIGHWAY_EXIT_X := 560.0
const HIGHWAY_REROUTE_EXIT_X := 360.0
const HIGHWAY_STEP := 40.0

const NEIGHBORHOOD_START := "n22"
const NEIGHBORHOOD_GATE := "n00"
const CITY_ENTRY := "c20"
const CITY_PARKING_NODE := "c22"

const NEIGHBORHOOD_NODES := {
	"n00": Vector2(1240, 600),
	"n10": Vector2(1380, 600),
	"n20": Vector2(1520, 600),
	"n01": Vector2(1240, 740),
	"n11": Vector2(1380, 740),
	"n21": Vector2(1520, 740),
	"n02": Vector2(1240, 880),
	"n12": Vector2(1380, 880),
	"n22": Vector2(1520, 880),
}

const NEIGHBORHOOD_EDGES := [
	["n00", "n01"], ["n01", "n02"],
	["n10", "n11"], ["n11", "n12"],
	["n20", "n21"], ["n21", "n22"],
	["n00", "n10"], ["n10", "n20"],
	["n01", "n11"], ["n11", "n21"],
	["n02", "n12"], ["n12", "n22"],
]

const CITY_NODES := {
	"c00": Vector2(180, 620),
	"c10": Vector2(320, 620),
	"c20": Vector2(460, 620),
	"c01": Vector2(180, 760),
	"c11": Vector2(320, 760),
	"c21": Vector2(460, 760),
	"c02": Vector2(180, 900),
	"c12": Vector2(320, 900),
	"c22": Vector2(460, 900),
}

const CITY_EDGES := [
	["c00", "c01"], ["c01", "c02"],
	["c10", "c11"], ["c11", "c12"],
	["c21", "c22"],
	["c00", "c10"], ["c10", "c20"],
	["c01", "c11"], ["c11", "c21"],
	["c02", "c12"],
]

const PARKING_ENTRY := Vector2(420, 900)
const PARKING_AISLE := Vector2(385, 900)
const PARKING_LEFT_SPACE := Vector2(365, 860)
const PARKING_RIGHT_SPACE := Vector2(365, 940)
const PARKING_LOT_RECT := Rect2(340, 825, 110, 150)
const VENUE_RECT := Rect2(195, 815, 130, 170)


static func node_position(area: String, node_id: String) -> Vector2:
	var nodes: Dictionary = (
		NEIGHBORHOOD_NODES if area == "neighborhood" else CITY_NODES
	)
	return nodes.get(node_id, Vector2.ZERO)


static func edges_for(area: String) -> Array:
	return NEIGHBORHOOD_EDGES if area == "neighborhood" else CITY_EDGES


static func nodes_for(area: String) -> Dictionary:
	return NEIGHBORHOOD_NODES if area == "neighborhood" else CITY_NODES


static func neighbors(area: String, node_id: String) -> Array[String]:
	var result: Array[String] = []
	for edge in edges_for(area):
		if String(edge[0]) == node_id:
			result.append(String(edge[1]))
		elif String(edge[1]) == node_id:
			result.append(String(edge[0]))
	return result


static func shortest_path(area: String, start_id: String, target_id: String) -> Array[String]:
	if start_id == target_id:
		return [start_id]

	var queue: Array[String] = [start_id]
	var came_from := {start_id: ""}

	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor in neighbors(area, current):
			if came_from.has(neighbor):
				continue
			came_from[neighbor] = current
			if neighbor == target_id:
				var path: Array[String] = [target_id]
				var cursor := current
				while not cursor.is_empty():
					path.push_front(cursor)
					cursor = String(came_from.get(cursor, ""))
				return path
			queue.append(neighbor)

	return []


static func cardinal_direction(from_point: Vector2, to_point: Vector2) -> Vector2i:
	var delta := to_point - from_point
	if absf(delta.x) >= absf(delta.y):
		return Vector2i.RIGHT if delta.x > 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if delta.y > 0.0 else Vector2i.UP


static func turn_kind(incoming: Vector2i, outgoing: Vector2i) -> String:
	if outgoing == incoming:
		return "straight"
	if outgoing == -incoming:
		return "back"
	var cross := incoming.x * outgoing.y - incoming.y * outgoing.x
	return "right" if cross > 0 else "left"


static func highway_lane_center(lane: int, x: float) -> Vector2:
	return Vector2(
		x,
		HIGHWAY_RECT.position.y
			+ float(lane) * HIGHWAY_LANE_WIDTH
			+ HIGHWAY_LANE_WIDTH * 0.5
	)


static func highway_entry_point() -> Vector2:
	return highway_lane_center(HIGHWAY_ENTRY_LANE, HIGHWAY_ENTRY_X)


static func highway_exit_point() -> Vector2:
	return highway_lane_center(HIGHWAY_EXIT_LANE, HIGHWAY_EXIT_X)


static func onramp_points() -> PackedVector2Array:
	var start := node_position("neighborhood", NEIGHBORHOOD_GATE)
	var end := highway_entry_point()
	var control_one := start + Vector2(-150.0, 0.0)
	var control_two := end + Vector2(110.0, 70.0)
	return _sample_cubic(start, control_one, control_two, end, 22)


static func offramp_points(reroute: bool = false) -> PackedVector2Array:
	var start_x := HIGHWAY_REROUTE_EXIT_X if reroute else HIGHWAY_EXIT_X
	var start := highway_lane_center(HIGHWAY_EXIT_LANE, start_x)
	var end := node_position("city", CITY_ENTRY)
	var control_one := (
		start + Vector2(70.0, 0.0)
		if reroute
		else start + Vector2(-80.0, 0.0)
	)
	var control_two := (
		end + Vector2(-100.0, -80.0)
		if reroute
		else end + Vector2(70.0, -90.0)
	)
	return _sample_cubic(start, control_one, control_two, end, 18)


static func _sample_cubic(
	start: Vector2,
	control_one: Vector2,
	control_two: Vector2,
	end: Vector2,
	samples: int
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(samples + 1):
		var t := float(index) / float(samples)
		var inverse := 1.0 - t
		points.append(
			start * inverse * inverse * inverse
			+ control_one * 3.0 * inverse * inverse * t
			+ control_two * 3.0 * inverse * t * t
			+ end * t * t * t
		)
	return points


static func route_points_for_local(
	area: String,
	current_node: String,
	target_node: String
) -> PackedVector2Array:
	var path := shortest_path(area, current_node, target_node)
	var points := PackedVector2Array()
	for node_id in path:
		points.append(node_position(area, node_id))
	return points


static func all_local_edges(area: String) -> Array:
	return edges_for(area)
