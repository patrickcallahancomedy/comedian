extends Control

const GENERATOR = preload("res://scripts/drive/grid_world_generator.gd")

const PAGE_BG := Color(0.055, 0.06, 0.065)
const WORLD_BG := Color(0.29, 0.39, 0.22)
const GRID_MINOR := Color(1.0, 1.0, 1.0, 0.035)
const GRID_MAJOR := Color(1.0, 1.0, 1.0, 0.08)

const ROAD_COLOR := Color(0.115, 0.125, 0.14)
const CONNECTOR_COLOR := Color(0.13, 0.14, 0.155)
const HIGHWAY_COLOR := Color(0.105, 0.115, 0.13)

const HOME_COLOR := Color(0.18, 0.52, 0.98)
const VENUE_COLOR := Color(0.84, 0.39, 0.19)
const VENUE_FILL := Color(0.47, 0.20, 0.11, 0.88)

const TOP_MARGIN := 64.0
const SIDE_MARGIN := 14.0
const BOTTOM_MARGIN := 92.0

@export var world_seed: int = 0

var generator := GENERATOR.new()
var actual_seed := 0
var map_scale := 1.0
var map_origin := Vector2.ZERO

@onready var seed_label: Label = $"../SeedLabel"
@onready var mode_label: Label = $"../ModeLabel"
@onready var new_map_button: Button = $"../NewMapButton"


func _ready() -> void:
	new_map_button.pressed.connect(_new_map)
	resized.connect(_refresh_layout)
	_generate()
	call_deferred("_refresh_layout")


func _new_map() -> void:
	world_seed = 0
	_generate()


func _generate() -> void:
	actual_seed = world_seed

	if actual_seed == 0:
		actual_seed = (
			int(Time.get_unix_time_from_system())
			^ int(Time.get_ticks_msec())
		)

	generator.generate(actual_seed)

	seed_label.text = "SEED %d" % actual_seed
	mode_label.text = (
		"HIGHWAY CORRIDOR"
		if generator.uses_highway
		else "SURFACE CONNECTION"
	)

	queue_redraw()


func _refresh_layout() -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAGE_BG, true)
	_update_transform()

	var world_screen := Rect2(
		map_origin,
		Vector2.ONE * float(generator.GRID_SIZE) * map_scale
	)
	draw_rect(world_screen, WORLD_BG, true)

	_draw_grid()
	_draw_roads()
	_draw_venue_block()
	_draw_point_marker(
		Vector2(generator.nodes[generator.home_node]),
		HOME_COLOR,
		"A"
	)
	_draw_point_marker(
		Vector2(generator.venue_block.get_center()),
		VENUE_COLOR,
		"B"
	)


func _update_transform() -> void:
	var available_width := maxf(
		1.0,
		size.x - SIDE_MARGIN * 2.0
	)
	var available_height := maxf(
		1.0,
		size.y - TOP_MARGIN - BOTTOM_MARGIN
	)
	var available := minf(
		available_width,
		available_height
	)

	map_scale = available / float(generator.GRID_SIZE)

	var map_size := Vector2.ONE * (
		float(generator.GRID_SIZE) * map_scale
	)

	map_origin = Vector2(
		(size.x - map_size.x) * 0.5,
		TOP_MARGIN + (
			available_height - map_size.y
		) * 0.5
	)


func _draw_grid() -> void:
	for coordinate in range(0, generator.GRID_SIZE + 1, 10):
		var color := (
			GRID_MAJOR
			if coordinate % 50 == 0
			else GRID_MINOR
		)
		var width := 1.0 if coordinate % 50 == 0 else 0.6

		var horizontal_start := _world_to_screen(
			Vector2(0.0, float(coordinate))
		)
		var horizontal_end := _world_to_screen(
			Vector2(
				float(generator.GRID_SIZE),
				float(coordinate)
			)
		)

		var vertical_start := _world_to_screen(
			Vector2(float(coordinate), 0.0)
		)
		var vertical_end := _world_to_screen(
			Vector2(
				float(coordinate),
				float(generator.GRID_SIZE)
			)
		)

		draw_line(
			horizontal_start,
			horizontal_end,
			color,
			width
		)
		draw_line(
			vertical_start,
			vertical_end,
			color,
			width
		)


func _draw_roads() -> void:
	for a in range(generator.nodes.size()):
		for b_value in generator.adjacency[a]:
			var b: int = int(b_value)
			if b <= a:
				continue

			var road_class := generator.edge_class(a, b)
			var width := 2.4
			var color := ROAD_COLOR

			match road_class:
				generator.RoadClass.CITY:
					width = 3.0
				generator.RoadClass.CONNECTOR:
					width = 3.4
					color = CONNECTOR_COLOR
				generator.RoadClass.HIGHWAY:
					width = 5.2
					color = HIGHWAY_COLOR

			draw_line(
				_world_to_screen(
					Vector2(generator.nodes[a])
				),
				_world_to_screen(
					Vector2(generator.nodes[b])
				),
				color,
				maxf(1.0, width * map_scale),
				true
			)

	for node_id in range(generator.nodes.size()):
		if generator.adjacency[node_id].size() < 3:
			continue

		var road_class := _strongest_node_class(node_id)
		var radius := 1.8
		var color := ROAD_COLOR

		match road_class:
			generator.RoadClass.CITY:
				radius = 2.2
			generator.RoadClass.CONNECTOR:
				radius = 2.4
				color = CONNECTOR_COLOR
			generator.RoadClass.HIGHWAY:
				radius = 3.0
				color = HIGHWAY_COLOR

		draw_circle(
			_world_to_screen(
				Vector2(generator.nodes[node_id])
			),
			maxf(1.0, radius * map_scale),
			color
		)


func _strongest_node_class(node_id: int) -> int:
	var strongest := generator.RoadClass.NEIGHBORHOOD

	for neighbor_value in generator.adjacency[node_id]:
		var neighbor: int = int(neighbor_value)
		strongest = maxi(
			strongest,
			generator.edge_class(node_id, neighbor)
		)

	return strongest


func _draw_venue_block() -> void:
	var inset := 2.0
	var rect := Rect2(
		_world_to_screen(
			Vector2(generator.venue_block.position)
			+ Vector2.ONE * inset
		),
		(
			Vector2(generator.venue_block.size)
			- Vector2.ONE * inset * 2.0
		) * map_scale
	)

	draw_rect(rect, VENUE_FILL, true)


func _draw_point_marker(
	world_point: Vector2,
	color: Color,
	label_text: String
) -> void:
	var screen := _world_to_screen(world_point)
	var radius := 5.0

	draw_circle(screen, radius, color)
	draw_circle(screen, 2.2, Color.WHITE)

	var font := get_theme_default_font()
	draw_string(
		font,
		screen + Vector2(8.0, 4.0),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		28.0,
		13,
		Color.WHITE
	)


func _world_to_screen(world_point: Vector2) -> Vector2:
	return map_origin + world_point * map_scale


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return

	if event.keycode == KEY_R:
		_new_map()
