class_name DriveProfiles
extends RefCounted

# v0.9 keeps three logical profiles, but the player experiences one continuous
# road. Invisible gates trigger short connector animations between profiles.
const ORDER := [
	"neighborhood",
	"highway",
	"downtown",
]

const BASE_SPEED := 680.0
const BASE_LANE_WIDTH := 110.0
const BASE_BLOCK_SPACING := 1900.0

const PROFILES := {
	"neighborhood": {
		"name": "NEIGHBORHOOD",
		"mode": "turn",
		"lane_count": 1,
		"car_scale": 1.0,
		"speed_scale": 0.62,
		"road_scale": 1.0,
		"block_scale": 1.0,
		"stop_signs": false,
		"auto_stop_time": 0.0,
		"one_way": false,
		"grid_size": Vector2i(4, 4),
		"entry": Vector2i(0, 3),
		"exit": Vector2i(3, 0),
		"traffic_count": 0,
		"section_length": 0.0,
		"exit_lane": -1,
		"start_lane": 0,
	},
	"main_road": {
		"name": "MAIN ROAD",
		"mode": "lane",
		"lane_count": 2,
		"car_scale": 0.75,
		"speed_scale": 1.45,
		"road_scale": 0.85,
		"block_scale": 0.0,
		"stop_signs": false,
		"auto_stop_time": 0.0,
		"one_way": false,
		"grid_size": Vector2i.ZERO,
		"entry": Vector2i.ZERO,
		"exit": Vector2i.ZERO,
		"traffic_count": 4,
		"section_length": 6200.0,
		"exit_lane": -1,
		"start_lane": 1,
	},
	"highway": {
		"name": "HIGHWAY",
		"mode": "lane",
		"lane_count": 8,
		"car_scale": 0.36,
		"speed_scale": 2.05,
		"road_scale": 0.47,
		"block_scale": 0.0,
		"stop_signs": false,
		"auto_stop_time": 0.0,
		"one_way": false,
		"grid_size": Vector2i.ZERO,
		"entry": Vector2i.ZERO,
		"exit": Vector2i.ZERO,
		"traffic_count": 12,
		"section_length": 9000.0,
		"exit_lane": 7,
		"start_lane": 3,
	},
	"downtown": {
		"name": "VENUE APPROACH",
		"mode": "approach",
		"lane_count": 1,
		"car_scale": 1.65,
		"speed_scale": 0.50,
		"road_scale": 3.25,
		"block_scale": 0.0,
		"stop_signs": false,
		"auto_stop_time": 0.0,
		"one_way": false,
		"grid_size": Vector2i.ZERO,
		"entry": Vector2i.ZERO,
		"exit": Vector2i.ZERO,
		"traffic_count": 0,
		"section_length": 2800.0,
		"exit_lane": -1,
		"start_lane": 0,
	},
	"parking": {
		"name": "PARKING LOT",
		"mode": "turn",
		"lane_count": 1,
		"car_scale": 1.10,
		"speed_scale": 0.55,
		"road_scale": 0.90,
		"block_scale": 0.22,
		"stop_signs": false,
		"auto_stop_time": 0.0,
		"one_way": false,
		"grid_size": Vector2i(3, 3),
		"entry": Vector2i(0, 2),
		"exit": Vector2i(2, 0),
		"traffic_count": 0,
		"section_length": 0.0,
		"exit_lane": -1,
		"start_lane": 0,
	},
}


static func get_profile(profile_id: String) -> Dictionary:
	return PROFILES.get(profile_id, {})
