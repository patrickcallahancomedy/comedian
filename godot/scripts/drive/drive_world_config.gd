class_name DriveWorldConfig
extends RefCounted

## DRIVE world layout.
##
## The game uses one continuous 20x20 road world.
## Four 5x5 regions are placed inside that world and physically connected:
## neighborhood -> highway -> city -> parking lot.
##
## Main view and minimap both render this same world data.


const WORLD_SIZE := 20

const START := Vector2i(0, 16)

const REGIONS := {
	"neighborhood": {
		"name": "NEIGHBORHOOD",
		"origin": Vector2i(0, 12),
		"size": Vector2i(5, 5),
		"speed_limit": 25,
		"road_type": "neighborhood",
	},
	"highway": {
		"name": "HIGHWAY",
		"origin": Vector2i(5, 8),
		"size": Vector2i(5, 5),
		"speed_limit": 65,
		"road_type": "highway",
	},
	"city": {
		"name": "CITY",
		"origin": Vector2i(10, 4),
		"size": Vector2i(5, 5),
		"speed_limit": 30,
		"road_type": "city",
	},
	"parking": {
		"name": "PARKING LOT",
		"origin": Vector2i(15, 4),
		"size": Vector2i(5, 5),
		"speed_limit": 10,
		"road_type": "parking",
	},
}


static func get_region(region_id: String) -> Dictionary:
	return REGIONS.get(region_id, {})


static func get_region_ids() -> Array[String]:
	return [
		"neighborhood",
		"highway",
		"city",
		"parking",
	]
