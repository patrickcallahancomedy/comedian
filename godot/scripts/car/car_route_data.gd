class_name CarRouteData
extends RefCounted

## DRIVE town layout.
##
## Main game: close top-down neighborhood view.
## Minimap: whole toy-town "rug" abstraction.
##
## Route points are ordinary 90-degree streets. Each turn can be read entirely
## from the minimap. Nothing here contains gameplay logic.

const ROUTE := PackedVector2Array([
	Vector2(0, 820),
	Vector2(0, 660),
	Vector2(170, 660),
	Vector2(170, 500),
	Vector2(350, 500),
	Vector2(350, 330),
	Vector2(170, 330),
	Vector2(170, 170),
	Vector2(350, 170),
	Vector2(350, 20),
])

# 1 = RIGHT, -1 = LEFT relative to Darren's current direction.
const TURNS := [1, -1, 1, -1, -1, 1, 1, -1]

# Wrong choices are real little neighborhood loops, already visible on the map.
# They are not spawned after the player makes a mistake.
const WRONG_LOOPS := [
	PackedVector2Array([Vector2(0, 660), Vector2(-110, 660), Vector2(-110, 740), Vector2(0, 740), Vector2(0, 660)]),
	PackedVector2Array([Vector2(170, 660), Vector2(170, 770), Vector2(90, 770), Vector2(90, 660), Vector2(170, 660)]),
	PackedVector2Array([Vector2(170, 500), Vector2(60, 500), Vector2(60, 580), Vector2(170, 580), Vector2(170, 500)]),
	PackedVector2Array([Vector2(350, 500), Vector2(350, 610), Vector2(270, 610), Vector2(270, 500), Vector2(350, 500)]),
	PackedVector2Array([Vector2(350, 330), Vector2(460, 330), Vector2(460, 410), Vector2(350, 410), Vector2(350, 330)]),
	PackedVector2Array([Vector2(170, 330), Vector2(170, 440), Vector2(250, 440), Vector2(250, 330), Vector2(170, 330)]),
	PackedVector2Array([Vector2(170, 170), Vector2(60, 170), Vector2(60, 250), Vector2(170, 250), Vector2(170, 170)]),
	PackedVector2Array([Vector2(350, 170), Vector2(350, 280), Vector2(270, 280), Vector2(270, 170), Vector2(350, 170)]),
]

# Extra roads make the town feel like a real little maze instead of one route.
# Each entry is one straight street.
const EXTRA_STREETS := [
	PackedVector2Array([Vector2(-180, 740), Vector2(130, 740)]),
	PackedVector2Array([Vector2(95, 740), Vector2(95, 580)]),
	PackedVector2Array([Vector2(245, 660), Vector2(520, 660)]),
	PackedVector2Array([Vector2(500, 660), Vector2(500, 450)]),
	PackedVector2Array([Vector2(-170, 570), Vector2(70, 570)]),
	PackedVector2Array([Vector2(-150, 410), Vector2(170, 410)]),
	PackedVector2Array([Vector2(270, 410), Vector2(540, 410)]),
	PackedVector2Array([Vector2(500, 410), Vector2(500, 250)]),
	PackedVector2Array([Vector2(-120, 250), Vector2(170, 250)]),
	PackedVector2Array([Vector2(260, 250), Vector2(530, 250)]),
	PackedVector2Array([Vector2(80, 90), Vector2(350, 90)]),
	PackedVector2Array([Vector2(80, 250), Vector2(80, 90)]),
	PackedVector2Array([Vector2(500, 250), Vector2(500, 80)]),
]

# Decoration is intentionally data, not baked into the renderer.
# type, position, optional color index.
const DECOR := [
	{"type":"house", "pos":Vector2(-95, 690), "color":0},
	{"type":"tree", "pos":Vector2(-125, 625)},
	{"type":"house", "pos":Vector2(235, 710), "color":1},
	{"type":"tree", "pos":Vector2(410, 710)},
	{"type":"pond", "pos":Vector2(405, 565)},
	{"type":"house", "pos":Vector2(-90, 500), "color":2},
	{"type":"tree", "pos":Vector2(75, 515)},
	{"type":"shop", "pos":Vector2(255, 565), "color":0},
	{"type":"tree", "pos":Vector2(455, 470)},
	{"type":"house", "pos":Vector2(-70, 340), "color":1},
	{"type":"tree", "pos":Vector2(70, 355)},
	{"type":"shop", "pos":Vector2(420, 345), "color":1},
	{"type":"tree", "pos":Vector2(255, 300)},
	{"type":"house", "pos":Vector2(-40, 190), "color":0},
	{"type":"pond", "pos":Vector2(430, 115)},
	{"type":"house", "pos":Vector2(25, 70), "color":2},
	{"type":"tree", "pos":Vector2(245, 80)},
	{"type":"club", "pos":Vector2(405, 15)},
]

const MAP_MIN := Vector2(-210, -35)
const MAP_MAX := Vector2(565, 865)
