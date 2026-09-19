class_name DriveWorldConfig
extends RefCounted

const WORLD_SIZE := 20
const MAP_SIZE := Vector2(42.0, 34.0)

const START := Vector2i(0, 16)

const REGIONS := {
	"neighborhood": {
		"name": "NEIGHBORHOOD",
		"origin": Vector2i(0, 12),
		"size": Vector2i(5, 5),
		"physical_origin": Vector2(2.0, 21.0),
		"spacing": 2.6,
		"speed_limit": 25,
		"road_type": "neighborhood",
	},
	"highway": {
		"name": "HIGHWAY",
		"origin": Vector2i(5, 8),
		"size": Vector2i(5, 5),
		"physical_origin": Vector2(15.8, 7.4),
		"spacing": 3.4,
		"speed_limit": 65,
		"road_type": "highway",
	},
	"city": {
		"name": "CITY",
		"origin": Vector2i(10, 4),
		"size": Vector2i(5, 5),
		"physical_origin": Vector2(31.4, 8.2),
		"spacing": 1.0,
		"speed_limit": 30,
		"road_type": "city",
	},
	"parking": {
		"name": "PARKING LOT",
		"origin": Vector2i(15, 4),
		"size": Vector2i(5, 5),
		"physical_origin": Vector2(37.4, 8.2),
		"spacing": 0.8,
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
