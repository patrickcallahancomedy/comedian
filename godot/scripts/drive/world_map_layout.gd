class_name ComedianWorldMapLayout
extends RefCounted

## Static geography only.
## This map is one fixed-scale physical world. No gameplay state lives here.

const WORLD_SIZE := Vector2(1200.0, 1500.0)

const LOCAL_ROAD_WIDTH := 20.0
const ARTERIAL_ROAD_WIDTH := 28.0
const RAMP_ROAD_WIDTH := 14.0
const HIGHWAY_LANES := 4
const HIGHWAY_LANE_WIDTH := 10.0
const HIGHWAY_CARRIAGEWAY_WIDTH := 40.0
const HIGHWAY_MEDIAN_GAP := 34.0

const HOME_RECT := Rect2(955, 1265, 46, 34)
const VENUE_RECT := Rect2(125, 235, 80, 72)
const VENUE_PARKING_RECT := Rect2(105, 310, 120, 62)


# ----------------------------
# Highway backbone
# ----------------------------

static func westbound_highway() -> PackedVector2Array:
	return _sample_cubic(
		Vector2(-80, 700),
		Vector2(300, 710),
		Vector2(720, 645),
		Vector2(1280, 650),
		54
	)


static func eastbound_highway() -> PackedVector2Array:
	return _offset_polyline(
		westbound_highway(),
		HIGHWAY_CARRIAGEWAY_WIDTH + HIGHWAY_MEDIAN_GAP
	)


# ----------------------------
# Neighborhood
# ----------------------------

static func neighborhood_roads() -> Array:
	return [
		# Outer residential loop.
		PackedVector2Array([
			Vector2(765, 1015),
			Vector2(915, 955),
			Vector2(1080, 1005),
			Vector2(1120, 1160),
			Vector2(1080, 1350),
			Vector2(900, 1400),
			Vector2(745, 1325),
			Vector2(700, 1160),
			Vector2(765, 1015),
		]),
		# Interior streets.
		PackedVector2Array([
			Vector2(780, 1115),
			Vector2(1035, 1085),
		]),
		PackedVector2Array([
			Vector2(790, 1235),
			Vector2(1050, 1210),
		]),
		PackedVector2Array([
			Vector2(865, 990),
			Vector2(865, 1370),
		]),
		PackedVector2Array([
			Vector2(995, 985),
			Vector2(995, 1365),
		]),
	]


static func neighborhood_collector() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(765, 1015),
		Vector2(720, 950),
		Vector2(685, 865),
		Vector2(670, 790),
	])


# ----------------------------
# Overpass / service interchange
# ----------------------------

# This is the physical road Darren follows out of the neighborhood. It crosses
# both freeway carriageways as an elevated arterial before the on-ramp branches.
static func overpass_arterial() -> PackedVector2Array:
	return _sample_cubic(
		Vector2(670, 790),
		Vector2(650, 735),
		Vector2(655, 610),
		Vector2(690, 520),
		18
	)


# A north-side continuation means missing the ramp can become a real wrong
# turn later instead of an invisible boundary.
static func north_surface_road() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(690, 520),
		Vector2(740, 470),
		Vector2(850, 450),
		Vector2(985, 470),
	])


# Loop-style on-ramp inspired by the user's Cities: Skylines reference.
# It leaves the overpass, curls west, straightens alongside the westbound
# freeway, then converges into the rightmost freeway lane.
static func main_onramp() -> PackedVector2Array:
	var result := _sample_cubic(
		Vector2(690, 520),
		Vector2(615, 485),
		Vector2(500, 500),
		Vector2(465, 585),
		14
	)
	_append_curve(
		result,
		_sample_cubic(
			Vector2(465, 585),
			Vector2(430, 640),
			Vector2(505, 675),
			Vector2(585, 675),
			12
		)
	)
	_append_curve(
		result,
		_sample_cubic(
			Vector2(585, 675),
			Vector2(650, 675),
			Vector2(705, 665),
			Vector2(760, 660),
			12
		)
	)
	return result


# ----------------------------
# City
# ----------------------------

static func city_roads() -> Array:
	return [
		# Main city arterial from the freeway exit.
		PackedVector2Array([
			Vector2(300, 590),
			Vector2(285, 510),
			Vector2(270, 415),
			Vector2(245, 325),
			Vector2(220, 235),
		]),
		# Organic downtown / neighborhood network.
		PackedVector2Array([
			Vector2(90, 190),
			Vector2(220, 190),
			Vector2(365, 205),
			Vector2(475, 250),
		]),
		PackedVector2Array([
			Vector2(75, 315),
			Vector2(210, 315),
			Vector2(355, 330),
			Vector2(465, 375),
		]),
		PackedVector2Array([
			Vector2(95, 440),
			Vector2(245, 430),
			Vector2(385, 455),
		]),
		PackedVector2Array([
			Vector2(115, 150),
			Vector2(105, 455),
		]),
		PackedVector2Array([
			Vector2(225, 165),
			Vector2(220, 450),
		]),
		PackedVector2Array([
			Vector2(350, 205),
			Vector2(345, 455),
		]),
	]


# Proper deceleration-lane style exit: first runs beside the freeway, then
# peels north into the city arterial.
static func city_exit() -> PackedVector2Array:
	var result := _sample_cubic(
		Vector2(520, 682),
		Vector2(470, 682),
		Vector2(420, 682),
		Vector2(380, 670),
		10
	)
	_append_curve(
		result,
		_sample_cubic(
			Vector2(380, 670),
			Vector2(340, 655),
			Vector2(310, 625),
			Vector2(300, 590),
			10
		)
	)
	return result


# A second real exit goes to a roadside / industrial area. Later, taking this
# is simply being on the wrong road rather than triggering a fake failure.
static func wrong_exit() -> PackedVector2Array:
	var result := _sample_cubic(
		Vector2(970, 650),
		Vector2(1015, 648),
		Vector2(1055, 640),
		Vector2(1080, 610),
		8
	)
	_append_curve(
		result,
		_sample_cubic(
			Vector2(1080, 610),
			Vector2(1105, 575),
			Vector2(1110, 520),
			Vector2(1085, 485),
			8
		)
	)
	return result


static func wrong_exit_road() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(1085, 485),
		Vector2(1035, 450),
		Vector2(970, 445),
		Vector2(915, 470),
	])


# ----------------------------
# Helpers
# ----------------------------

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


static func _append_curve(
	target: PackedVector2Array,
	additional: PackedVector2Array
) -> void:
	for index in range(1, additional.size()):
		target.append(additional[index])


static func _offset_polyline(
	points: PackedVector2Array,
	offset: float
) -> PackedVector2Array:
	var result := PackedVector2Array()
	if points.is_empty():
		return result

	for index in range(points.size()):
		var previous := points[maxi(0, index - 1)]
		var next := points[mini(points.size() - 1, index + 1)]
		var tangent := (next - previous).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		result.append(points[index] + normal * offset)

	return result
