class_name DriveRoadNetwork
extends RefCounted

const MAP = preload("res://scripts/drive/drive_grid_map.gd")

const ONRAMP_SAMPLE_COUNT := 18


static func neighborhood_gate_edge_point() -> Vector2:
	var center := MAP.neighborhood_cell_center(MAP.NEIGHBORHOOD_GATE)
	return Vector2(MAP.NEIGHBORHOOD_RECT.end.x, center.y)


static func highway_lane_edge_point() -> Vector2:
	var lane_center := MAP.highway_cell_center(0, MAP.HIGHWAY_ENTRY_LANE)
	return Vector2(MAP.HIGHWAY_RECT.position.x, lane_center.y)


static func highway_visual_underlay_rect() -> Rect2:
	return Rect2(
		Vector2(MAP.NEIGHBORHOOD_RECT.position.x, MAP.HIGHWAY_RECT.position.y),
		Vector2(
			MAP.HIGHWAY_RECT.position.x - MAP.NEIGHBORHOOD_RECT.position.x,
			MAP.HIGHWAY_RECT.size.y
		)
	)


static func onramp_centerline() -> PackedVector2Array:
	var start := neighborhood_gate_edge_point()
	var finish := highway_lane_edge_point()

	# Leave the neighborhood almost straight, run beside the highway, then
	# converge gently into lane 4. These control points are the single source
	# of truth for both movement and drawing.
	var control_one := start + Vector2(52.0, 0.0)
	var control_two := finish + Vector2(-58.0, 28.0)

	var points := PackedVector2Array()
	for index in range(ONRAMP_SAMPLE_COUNT + 1):
		var t := float(index) / float(ONRAMP_SAMPLE_COUNT)
		points.append(_cubic_bezier(start, control_one, control_two, finish, t))
	return points


static func _cubic_bezier(
	start: Vector2,
	control_one: Vector2,
	control_two: Vector2,
	finish: Vector2,
	t: float
) -> Vector2:
	var inverse := 1.0 - t
	return (
		start * inverse * inverse * inverse
		+ control_one * 3.0 * inverse * inverse * t
		+ control_two * 3.0 * inverse * t * t
		+ finish * t * t * t
	)
