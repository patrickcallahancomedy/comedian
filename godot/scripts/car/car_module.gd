extends GameModule

## DRIVE v0.5 — one verb: drive.
##
## STATE READS:
## energy, car_condition
##
## STATE WRITES:
## energy, gas, stress, night_context
##
## HISTORY:
## drives_completed, missed_turns
##
## RESULT:
## arrival_minutes_before_signup, arrival_clock_minutes, missed_turns,
## real_drive_seconds
##
## PLAYER EXPERIENCE:
## Darren actually travels through a tiny top-down town. The whole maze sits in
## the corner. The car keeps moving. LEFT / RIGHT selects the next turn.
##
## Wrong turns physically drive a short loop before rejoining the route.
## No phone game. No relationship game. No visible stat math.

@export_category("Drive Tuning")
@export_range(70.0, 240.0, 5.0) var drive_speed: float = 125.0
@export_range(0.3, 1.5, 0.05) var title_seconds: float = 0.70

@export_category("Comedy Night Clock")
@export var departure_clock_minutes: int = 19 * 60 + 16
@export var signup_close_clock_minutes: int = 19 * 60 + 45

@onready var road: CarRoad = $Road
@onready var player_car: ColorRect = $Road/PlayerCar
@onready var minimap: CarMinimap = $HUD/GPSPanel/GPSMargin/MiniMap
@onready var left_button: Button = $Controls/LeftButton
@onready var right_button: Button = $Controls/RightButton

@onready var fatigue_overlay: Control = $FatigueOverlay
@onready var top_lid: ColorRect = $FatigueOverlay/TopLid
@onready var bottom_lid: ColorRect = $FatigueOverlay/BottomLid

@onready var title_card: Control = $TitleCard
@onready var result_panel: PanelContainer = $ResultPanel
@onready var result_time_label: Label = $ResultPanel/ResultMargin/ResultLayout/TimeLabel
@onready var result_label: Label = $ResultPanel/ResultMargin/ResultLayout/ResultLabel
@onready var continue_button: Button = $ResultPanel/ResultMargin/ResultLayout/ContinueButton

var car_world_position := CarRouteData.ROUTE[0]
var car_world_direction := Vector2.UP

# route_segment means Darren is travelling ROUTE[n] -> ROUTE[n + 1].
var route_segment: int = 0
var pending_turn: int = 0

var detour_active: bool = false
var detour_points := PackedVector2Array()
var detour_segment: int = 0

var drive_elapsed: float = 0.0
var missed_turns: int = 0
var finished: bool = false
var game_started: bool = false

var fatigue_strength: float = 0.0
var fatigue_wait_timer: float = 99.0
var fatigue_blink_elapsed: float = 0.0
var fatigue_blink_duration: float = 0.0
var fatigue_blinking: bool = false


func _ready() -> void:
	module_id = "car"
	if next_route_id.is_empty():
		next_route_id = "venue"

	fatigue_strength = clampf(float(50 - GameState.energy) / 50.0, 0.0, 1.0)
	if fatigue_strength > 0.0:
		fatigue_wait_timer = lerpf(4.8, 2.2, fatigue_strength)

	result_panel.hide()
	title_card.show()
	_set_eye_closure(0.0)

	left_button.pressed.connect(_choose_left)
	right_button.pressed.connect(_choose_right)
	continue_button.pressed.connect(_finish_and_continue)

	left_button.disabled = true
	right_button.disabled = true
	_refresh_world_visuals()

	await get_tree().create_timer(title_seconds).timeout
	if not is_inside_tree():
		return

	title_card.hide()
	game_started = true
	left_button.disabled = false
	right_button.disabled = false
	left_button.grab_focus()


func _process(delta: float) -> void:
	if finished or not game_started:
		return

	drive_elapsed += delta
	_update_fatigue(delta)
	_move_car(delta)
	_refresh_world_visuals()


func _unhandled_key_input(event: InputEvent) -> void:
	if finished or not game_started or not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if not key_event.pressed:
		return

	if key_event.keycode == KEY_LEFT or key_event.keycode == KEY_A:
		_choose_left()
	elif key_event.keycode == KEY_RIGHT or key_event.keycode == KEY_D:
		_choose_right()


# -----------------------------------------------------------------------------
# DRIVE
# -----------------------------------------------------------------------------

func _choose_left() -> void:
	_choose_turn(-1)


func _choose_right() -> void:
	_choose_turn(1)


func _choose_turn(direction: int) -> void:
	if finished or not game_started or detour_active:
		return
	if route_segment >= CarRouteData.TURNS.size():
		return

	pending_turn = direction
	_refresh_button_state()


func _refresh_button_state() -> void:
	var selected := Color(0.82, 0.78, 0.68, 1.0)
	var normal := Color(1, 1, 1, 1)

	left_button.modulate = selected if pending_turn < 0 else normal
	right_button.modulate = selected if pending_turn > 0 else normal


func _effective_speed() -> float:
	# Bad condition quietly slows the trip. No car-condition UI belongs here.
	var condition := clampf(float(GameState.car_condition) / 100.0, 0.0, 1.0)
	return drive_speed * lerpf(0.82, 1.0, condition)


func _move_car(delta: float) -> void:
	var remaining := _effective_speed() * delta

	while remaining > 0.0 and not finished:
		var target := _current_target()
		var offset := target - car_world_position
		var distance := offset.length()

		if distance <= 0.001:
			_arrive_at_target()
			continue

		car_world_direction = offset / distance

		if remaining < distance:
			car_world_position += car_world_direction * remaining
			remaining = 0.0
		else:
			car_world_position = target
			remaining -= distance
			_arrive_at_target()


func _current_target() -> Vector2:
	if detour_active:
		return detour_points[detour_segment + 1]
	return CarRouteData.ROUTE[route_segment + 1]


func _arrive_at_target() -> void:
	if detour_active:
		detour_segment += 1
		if detour_segment >= detour_points.size() - 1:
			_finish_detour()
		return

	# Final route point reached.
	if route_segment >= CarRouteData.ROUTE.size() - 2:
		_end_drive()
		return

	_resolve_turn()


func _resolve_turn() -> void:
	var required := int(CarRouteData.TURNS[route_segment])

	if pending_turn == required:
		route_segment += 1
		pending_turn = 0
		_refresh_button_state()
		return

	missed_turns += 1
	GameState.change_stress(2)
	GameState.increment_history("missed_turns")

	detour_active = true
	detour_points = CarRouteData.DETOURS[route_segment]
	detour_segment = 0
	pending_turn = 0
	_refresh_button_state()


func _finish_detour() -> void:
	detour_active = false
	detour_points = PackedVector2Array()
	detour_segment = 0

	# GPS has rerouted Darren back to the same intersection; from there he
	# continues along the intended street automatically.
	route_segment += 1


func _refresh_world_visuals() -> void:
	road.set_car_world_state(car_world_position, car_world_direction)
	minimap.set_car_world_state(car_world_position, car_world_direction)

	# Car node stays near the lower center while the world scrolls underneath.
	var anchor := Vector2(road.size.x * 0.5, road.size.y * 0.72)
	player_car.position = anchor - player_car.size * 0.5

	# The rectangle's "front" is its top edge.
	player_car.rotation = atan2(car_world_direction.y, car_world_direction.x) + PI * 0.5


# -----------------------------------------------------------------------------
# FATIGUE
# -----------------------------------------------------------------------------

func _update_fatigue(delta: float) -> void:
	if fatigue_strength <= 0.0:
		return

	if fatigue_blinking:
		fatigue_blink_elapsed += delta
		var t := clampf(fatigue_blink_elapsed / fatigue_blink_duration, 0.0, 1.0)
		_set_eye_closure(sin(t * PI))

		if t >= 1.0:
			fatigue_blinking = false
			_set_eye_closure(0.0)
			fatigue_wait_timer = randf_range(
				lerpf(4.8, 2.1, fatigue_strength),
				lerpf(6.1, 3.0, fatigue_strength)
			)
		return

	fatigue_wait_timer -= delta
	if fatigue_wait_timer <= 0.0:
		fatigue_blinking = true
		fatigue_blink_elapsed = 0.0
		fatigue_blink_duration = randf_range(
			lerpf(0.28, 0.70, fatigue_strength),
			lerpf(0.45, 1.12, fatigue_strength)
		)


func _set_eye_closure(amount: float) -> void:
	var closure := clampf(amount, 0.0, 1.0)
	var half_height := fatigue_overlay.size.y * 0.49
	var lid_height := half_height * closure

	top_lid.position = Vector2.ZERO
	top_lid.size = Vector2(fatigue_overlay.size.x, lid_height)

	bottom_lid.position = Vector2(0, fatigue_overlay.size.y - lid_height)
	bottom_lid.size = Vector2(fatigue_overlay.size.x, lid_height)


# -----------------------------------------------------------------------------
# FINISH / STATE HANDOFF
# -----------------------------------------------------------------------------

func _end_drive() -> void:
	if finished:
		return

	finished = true
	left_button.disabled = true
	right_button.disabled = true
	_set_eye_closure(0.0)

	var elapsed_game_minutes := maxi(1, ceili(drive_elapsed))
	var arrival_clock_minutes := departure_clock_minutes + elapsed_game_minutes
	var arrival_minutes_before_signup := signup_close_clock_minutes - arrival_clock_minutes

	GameState.change_energy(-2)
	GameState.change_gas(-3)
	if missed_turns == 0:
		GameState.change_stress(-1)

	GameState.night_context["arrival_minutes_before_signup"] = arrival_minutes_before_signup
	GameState.night_context["arrival_clock_minutes"] = arrival_clock_minutes
	GameState.night_context["drive_real_seconds"] = drive_elapsed
	GameState.night_context["drive_missed_turns"] = missed_turns
	GameState.increment_history("drives_completed")

	result_time_label.text = _format_clock(arrival_clock_minutes)
	result_label.text = "YOU MADE IT.\n\nYou park and sit there for about three seconds longer than necessary."
	result_panel.show()
	continue_button.grab_focus()


func _format_clock(total_minutes: int) -> String:
	var wrapped := posmod(total_minutes, 24 * 60)
	var hour_24 := wrapped / 60
	var minute := wrapped % 60
	var suffix := "AM" if hour_24 < 12 else "PM"
	var hour_12 := hour_24 % 12
	if hour_12 == 0:
		hour_12 = 12
	return "%d:%02d %s" % [hour_12, minute, suffix]


func _finish_and_continue() -> void:
	finish_module({
		"status": "drive_complete",
		"arrival_minutes_before_signup": int(GameState.night_context.get("arrival_minutes_before_signup", 0)),
		"arrival_clock_minutes": int(GameState.night_context.get("arrival_clock_minutes", 0)),
		"missed_turns": missed_turns,
		"real_drive_seconds": snappedf(drive_elapsed, 0.1),
	})
