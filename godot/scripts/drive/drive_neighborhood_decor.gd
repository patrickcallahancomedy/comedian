extends Node2D

## Decorative neighborhood lots.
## Uses Sprite2D nodes over the TileMapLayer so the art remains node-based
## and easy to replace later without touching driving logic.

const MAP = preload("res://scripts/drive/drive_grid_map.gd")
const HOUSE_ATLAS = preload("res://assets/drive/neighborhood/neighborhood_houses.png")

const HOUSE_PIXELS := 64.0
const HOUSE_WORLD_SIZE := 22.0

const HOUSE_POSITIONS := [
	Vector2(50, 350),
	Vector2(130, 350),
	Vector2(90, 390),
	Vector2(50, 430),
	Vector2(130, 430),
]


func _ready() -> void:
	_build_houses()
	_sync_to_drive_camera()


func _process(_delta: float) -> void:
	_sync_to_drive_camera()


func _build_houses() -> void:
	for index in range(HOUSE_POSITIONS.size()):
		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = HOUSE_ATLAS
		atlas_texture.region = Rect2(
			Vector2((index % 2) * 64, ((index / 2) as int % 2) * 64),
			Vector2(64, 64)
		)

		var house := Sprite2D.new()
		house.name = "House%d" % (index + 1)
		house.texture = atlas_texture
		house.position = HOUSE_POSITIONS[index]
		house.scale = Vector2.ONE * (HOUSE_WORLD_SIZE / HOUSE_PIXELS)
		add_child(house)


func _sync_to_drive_camera() -> void:
	var drive = get_parent()
	if drive == null or drive.player_screen_center == Vector2.ZERO:
		return

	rotation = drive.map_rotation
	scale = Vector2.ONE * drive.WORLD_ZOOM
	position = (
		drive.player_screen_center
		- (drive.visual_world_position * drive.WORLD_ZOOM).rotated(rotation)
	)
