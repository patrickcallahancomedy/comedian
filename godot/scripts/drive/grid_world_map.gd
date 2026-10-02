extends Control

signal map_generated

const GENERATOR = preload("res://scripts/drive/grid_world_generator.gd")

const PAGE_BG := Color(0.055, 0.06, 0.065)
const WORLD_BG := Color(0.29, 0.39, 0.22)
const GRID_MINOR := Color(1.0, 1.0, 1.0, 0.035)
const GRID_MAJOR := Color(1.0, 1.0, 1.0, 0.08)

const ROAD_COLOR := Color(0.115, 0.125, 0.14)
const CONNECTOR_COLOR := Color(0.10, 0.34, 0.92)
const RAMP_COLOR := Color(0.90, 0.16, 0.78)
const ON_RAMP_COLOR := Color(0.15, 0.78, 0.24)
const HIGHWAY_COLOR := Color(0.84, 0.12, 0.10)

const HOME_COLOR := Color(0.18, 0.52, 0.98)
const VENUE_COLOR := Color(0.84, 0.39, 0.19)
const VENUE_FILL := Color(0.47, 0.20, 0.11, 0.88)

const TOP_MARGIN := 64.0
const SIDE_MARGIN := 14.0
const BOTTOM_MARGIN := 92.0
const VISIBLE_NEIGHBORHOOD_BLOCKS := 2.0
const ROAD_BLOCK_LENGTH := 20
const ROAD_BLOCK_WIDTH := 10
const DRIVE_VISIBLE_WORLD_WIDTH := 13.333333
const DRIVE_ROTATION_SMOOTH_SPEED := 4.5
const LEGACY_LOCAL_ROAD_RATIO := 13.0 / 80.0
const HIGHWAY_LANE_FILL_RATIO := 1.0

@export var world_seed: int = 0

var generator := GENERATOR.new()
var actual_seed := 0
var map_scale := 1.0
var map_origin := Vector2.ZERO
var show_whole_map := false
var zoom_map_enabled := false
var drive_camera_enabled := false
var drive_camera_world := Vector2.ZERO
var drive_camera_rotation := 0.0
var drive_camera_target_rotation := 0.0
var open_debug_tab := -1

@onready var seed_label: Label = $"../SeedLabel"
@onready var mode_label: Label = $"../ModeLabel"
@onready var debug_panel: PanelContainer = $"../DebugPanel"
@onready var drive_group: VBoxContainer = $"../DebugPanel/Content/DRIVE"
@onready var view_group: VBoxContainer = $"../DebugPanel/Content/VIEW"
@onready var map_group: VBoxContainer = $"../DebugPanel/Content/MAP"
@onready var drive_tab_button: Button = $"../DebugBar/Tabs/DriveTabButton"
@onready var view_tab_button: Button = $"../DebugBar/Tabs/ViewTabButton"
@onready var map_tab_button: Button = $"../DebugBar/Tabs/MapTabButton"
@onready var seed_input: LineEdit = $"../DebugPanel/Content/MAP/SeedInput"
@onready var load_seed_button: Button = $"../DebugPanel/Content/MAP/LoadSeedButton"
@onready var new_map_button: Button = $"../DebugPanel/Content/MAP/NewMapButton"
@onready var drive_view_button: Button = $"../DebugPanel/Content/VIEW/DriveViewButton"
@onready var whole_map_button: Button = $"../DebugPanel/Content/VIEW/WholeMapButton"
@onready var zoom_map_button: Button = $"../DebugPanel/Content/VIEW/ZoomMapButton"


func _ready() -> void:
	drive_tab_button.pressed.connect(_toggle_drive_tab)
	view_tab_button.pressed.connect(_toggle_view_tab)
	map_tab_button.pressed.connect(_toggle_map_tab)
	load_seed_button.pressed.connect(_load_seed)
	seed_input.text_submitted.connect(_load_seed_from_text)
	new_map_button.pressed.connect(_new_map)
	drive_view_button.pressed.connect(_show_drive_view)
	whole_map_button.pressed.connect(_show_whole_map)
	zoom_map_button.pressed.connect(_show_zoom_map)
	resized.connect(_refresh_layout)
	_generate()
	call_deferred("_refresh_layout")



func _toggle_drive_tab() -> void:
	_toggle_debug_tab(0)


func _toggle_view_tab() -> void:
	_toggle_debug_tab(1)


func _toggle_map_tab() -> void:
	_toggle_debug_tab(2)


func _toggle_debug_tab(tab_index: int) -> void:
	if open_debug_tab == tab_index and debug_panel.visible:
		debug_panel.visible = false
		open_debug_tab = -1
		return

	open_debug_tab = tab_index
	debug_panel.visible = true
	drive_group.visible = tab_index == 0
	view_group.visible = tab_index == 1
	map_group.visible = tab_index == 2


func _load_seed() -> void:
	_load_seed_from_text(seed_input.text)


func _load_seed_from_text(value: String) -> void:
	var cleaned := value.strip_edges()
	if not cleaned.is_valid_int():
		seed_input.text = str(actual_seed)
		seed_input.select_all()
		return
	world_seed = int(cleaned)
	_generate()


func _new_map() -> void:
	world_seed = 0
	_generate()


func _show_drive_view() -> void:
	show_whole_map = false
	zoom_map_enabled = false
	drive_camera_enabled = true
	queue_redraw()


func _show_whole_map() -> void:
	show_whole_world()


func _show_zoom_map() -> void:
	show_whole_map = false
	zoom_map_enabled = true
	drive_camera_enabled = true
	queue_redraw()


func _generate() -> void:
	actual_seed = world_seed

	if actual_seed == 0:
		actual_seed = (
			int(Time.get_unix_time_from_system())
			^ int(Time.get_ticks_msec())
		)

	generator.generate(actual_seed)

	seed_label.text = "SEED %d" % actual_seed
	seed_input.text = str(actual_seed)
	mode_label.text = (
		"HIGHWAY CORRIDOR"
		if generator.uses_highway
		else "SURFACE CONNECTION"
	)

	queue_redraw()
	map_generated.emit()


func _process(delta: float) -> void:
	if not drive_camera_enabled:
		return

	var blend := 1.0 - exp(-DRIVE_ROTATION_SMOOTH_SPEED * delta)
	drive_camera_rotation = lerp_angle(
		drive_camera_rotation,
		drive_camera_target_rotation,
		blend
	)
	queue_redraw()


func show_whole_world() -> void:
	zoom_map_enabled = false
	show_whole_map = true
	drive_camera_enabled = true
	queue_redraw()


func set_drive_camera(
	world_position: Vector2,
	forward_direction: Vector2
) -> void:
	var was_enabled := drive_camera_enabled
	drive_camera_enabled = true
	drive_camera_world = world_position

	var direction := forward_direction.normalized()
	if direction.length_squared() <= 0.0001:
		direction = Vector2.UP

	drive_camera_target_rotation = direction.angle_to(Vector2.UP)
	if not was_enabled:
		drive_camera_rotation = drive_camera_target_rotation
	queue_redraw()


func drive_camera_screen_position() -> Vector2:
	var available_height := maxf(
		1.0,
		size.y - TOP_MARGIN - BOTTOM_MARGIN
	)
	return Vector2(
		size.x * 0.5,
		TOP_MARGIN + available_height * 0.58
	)


func world_to_screen(world_point: Vector2) -> Vector2:
	# Debug/playback layers may ask for coordinates before this Control has
	# received its next draw callback after a view change.
	_update_transform()

	if drive_camera_enabled:
		var local := (
			(world_point - drive_camera_world) * map_scale
		).rotated(drive_camera_rotation)
		return drive_camera_screen_position() + local

	return map_origin + world_point * map_scale


func _refresh_layout() -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAGE_BG, true)
	_update_transform()

	if drive_camera_enabled:
		var world_size := float(generator.GRID_SIZE)
		var world_polygon := PackedVector2Array([
			_world_to_screen(Vector2(0.0, 0.0)),
			_world_to_screen(Vector2(world_size, 0.0)),
			_world_to_screen(Vector2(world_size, world_size)),
			_world_to_screen(Vector2(0.0, world_size)),
		])
		draw_colored_polygon(world_polygon, WORLD_BG)
	else:
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

	if drive_camera_enabled:
		# All play views share the same fixed-car rotating camera.
		# Only the visible world width changes between view buttons.
		if show_whole_map:
			map_scale = minf(
				available_width,
				available_height
			) / float(generator.GRID_SIZE)
		elif zoom_map_enabled:
			var visible_world_width := (
				float(generator.NEIGHBORHOOD_SPACING)
				* VISIBLE_NEIGHBORHOOD_BLOCKS
			)
			map_scale = available_width / visible_world_width
		else:
			map_scale = available_width / DRIVE_VISIBLE_WORLD_WIDTH
		return

	# Static fallback before the debug car initializes.
	var visible_world_width := DRIVE_VISIBLE_WORLD_WIDTH
	map_scale = available_width / visible_world_width
	var viewport_center := Vector2(
		size.x * 0.5,
		TOP_MARGIN + available_height * 0.5
	)
	var home_world := Vector2(
		generator.nodes[generator.home_node]
	)
	map_origin = viewport_center - home_world * map_scale


func _draw_grid() -> void:
	# The grid is presentation only. Keep logical road coordinates unchanged,
	# but make each visible road block twice as long as it is wide.
	var highway_horizontal := _highway_is_horizontal()
	var x_step := ROAD_BLOCK_LENGTH if highway_horizontal else ROAD_BLOCK_WIDTH
	var y_step := ROAD_BLOCK_WIDTH if highway_horizontal else ROAD_BLOCK_LENGTH

	for x in range(0, generator.GRID_SIZE + 1, x_step):
		var major := x % (x_step * 5) == 0
		var color := GRID_MAJOR if major else GRID_MINOR
		var width := 1.0 if major else 0.6
		draw_line(
			_world_to_screen(Vector2(float(x), 0.0)),
			_world_to_screen(
				Vector2(float(x), float(generator.GRID_SIZE))
			),
			color,
			width
		)

	for y in range(0, generator.GRID_SIZE + 1, y_step):
		var major := y % (y_step * 5) == 0
		var color := GRID_MAJOR if major else GRID_MINOR
		var width := 1.0 if major else 0.6
		draw_line(
			_world_to_screen(Vector2(0.0, float(y))),
			_world_to_screen(
				Vector2(float(generator.GRID_SIZE), float(y))
			),
			color,
			width
		)


func _highway_is_horizontal() -> bool:
	if generator.highway_nodes.size() != 2:
		return true
	var a: Vector2i = generator.nodes[int(generator.highway_nodes[0])]
	var b: Vector2i = generator.nodes[int(generator.highway_nodes[1])]
	return a.y == b.y


func _draw_roads() -> void:
	for a in range(generator.nodes.size()):
		for b_value in generator.adjacency[a]:
			var b: int = int(b_value)
			if b <= a:
				continue

			var road_class := generator.edge_class(a, b)
			# Graph-only highway/ramp merge links are intentionally invisible.
			if road_class < 0:
				continue
			var width := (
				float(generator.NEIGHBORHOOD_SPACING)
				* LEGACY_LOCAL_ROAD_RATIO
			)
			var color := ROAD_COLOR

			match road_class:
				generator.RoadClass.CITY:
					width = (
						float(generator.NEIGHBORHOOD_SPACING)
						* LEGACY_LOCAL_ROAD_RATIO
					)
				generator.RoadClass.CONNECTOR:
					width = (
						float(generator.CONNECTOR_STEP)
						* LEGACY_LOCAL_ROAD_RATIO
					)
					color = CONNECTOR_COLOR
				generator.RoadClass.RAMP:
					width = (
						float(generator.HIGHWAY_LANE_SPACING)
						* HIGHWAY_LANE_FILL_RATIO
					)
					color = (
						ON_RAMP_COLOR
						if generator.is_on_ramp_edge(a, b)
						else RAMP_COLOR
					)
				generator.RoadClass.HIGHWAY:
					_draw_three_lane_highway(
						Vector2(generator.nodes[a]),
						Vector2(generator.nodes[b])
					)
					continue

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
		if _visible_degree(node_id) < 3:
			continue

		var road_class := _strongest_node_class(node_id)
		var radius := (
			float(generator.NEIGHBORHOOD_SPACING)
			* LEGACY_LOCAL_ROAD_RATIO
			* 0.5
		)
		var color := ROAD_COLOR

		match road_class:
			generator.RoadClass.CITY:
				radius = (
					float(generator.NEIGHBORHOOD_SPACING)
					* LEGACY_LOCAL_ROAD_RATIO
					* 0.5
				)
			generator.RoadClass.CONNECTOR:
				radius = (
					float(generator.CONNECTOR_STEP)
					* LEGACY_LOCAL_ROAD_RATIO
					* 0.5
				)
				color = CONNECTOR_COLOR
			generator.RoadClass.RAMP:
				radius = (
					float(generator.HIGHWAY_LANE_SPACING)
					* HIGHWAY_LANE_FILL_RATIO
					* 0.5
				)
				color = RAMP_COLOR
			generator.RoadClass.HIGHWAY:
				radius = (
					float(generator.HIGHWAY_LANE_SPACING)
					* HIGHWAY_LANE_FILL_RATIO
					* 0.5
				)
				color = HIGHWAY_COLOR

		draw_circle(
			_world_to_screen(
				Vector2(generator.nodes[node_id])
			),
			maxf(1.0, radius * map_scale),
			color
		)

	_draw_auxiliary_merge_nodes()


func _draw_three_lane_highway(start: Vector2, finish: Vector2) -> void:
	# Restore the approved pre-2-lane highway: three touching red lanes.
	# Pink/green auxiliary lanes sit one more lane-width outside.
	var lane_spacing := float(generator.HIGHWAY_LANE_SPACING)
	var perpendicular := Vector2.ZERO
	if is_equal_approx(start.y, finish.y):
		perpendicular = Vector2(0.0, 1.0)
	else:
		perpendicular = Vector2(1.0, 0.0)

	for lane_offset in [-lane_spacing, 0.0, lane_spacing]:
		var offset: Vector2 = perpendicular * float(lane_offset)
		draw_line(
			_world_to_screen(start + offset),
			_world_to_screen(finish + offset),
			HIGHWAY_COLOR,
			maxf(
				1.0,
				float(generator.HIGHWAY_LANE_SPACING)
				* HIGHWAY_LANE_FILL_RATIO
				* map_scale
			),
			true
		)


func _draw_auxiliary_merge_nodes() -> void:
	for node_value in generator.auxiliary_merge_nodes:
		var node_id: int = int(node_value)
		draw_circle(
			_world_to_screen(Vector2(generator.nodes[node_id])),
			maxf(
				1.0,
				float(generator.HIGHWAY_LANE_SPACING)
				* HIGHWAY_LANE_FILL_RATIO
				* 0.5
				* map_scale
			),
			HIGHWAY_COLOR
		)


func _visible_degree(node_id: int) -> int:
	var degree := 0
	for neighbor_value in generator.adjacency[node_id]:
		var neighbor: int = int(neighbor_value)
		if generator.edge_class(node_id, neighbor) >= 0:
			degree += 1
	return degree


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
	var position := Vector2(generator.venue_block.position) + Vector2.ONE * inset
	var block_size := (
		Vector2(generator.venue_block.size)
		- Vector2.ONE * inset * 2.0
	)

	if drive_camera_enabled:
		var corners := PackedVector2Array([
			_world_to_screen(position),
			_world_to_screen(position + Vector2(block_size.x, 0.0)),
			_world_to_screen(position + block_size),
			_world_to_screen(position + Vector2(0.0, block_size.y)),
		])
		draw_colored_polygon(corners, VENUE_FILL)
		return

	var rect := Rect2(
		_world_to_screen(position),
		block_size * map_scale
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
	return world_to_screen(world_point)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return

	if event.keycode == KEY_R:
		_new_map()
