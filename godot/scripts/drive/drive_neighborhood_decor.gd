extends Node2D

## Decorative neighborhood lots.
## Native Sprite2D nodes sit in the grassy corners between road centers.
## This layer is visual only and never changes driving logic.

const MAP = preload("res://scripts/drive/drive_grid_map.gd")
const HOUSE_ATLAS = preload("res://assets/drive/neighborhood/neighborhood_houses.png")

const HOUSE_PIXELS := 64.0
const HOUSE_WORLD_SIZE := 12.0

# Each entry is: neighborhood cell, corner offset, house atlas index.
# Offsets keep houses away from the road center where the car travels.
const HOUSE_LOTS := [
	[Vector2i(0, 0), Vector2(-10, -10), 0],
	[Vector2i(1, 0), Vector2(10, -10), 1],
	[Vector2i(2, 0), Vector2(-10, -10), 2],
	[Vector2i(3, 0), Vector2(10, -10), 3],
	[Vector2i(0, 1), Vector2(-10, 10), 2],
	[Vector2i(3, 1), Vector2(10, 10), 0],
	[Vector2i(0, 2), Vector2(-10, -10), 1],
	[Vector2i(3, 2), Vector2(10, -10), 3],
	[Vector2i(0, 3), Vector2(-10, 10), 3],
	[Vector2i(1, 3), Vector2(10, 10), 0],
	[Vector2i(2, 3), Vector2(-10, 10), 1],
	[Vector2i(3, 3), Vector2(10, 10), 2],
]


func _ready() -> void:
	_build_houses()
	_sync_to_drive_camera()


func _process(_delta: float) -> void:
	_sync_to_drive_camera()


func _build_houses() -> void:
	for index in range(HOUSE_LOTS.size()):
		var lot = HOUSE_LOTS[index]
		var cell: Vector2i = lot[0]
		var corner_offset: Vector2 = lot[1]
		var atlas_index: int = lot[2]

		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = HOUSE_ATLAS
		atlas_texture.region = Rect2(
			Vector2((atlas_index % 2) * 64, int(atlas_index / 2) * 64),
			Vector2(64, 64)
		)

		var house := Sprite2D.new()
		house.name = "House%d" % (index + 1)
		house.texture = atlas_texture
		house.position = MAP.neighborhood_cell_center(cell) + corner_offset
		house.scale = Vector2.ONE * (HOUSE_WORLD_SIZE / HOUSE_PIXELS)
		add_child(house)


func _sync_to_drive_camera() -> void:
	var drive = get_node("../CityMap")
	if drive == null or drive.player_screen_center == Vector2.ZERO:
		return

	rotation = drive.map_rotation
	scale = Vector2.ONE * drive.WORLD_ZOOM
	position = (
		drive.player_screen_center
		- (drive.visual_world_position * drive.WORLD_ZOOM).rotated(rotation)
	)
