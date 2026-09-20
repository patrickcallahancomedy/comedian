class_name DriveRoadNetwork
extends RefCounted

## v0.12 road topology.
## Every coordinate below belongs to one continuous world. Gameplay behavior
## changes because the car enters a different road segment, not because a new
## stage or scene is loaded.

const STREET_WIDTH := 88.0
const HIGHWAY_LANE_WIDTH := 78.0
const PARK_LANE_WIDTH := 92.0

const NEIGHBORHOOD_ZOOM := 0.78
const HIGHWAY_ZOOM := 0.52
const CITY_ZOOM := 1.0

const NEIGHBORHOOD_SPEED := 390.0
const CONNECTOR_SPEED := 520.0
const HIGHWAY_SPEED := 920.0
const CITY_SPEED := 430.0
const PARK_SPEED := 280.0

const HIGHWAY_CENTER_X := 0.0
const HIGHWAY_START_Y := 600.0
const HIGHWAY_FORK_Y := -4200.0
const HIGHWAY_END_Y := -8600.0

const CONNECTOR_OUT_START := Vector2(0.0, 2100.0)
const CONNECTOR_OUT_END := Vector2(0.0, HIGHWAY_START_Y)

const EXIT_START := Vector2(117.0, HIGHWAY_FORK_Y)
const EXIT_CONTROL := Vector2(610.0, -4470.0)
const CITY_ENTRY := Vector2(900.0, -5200.0)

const PARK_WIDEN_END := Vector2(2100.0, -7900.0)
const FIRST_PARKING_SPOT_Y := -8750.0


static func neighborhood_nodes() -> Dictionary:
	return {
		"n0": Vector2(0.0, 4200.0),
		"n1": Vector2(-700.0, 3500.0),
		"n2": Vector2(0.0, 3500.0),
		"n3": Vector2(700.0, 3500.0),
		"n4": Vector2(-700.0, 2800.0),
		"n5": Vector2(0.0, 2800.0),
		"n6": Vector2(700.0, 2800.0),
		"n7": CONNECTOR_OUT_START,
	}


static func neighborhood_edges() -> Array:
	return [
		["n0", "n2"],
		["n2", "n1"],
		["n2", "n3"],
		["n2", "n5"],
		["n1", "n4"],
		["n3", "n6"],
		["n4", "n5"],
		["n5", "n6"],
		["n5", "n7"],
	]


static func city_nodes() -> Dictionary:
	return {
		"c0": CITY_ENTRY,
		"c1": Vector2(900.0, -5900.0),
		"c2": Vector2(1500.0, -5900.0),
		"c3": Vector2(2100.0, -5900.0),
		"c4": Vector2(900.0, -6600.0),
		"c5": Vector2(1500.0, -6600.0),
		"c6": Vector2(2100.0, -6600.0),
		"c7": Vector2(1500.0, -7300.0),
		"c8": Vector2(2100.0, -7300.0),
	}


static func city_edges() -> Array:
	return [
		["c0", "c1"],
		["c1", "c2"],
		["c1", "c4"],
		["c2", "c3"],
		["c2", "c5"],
		["c3", "c6"],
		["c4", "c5"],
		["c5", "c6"],
		["c5", "c7"],
		["c6", "c8"],
		["c7", "c8"],
	]


static func all_nodes() -> Dictionary:
	var nodes := neighborhood_nodes()
	for key in city_nodes():
		nodes[key] = city_nodes()[key]
	nodes["connector_out_end"] = CONNECTOR_OUT_END
	nodes["highway_fork"] = Vector2(HIGHWAY_CENTER_X, HIGHWAY_FORK_Y)
	nodes["exit_start"] = EXIT_START
	nodes["park_widen_end"] = PARK_WIDEN_END
	return nodes


static func highway_lane_center(lane: int, lane_count: int = 4) -> float:
	return (
		HIGHWAY_CENTER_X
		+ (float(lane) - float(lane_count - 1) * 0.5)
		* HIGHWAY_LANE_WIDTH
	)


static func exit_curve(t: float) -> Vector2:
	var clamped := clampf(t, 0.0, 1.0)
	var a := EXIT_START.lerp(EXIT_CONTROL, clamped)
	var b := EXIT_CONTROL.lerp(CITY_ENTRY, clamped)
	return a.lerp(b, clamped)


static func exit_curve_tangent(t: float) -> Vector2:
	var clamped := clampf(t, 0.0, 1.0)
	return (
		2.0 * (1.0 - clamped) * (EXIT_CONTROL - EXIT_START)
		+ 2.0 * clamped * (CITY_ENTRY - EXIT_CONTROL)
	).normalized()
