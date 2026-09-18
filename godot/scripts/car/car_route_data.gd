class_name CarRouteData
extends RefCounted

## One tiny authored town for DRIVE.
##
## Keep this boring and readable. World coordinates are only layout.
## The route is the blue path. Each decision has one short wrong-turn loop that
## returns to the same intersection, then Darren continues toward the mic.

const ROUTE := PackedVector2Array([
	Vector2(0, 800),
	Vector2(0, 650),
	Vector2(170, 650),
	Vector2(170, 500),
	Vector2(340, 500),
	Vector2(340, 350),
	Vector2(170, 350),
	Vector2(170, 200),
	Vector2(340, 200),
	Vector2(340, 50),
])

# 1 = RIGHT, -1 = LEFT at each route intersection.
const TURNS := [1, -1, 1, -1, -1, 1, 1, -1]

# Wrong-turn loops. Each starts/ends on the matching route intersection.
const DETOURS := [
	PackedVector2Array([
		Vector2(0, 650),
		Vector2(-120, 650),
		Vector2(-120, 720),
		Vector2(0, 720),
		Vector2(0, 650),
	]),
	PackedVector2Array([
		Vector2(170, 650),
		Vector2(290, 650),
		Vector2(290, 735),
		Vector2(170, 735),
		Vector2(170, 650),
	]),
	PackedVector2Array([
		Vector2(170, 500),
		Vector2(50, 500),
		Vector2(50, 430),
		Vector2(170, 430),
		Vector2(170, 500),
	]),
	PackedVector2Array([
		Vector2(340, 500),
		Vector2(460, 500),
		Vector2(460, 430),
		Vector2(340, 430),
		Vector2(340, 500),
	]),
	PackedVector2Array([
		Vector2(340, 350),
		Vector2(460, 350),
		Vector2(460, 285),
		Vector2(340, 285),
		Vector2(340, 350),
	]),
	PackedVector2Array([
		Vector2(170, 350),
		Vector2(50, 350),
		Vector2(50, 280),
		Vector2(170, 280),
		Vector2(170, 350),
	]),
	PackedVector2Array([
		Vector2(170, 200),
		Vector2(50, 200),
		Vector2(50, 130),
		Vector2(170, 130),
		Vector2(170, 200),
	]),
	PackedVector2Array([
		Vector2(340, 200),
		Vector2(460, 200),
		Vector2(460, 120),
		Vector2(340, 120),
		Vector2(340, 200),
	]),
]

# A few extra streets that are not part of the route. They make the town read
# like a maze instead of a single blue polyline.
const EXTRA_STREETS := [
	PackedVector2Array([Vector2(-120, 560), Vector2(80, 560)]),
	PackedVector2Array([Vector2(70, 735), Vector2(70, 580)]),
	PackedVector2Array([Vector2(290, 735), Vector2(430, 735)]),
	PackedVector2Array([Vector2(50, 430), Vector2(-90, 430)]),
	PackedVector2Array([Vector2(460, 430), Vector2(560, 430)]),
	PackedVector2Array([Vector2(460, 285), Vector2(560, 285)]),
	PackedVector2Array([Vector2(50, 280), Vector2(-80, 280)]),
	PackedVector2Array([Vector2(50, 130), Vector2(-60, 130)]),
	PackedVector2Array([Vector2(460, 120), Vector2(560, 120)]),
]

const MAP_MIN := Vector2(-140, 20)
const MAP_MAX := Vector2(580, 760)
