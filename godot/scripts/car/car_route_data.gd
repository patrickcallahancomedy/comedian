class_name CarRouteData
extends RefCounted

## One tiny authored town for DRIVE.
## Main view = close neighborhood.
## Minimap = whole kid-rug town.
## No gameplay logic lives here.

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

# 1 = RIGHT, -1 = LEFT relative to Darren's current heading.
const TURNS := [1, -1, 1, -1, -1, 1, 1, -1]

# A wrong choice sends Darren around one visible little block and returns him
# to the SAME intersection. It does not advance the route. The player has to
# eventually make the correct turn.
const WRONG_LOOPS := [
	PackedVector2Array([Vector2(0, 660), Vector2(-110, 660), Vector2(-110, 760), Vector2(0, 760), Vector2(0, 660)]),
	PackedVector2Array([Vector2(170, 660), Vector2(170, 770), Vector2(70, 770), Vector2(70, 660), Vector2(170, 660)]),
	PackedVector2Array([Vector2(170, 500), Vector2(60, 500), Vector2(60, 590), Vector2(170, 590), Vector2(170, 500)]),
	PackedVector2Array([Vector2(350, 500), Vector2(350, 610), Vector2(260, 610), Vector2(260, 500), Vector2(350, 500)]),
	PackedVector2Array([Vector2(350, 330), Vector2(470, 330), Vector2(470, 420), Vector2(350, 420), Vector2(350, 330)]),
	PackedVector2Array([Vector2(170, 330), Vector2(170, 440), Vector2(260, 440), Vector2(260, 330), Vector2(170, 330)]),
	PackedVector2Array([Vector2(170, 170), Vector2(55, 170), Vector2(55, 260), Vector2(170, 260), Vector2(170, 170)]),
	PackedVector2Array([Vector2(350, 170), Vector2(350, 280), Vector2(260, 280), Vector2(260, 170), Vector2(350, 170)]),
]

# Extra streets that are not part of the blue route.
const EXTRA_STREETS := [
	PackedVector2Array([Vector2(-170, 740), Vector2(70, 740)]),
	PackedVector2Array([Vector2(70, 740), Vector2(70, 610)]),
	PackedVector2Array([Vector2(250, 660), Vector2(520, 660)]),
	PackedVector2Array([Vector2(500, 660), Vector2(500, 430)]),
	PackedVector2Array([Vector2(-160, 560), Vector2(80, 560)]),
	PackedVector2Array([Vector2(-150, 410), Vector2(170, 410)]),
	PackedVector2Array([Vector2(260, 410), Vector2(540, 410)]),
	PackedVector2Array([Vector2(500, 410), Vector2(500, 245)]),
	PackedVector2Array([Vector2(-120, 245), Vector2(170, 245)]),
	PackedVector2Array([Vector2(260, 245), Vector2(535, 245)]),
	PackedVector2Array([Vector2(70, 90), Vector2(350, 90)]),
	PackedVector2Array([Vector2(70, 245), Vector2(70, 90)]),
	PackedVector2Array([Vector2(500, 245), Vector2(500, 80)]),
]

# Reusable placeholder scenery. Patrick can replace these with real assets later.
const DECOR := [
	{"type":"house", "pos":Vector2(-95, 690), "color":0},
	{"type":"tree", "pos":Vector2(-125, 625)},
	{"type":"house", "pos":Vector2(245, 710), "color":1},
	{"type":"tree", "pos":Vector2(420, 715)},
	{"type":"pond", "pos":Vector2(410, 565)},
	{"type":"house", "pos":Vector2(-90, 495), "color":2},
	{"type":"tree", "pos":Vector2(70, 515)},
	{"type":"shop", "pos":Vector2(250, 565), "color":0},
	{"type":"tree", "pos":Vector2(455, 475)},
	{"type":"house", "pos":Vector2(-70, 340), "color":1},
	{"type":"tree", "pos":Vector2(70, 355)},
	{"type":"shop", "pos":Vector2(425, 350), "color":1},
	{"type":"tree", "pos":Vector2(255, 300)},
	{"type":"house", "pos":Vector2(-40, 190), "color":0},
	{"type":"pond", "pos":Vector2(430, 115)},
	{"type":"house", "pos":Vector2(25, 70), "color":2},
	{"type":"tree", "pos":Vector2(245, 80)},
	{"type":"club", "pos":Vector2(405, 20)},
]

const MAP_MIN := Vector2(-210, -40)
const MAP_MAX := Vector2(565, 870)
