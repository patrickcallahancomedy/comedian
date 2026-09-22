extends TileMapLayer

## Neighborhood art layer for the driving microgame.
## Uses a native TileMapLayer so the visual grid stays editable and can later
## accept procedural road tiles without touching the driving controller.

const MAP = preload("res://scripts/drive/drive_grid_map.gd")
const TILE_TEXTURE = preload("res://assets/drive/neighborhood/neighborhood_intersection.png")
const TILE_PIXELS := 128


func _ready() -> void:
	_build_tiles()
	_sync_to_drive_camera()


func _process(_delta: float) -> void:
	_sync_to_drive_camera()


func _build_tiles() -> void:
	var set := TileSet.new()
	set.tile_size = Vector2i(TILE_PIXELS, TILE_PIXELS)

	var atlas := TileSetAtlasSource.new()
	atlas.texture = TILE_TEXTURE
	atlas.texture_region_size = Vector2i(TILE_PIXELS, TILE_PIXELS)
	atlas.create_tile(Vector2i.ZERO)

	var source_id := set.add_source(atlas)
	tile_set = set

	for y in range(MAP.NEIGHBORHOOD_SIZE.y):
		for x in range(MAP.NEIGHBORHOOD_SIZE.x):
			set_cell(Vector2i(x, y), source_id, Vector2i.ZERO)


func _sync_to_drive_camera() -> void:
	var drive = get_node("../CityMap")
	if drive == null or drive.player_screen_center == Vector2.ZERO:
		return

	# Match the controller's existing world-to-screen transform exactly.
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
