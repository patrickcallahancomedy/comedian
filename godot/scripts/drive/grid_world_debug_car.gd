extends Control

const BASE_SPEED := 25.0
const SPEED_MULTIPLIERS := [1.0, 10.0, 100.0, 5000.0]
const SPEED_LABELS := ["1×", "10×", "100×", "MAX"]
const CAR_COLOR := Color(1.0, 0.90, 0.18)
const CAR_OUTLINE := Color(0.05, 0.05, 0.05)

var route: Array = []
var route_index := 0
var world_position := Vector2.ZERO
var running := false
var finished := false
var speed_index := 0

@onready var map = $"../Map"
@onready var run_button: Button = $"../DriveBox/Layout/RunButton"
@onready var reset_button: Button = $"../DriveBox/Layout/ResetButton"
@onready var speed_button: Button = $"../DriveBox/Layout/SpeedButton"
@onready var status_label: Label = $"../DriveBox/Layout/StatusLabel"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	run_button.pressed.connect(_run)
	reset_button.pressed.connect(_reset)
	speed_button.pressed.connect(_cycle_speed)
	map.map_generated.connect(_reset)
	call_deferred("_reset")


func _process(delta: float) -> void:
	if not running or route.size() < 2:
		return

	var remaining := BASE_SPEED * SPEED_MULTIPLIERS[speed_index] * delta

	while remaining > 0.0 and running:
		if route_index >= route.size() - 1:
			_finish()
			break

		var next_id: int = int(route[route_index + 1])
		var target := Vector2(map.generator.nodes[next_id])
		var distance := world_position.distance_to(target)

		if distance <= 0.0001:
			world_position = target
			route_index += 1
			continue

		if remaining >= distance:
			world_position = target
			remaining -= distance
			route_index += 1

			if route_index >= route.size() - 1:
				_finish()
		else:
			world_position = world_position.move_toward(target, remaining)
			remaining = 0.0

	queue_redraw()


func _draw() -> void:
	if route.is_empty():
		return

	var screen := map.world_to_screen(world_position)
	var radius := maxf(4.0, 4.5 * map.map_scale)

	draw_circle(screen, radius + 2.0, CAR_OUTLINE)
	draw_circle(screen, radius, CAR_COLOR)


func _run() -> void:
	if route.is_empty():
		_reset()

	if route.size() < 2:
		return

	map.show_whole_world()
	running = true
	finished = false
	status_label.text = "RUNNING"
	queue_redraw()


func _reset() -> void:
	running = false
	finished = false
	route_index = 0

	if map.generator.home_node < 0 or map.generator.venue_access_node < 0:
		route = []
		status_label.text = "NO ROUTE"
		queue_redraw()
		return

	route = map.generator.shortest_path(
		map.generator.home_node,
		map.generator.venue_access_node
	)

	if route.is_empty():
		status_label.text = "NO ROUTE"
		queue_redraw()
		return

	world_position = Vector2(map.generator.nodes[int(route[0])])
	status_label.text = "READY"
	queue_redraw()


func _cycle_speed() -> void:
	speed_index = (speed_index + 1) % SPEED_MULTIPLIERS.size()
	speed_button.text = "SPEED  %s" % SPEED_LABELS[speed_index]


func _finish() -> void:
	running = false
	finished = true
	status_label.text = "ARRIVED"
	queue_redraw()
