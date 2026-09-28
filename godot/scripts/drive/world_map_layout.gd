class_name ComedianWorldMapLayout
extends RefCounted

## Static geometry only. No car/gameplay state lives here.
## This is the first-pass physical world for the COMEDIAN driving rebuild.

const WORLD_SIZE := Vector2(1000.0, 1200.0)

const LOCAL_ROAD_WIDTH := 22.0
const LOCAL_SIDEWALK_WIDTH := 30.0

const HIGHWAY_LANES := 4
const HIGHWAY_LANE_WIDTH := 11.0
const HIGHWAY_SHOULDER := 5.0

# Upper carriageway travels west; lower carriageway travels east.
const WESTBOUND_HIGHWAY := Rect2(0.0, 520.0, 1000.0, 44.0)
const EASTBOUND_HIGHWAY := Rect2(0.0, 590.0, 1000.0, 44.0)

# Venue / destination area. Gameplay comes later.
const VENUE_RECT := Rect2(105, 175, 70, 72)
const VENUE_PARKING_RECT := Rect2(105, 250, 70, 50)
const HOME_RECT := Rect2(812, 950, 44, 34)


static func neighborhood_roads() -> Array:
	return [
		PackedVector2Array([Vector2(650, 760), Vector2(910, 760)]),
		PackedVector2Array([Vector2(650, 900), Vector2(910, 900)]),
		PackedVector2Array([Vector2(650, 1040), Vector2(910, 1040)]),
		PackedVector2Array([Vector2(650, 760), Vector2(650, 1040)]),
		PackedVector2Array([Vector2(780, 760), Vector2(780, 1040)]),
		PackedVector2Array([Vector2(910, 760), Vector2(910, 1040)]),
	]


static func city_roads() -> Array:
	return [
		PackedVector2Array([Vector2(90, 150), Vector2(390, 150)]),
		PackedVector2Array([Vector2(90, 275), Vector2(390, 275)]),
		PackedVector2Array([Vector2(90, 400), Vector2(390, 400)]),
		PackedVector2Array([Vector2(90, 150), Vector2(90, 400)]),
		PackedVector2Array([Vector2(190, 150), Vector2(190, 400)]),
		PackedVector2Array([Vector2(290, 150), Vector2(290, 400)]),
		PackedVector2Array([Vector2(390, 150), Vector2(390, 400)]),
	]


static func neighborhood_feeder() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(650, 760),
		Vector2(605, 735),
		Vector2(565, 700),
	])


static func city_entry_road() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(205, 410),
		Vector2(205, 400),
		Vector2(190, 400),
	])


static func wrong_exit_road() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(835, 440),
		Vector2(895, 420),
		Vector2(950, 420),
	])


# Main neighborhood -> overpass -> highway connection.
# It climbs north over both carriageways, loops west, then merges tangentially
# into the westbound highway. The highway itself never stops.
static func main_onramp() -> PackedVector2Array:
	var result := _sample_cubic(
		Vector2(565, 700),
		Vector2(535, 675),
		Vector2(500, 560),
		Vector2(515, 445),
		12
	)
	var second := _sample_cubic(
		Vector2(515, 445),
		Vector2(430, 350),
		Vector2(330, 541),
		Vector2(250, 541),
		16
	)
	for index in range(1, second.size()):
		result.append(second[index])
	return result


# Correct city exit: highway -> city arterial.
static func city_exit() -> PackedVector2Array:
	return _sample_cubic(
		Vector2(175, 541),
		Vector2(155, 520),
		Vector2(165, 455),
		Vector2(205, 410),
		10
	)


# Alternate highway exit that is intentionally not the city route.
static func wrong_exit() -> PackedVector2Array:
	return _sample_cubic(
		Vector2(760, 541),
		Vector2(775, 515),
		Vector2(790, 470),
		Vector2(835, 440),
		10
	)


static func westbound_lane_center(lane: int) -> float:
	return (
		WESTBOUND_HIGHWAY.position.y
		+ float(lane) * HIGHWAY_LANE_WIDTH
		+ HIGHWAY_LANE_WIDTH * 0.5
	)


static func _sample_cubic(
	start: Vector2,
	control_one: Vector2,
	control_two: Vector2,
	finish: Vector2,
	samples: int
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(samples + 1):
		var t := float(index) / float(samples)
		var inverse := 1.0 - t
		result.append(
			start * inverse * inverse * inverse
			+ control_one * 3.0 * inverse * inverse * t
			+ control_two * 3.0 * inverse * t * t
			+ finish * t * t * t
		)
	return result
