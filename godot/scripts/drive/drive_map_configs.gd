class_name DriveMapConfigs
extends RefCounted

## DRIVE map definitions.
##
## The whole microgame uses one driving system, but the trip is broken into
## four small maps. Each map changes the road graph and driving feel without
## adding new controls.
##
## Order:
## 1. neighborhood -> 2. highway -> 3. city -> 4. parking lot


static func get_maps() -> Array[Dictionary]:
	return [
		{
			"id": "neighborhood",
			"name": "NEIGHBORHOOD",
			"generator": "grid",
			"grid_size": 5,
			"roads_to_remove": 16,
			"start": Vector2i(0, 4),
			"destination": Vector2i(4, 0),
			"road_type": "neighborhood",
			"speed_limit": 25,
			"block_min": 2,
			"block_max": 4,
			"one_way_count": 0,
		},
		{
			"id": "highway",
			"name": "HIGHWAY",
			"generator": "highway",
			"grid_size": 5,
			"roads_to_remove": 0,
			"start": Vector2i(2, 4),
			"destination": Vector2i(2, 0),
			"road_type": "highway",
			"speed_limit": 65,
			"block_min": 3,
			"block_max": 5,
			"one_way_count": 0,
		},
		{
			"id": "city",
			"name": "CITY",
			"generator": "grid",
			"grid_size": 5,
			"roads_to_remove": 0,
			"start": Vector2i(0, 4),
			"destination": Vector2i(4, 0),
			"road_type": "city",
			"speed_limit": 30,
			"block_min": 1,
			"block_max": 2,
			"one_way_count": 10,
		},
		{
			"id": "parking",
			"name": "PARKING LOT",
			"generator": "parking",
			"grid_size": 5,
			"roads_to_remove": 0,
			"start": Vector2i(2, 4),
			"destination": Vector2i(4, 1),
			"road_type": "parking",
			"speed_limit": 10,
			"block_min": 1,
			"block_max": 1,
			"one_way_count": 0,
		},
	]
