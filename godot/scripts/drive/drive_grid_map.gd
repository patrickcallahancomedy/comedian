class_name DriveGridMap
extends RefCounted

## DRIVE GRID v0.1
## One modular logical board. Every module snaps to MASTER_UNIT so layouts can
## be rearranged like Lego without hand-tuned coordinates.

const MAP_SIZE := Vector2i(1760, 1600)
const MASTER_UNIT := 10

const NEIGHBORHOOD_CELL := 80
const HIGHWAY_CELL := 40
const HIGHWAY_LANE_WIDTH := 20
const CITY_CELL := 120

const NEIGHBORHOOD_RECT := Rect2(20, 620, 320, 320)
const CONNECTOR_ONE_RECT := Rect2(340, 720, 160, 40)
const HIGHWAY_RECT := Rect2(500, 700, 600, 80)
const CONNECTOR_TWO_RECT := Rect2(1100, 760, 160, 40)
const CITY_RECT := Rect2(1260, 480, 480, 480)

const NEIGHBORHOOD_SIZE := Vector2i(4, 4)
const CITY_SIZE := Vector2i(4, 4)
const HIGHWAY_LANES := 4
const HIGHWAY_COLUMNS := 15

const NEIGHBORHOOD_START := Vector2i(1, 3)
const NEIGHBORHOOD_GATE := Vector2i(3, 1)
const NEIGHBORHOOD_GATE_SIDE := Vector2i.RIGHT

const HIGHWAY_ENTRY_LANE := 2
const HIGHWAY_EXIT_LANE := 3

const CITY_ENTRY := Vector2i(0, 2)
const CITY_DESTINATION := Vector2i(3, 1)

const REFERENCE_CELL := float(NEIGHBORHOOD_CELL)


static func is_master_snapped(value: float) -> bool:
	return is_equal_approx(fmod(value, float(MASTER_UNIT)), 0.0)


static func rect_is_master_snapped(rect: Rect2) -> bool:
	return (
		is_master_snapped(rect.position.x)
		and is_master_snapped(rect.position.y)
		and is_master_snapped(rect.size.x)
		and is_master_snapped(rect.size.y)
	)


static func gate_is_on_outer_edge(cell: Vector2i, grid_size: Vector2i) -> bool:
	return (
		cell.x == 0
		or cell.y == 0
		or cell.x == grid_size.x - 1
		or cell.y == grid_size.y - 1
	)


static func gate_faces_outside(
	cell: Vector2i,
	side: Vector2i,
	grid_size: Vector2i
) -> bool:
	if side == Vector2i.LEFT:
		return cell.x == 0
	if side == Vector2i.RIGHT:
		return cell.x == grid_size.x - 1
	if side == Vector2i.UP:
		return cell.y == 0
	if side == Vector2i.DOWN:
		return cell.y == grid_size.y - 1
	return false


static func neighborhood_connections(cell: Vector2i) -> Array[Vector2i]:
	# The neighborhood is a 4x4 road graph:
	# - four corner cells are turns
	# - non-corner perimeter cells are T-junctions that connect the outer loop
	#   to the inner grid
	# - the four inner cells are four-way intersections
	# - the fixed gate cell also opens outward to the connector
	var connections: Array[Vector2i] = []

	var max_x := NEIGHBORHOOD_SIZE.x - 1
	var max_y := NEIGHBORHOOD_SIZE.y - 1

	if cell == Vector2i(0, 0):
		connections = [Vector2i.RIGHT, Vector2i.DOWN]
	elif cell == Vector2i(max_x, 0):
		connections = [Vector2i.LEFT, Vector2i.DOWN]
	elif cell == Vector2i(0, max_y):
		connections = [Vector2i.RIGHT, Vector2i.UP]
	elif cell == Vector2i(max_x, max_y):
		connections = [Vector2i.LEFT, Vector2i.UP]
	elif cell.y == 0:
		connections = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]
	elif cell.y == max_y:
		connections = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]
	elif cell.x == 0:
		connections = [Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT]
	elif cell.x == max_x:
		connections = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT]
	else:
		connections = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

	if cell == NEIGHBORHOOD_GATE and not connections.has(NEIGHBORHOOD_GATE_SIDE):
		connections.append(NEIGHBORHOOD_GATE_SIDE)

	return connections


static func neighborhood_has_connection(cell: Vector2i, direction: Vector2i) -> bool:
	return neighborhood_connections(cell).has(direction)


static func neighborhood_cells_connect(a: Vector2i, b: Vector2i) -> bool:
	var delta := b - a
	if abs(delta.x) + abs(delta.y) != 1:
		return false
	return (
		neighborhood_has_connection(a, delta)
		and neighborhood_has_connection(b, -delta)
	)


static func neighborhood_cell_center(cell: Vector2i) -> Vector2:
	return NEIGHBORHOOD_RECT.position + Vector2(
		(float(cell.x) + 0.5) * NEIGHBORHOOD_CELL,
		(float(cell.y) + 0.5) * NEIGHBORHOOD_CELL
	)


static func city_cell_center(cell: Vector2i) -> Vector2:
	return CITY_RECT.position + Vector2(
		(float(cell.x) + 0.5) * CITY_CELL,
		(float(cell.y) + 0.5) * CITY_CELL
	)


static func highway_cell_center(column: int, lane: int) -> Vector2:
	return HIGHWAY_RECT.position + Vector2(
		(float(column) + 0.5) * HIGHWAY_CELL,
		(float(lane) + 0.5) * HIGHWAY_LANE_WIDTH
	)


static func neighborhood_gate_outside_point() -> Vector2:
	return neighborhood_cell_center(NEIGHBORHOOD_GATE) + Vector2(
		NEIGHBORHOOD_GATE_SIDE.x,
		NEIGHBORHOOD_GATE_SIDE.y
	) * NEIGHBORHOOD_CELL


static func highway_entry_point() -> Vector2:
	return highway_cell_center(0, HIGHWAY_ENTRY_LANE)


static func highway_exit_point() -> Vector2:
	return highway_cell_center(HIGHWAY_COLUMNS - 1, HIGHWAY_EXIT_LANE)


static func city_entry_point() -> Vector2:
	return city_cell_center(CITY_ENTRY)


static func car_scale_for_cell(cell_size: float) -> float:
	return cell_size / REFERENCE_CELL
