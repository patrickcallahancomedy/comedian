class_name DriveGridMap
extends RefCounted

## DRIVE GRID v0.1
## One 800x800 logical board. Every module snaps to MASTER_UNIT so layouts can
## be rearranged like Lego without hand-tuned coordinates.

const MAP_SIZE := Vector2i(800, 800)
const MASTER_UNIT := 10

const NEIGHBORHOOD_CELL := 40
const HIGHWAY_CELL := 20
const HIGHWAY_LANE_WIDTH := 10
const CITY_CELL := 60

const NEIGHBORHOOD_RECT := Rect2(10, 310, 160, 160)
const CONNECTOR_ONE_RECT := Rect2(170, 360, 40, 20)
const HIGHWAY_RECT := Rect2(210, 350, 300, 40)
const CONNECTOR_TWO_RECT := Rect2(510, 380, 40, 20)
const CITY_RECT := Rect2(550, 240, 240, 240)

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
