extends Control

const PANEL_BG := Color(0.055, 0.06, 0.065, 0.96)
const WORLD_BG := Color(0.29, 0.39, 0.22)
const ROAD_COLOR := Color(0.115, 0.125, 0.14)
const CONNECTOR_COLOR := Color(0.10, 0.34, 0.92)
const RAMP_COLOR := Color(0.90, 0.16, 0.78)
const HIGHWAY_COLOR := Color(0.84, 0.12, 0.10)
const CAR_COLOR := Color(1.0, 0.92, 0.08)
const BORDER_COLOR := Color(0.85, 0.85, 0.80, 0.85)
const PADDING := 8.0

@onready var map = $"../Map"
@onready var car = $"../DebugCar"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func _process(_delta: float) -> void:
	visible = map.drive_camera_enabled
	if visible:
		queue_redraw()


func _draw() -> void:
	if not visible:
		return
	if map.generator.nodes.is_empty():
		return

	draw_rect(Rect2(Vector2.ZERO, size), PANEL_BG, true)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 2.0)

	var inner := Rect2(
		Vector2.ONE * PADDING,
		size - Vector2.ONE * PADDING * 2.0
	)
	var world_size := float(map.generator.GRID_SIZE)
	var scale := minf(
		inner.size.x / world_size,
		inner.size.y / world_size
	)
	var world_draw_size := Vector2.ONE * world_size * scale
	var origin := inner.position + (inner.size - world_draw_size) * 0.5

	draw_rect(
		Rect2(origin, world_draw_size),
		WORLD_BG,
		true
	)

	for a in range(map.generator.nodes.size()):
		for b_value in map.generator.adjacency[a]:
			var b: int = int(b_value)
			if b <= a:
				continue

			var road_class := map.generator.edge_class(a, b)
			if road_class < 0:
				continue

			var color := ROAD_COLOR
			var width := 1.0
			match road_class:
				map.generator.RoadClass.CITY:
					width = 1.2
				map.generator.RoadClass.CONNECTOR:
					color = CONNECTOR_COLOR
					width = 1.4
				map.generator.RoadClass.RAMP:
					color = RAMP_COLOR
					width = 1.6
				map.generator.RoadClass.HIGHWAY:
					color = HIGHWAY_COLOR
					width = 1.8

			draw_line(
				_to_overview(
					Vector2(map.generator.nodes[a]),
					origin,
					scale
				),
				_to_overview(
					Vector2(map.generator.nodes[b]),
					origin,
					scale
				),
				color,
				width,
				true
			)

	var home := _to_overview(
		Vector2(map.generator.nodes[map.generator.home_node]),
		origin,
		scale
	)
	var venue := _to_overview(
		Vector2(map.generator.venue_block.get_center()),
		origin,
		scale
	)
	draw_circle(home, 2.5, Color.WHITE)
	draw_circle(venue, 2.5, Color.WHITE)

	if not car.route.is_empty():
		var car_world: Vector2 = car._display_world_position()
		var car_screen := _to_overview(car_world, origin, scale)
		draw_circle(car_screen, 4.0, Color(0.02, 0.02, 0.02))
		draw_circle(car_screen, 2.8, CAR_COLOR)


func _to_overview(
	world_point: Vector2,
	origin: Vector2,
	scale: float
) -> Vector2:
	return origin + world_point * scale
