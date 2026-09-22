extends TileMapLayer

## Neighborhood road art for the driving microgame.
## The TileSet is a normal external Godot resource so the atlas is inspectable
## in the editor. This script only paints the 4x4 layer and follows the drive camera.

const MAP = preload("res://scripts/drive/drive_grid_map.gd")
const NEIGHBORHOOD_TILE_SET = preload("res://resources/drive/neighborhood_tileset.tres")
const TILE_PIXELS := 128


func _ready() -> void:
	tile_set = NEIGHBORHOOD_TILE_SET
	_paint_neighborhood()
	# TileMapLayer batches internal rendering updates. Force the initial atlas
	# and cells to be ready before the first visible frame.
	update_internals()
	_sync_to_drive_camera()


func _process(_delta: float) -> void:
	_sync_to_drive_camera()


func _paint_neighborhood() -> void:
	clear()
	for y in range(MAP.NEIGHBORHOOD_SIZE.y):
		for x in range(MAP.NEIGHBORHOOD_SIZE.x):
			set_cell(Vector2i(x, y), 0, Vector2i.ZERO, 0)


func _sync_to_drive_camera() -> void:
	var drive = get_node("../CityMap")
	if drive == null or drive.player_screen_center == Vector2.ZERO:
		return

	# The TileSet uses the source image's 128 px cell spacing. Scale that
	# spacing to one neighborhood world cell, then apply the drive camera zoom.
	var first_cell_local := map_to_local(Vector2i.ZERO)
	var first_cell_world := MAP.neighborhood_cell_center(Vector2i.ZERO)
	var target_screen: Vector2 = drive._world_to_screen(first_cell_world)
	var screen_scale: float = (
		float(MAP.NEIGHBORHOOD_CELL)
		* drive.WORLD_ZOOM
		/ float(TILE_PIXELS)
	)

	rotation = drive.map_rotation
	scale = Vector2.ONE * screen_scale
	position = target_screen - (first_cell_local * screen_scale).rotated(rotation)
