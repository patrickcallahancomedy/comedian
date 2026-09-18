extends GameModule

## DRIVE v0.4 — one verb: drive.
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
## A tiny route through a little maze-town. The car moves forward automatically.
## The player only presses LEFT or RIGHT at intersections while glancing between
## the close road view and the whole-route minimap.
##
## No phone game. No relationship game. No visible stat math.
## Tiredness and car condition only change how DRIVE itself feels.

@export_category("Drive Tuning")
@export_range(0.8, 3.0, 0.05) var seconds_per_block: float = 1.50
@export_range(0.6, 2.5, 0.05) var final_block_seconds: float = 1.00
@export_range(0.6, 4.0, 0.05) var wrong_turn_detour_seconds: float = 1.55
@export_range(80.0, 400.0, 5.0) var road_scroll_speed: float = 210.0
@export_range(0.3, 1.5, 0.05) var title_seconds: float = 0.75

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

# 1 = right, -1 = left. The minimap is the only navigation aid.
const TURN_PATTERN := [1, -1, 1, -1, -1, 1, 1, -1]

var route_segment: int = 0
var segment_progress: float = 0.0
var player_choice: int = 0

var detour_active: bool = false
var detour_progress: float = 0.0
var detour_direction: int = 1

var drive_elapsed: float = 0.0
var road_scroll: float = 0.0
var missed_turns: int = 0
var finished: bool = false
var game_started: bool = false

var fatigue_strength: float = 0.0
var fatigue_wait_timer: float = 99.0
var fatigue_blink_elapsed: float = 0.0
var fatigue_blink_duration: float = 0.0
var fatigue_blinking: bool = false
var fatigue_drift: float = 0.0
var fatigue_drift_target: float = 0.0
var fatigue_drift_timer: float = 0.0


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

	road.set_selected_turn(0)
	road.set_detour_active(false)
	minimap.set_route_progress(route_segment, segment_progress)
	minimap.set_detour(false)

	left_button.pressed.connect(_choose_left)
	right_button.pressed.connect(_choose_right)
	continue_button.pressed.connect(_finish_and_continue)

	left_button.disabled = true
	right_button.disabled = true

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
	road_scroll += road_scroll_speed * delta
	road.set_travel_scroll(road_scroll)

	_update_fatigue(delta)
	_update_car_visual(delta)

	if detour_active:
		_update_detour(delta)
	else:
		_update_route(delta)


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
	if route_segment >= TURN_PATTERN.size():
		return

	player_choice = direction
	road.set_selected_turn(player_choice)


func _effective_block_seconds() -> float:
	var base := final_block_seconds if route_segment >= TURN_PATTERN.size() else seconds_per_block
	var condition_factor := lerpf(1.20, 1.0, float(GameState.car_condition) / 100.0)
	return maxf(0.45, base * condition_factor)


func _update_route(delta: float) -> void:
	segment_progress += delta / _effective_block_seconds()
	segment_progress = minf(segment_progress, 1.0)

	road.set_approach_progress(segment_progress)
	minimap.set_route_progress(route_segment, segment_progress)

	if segment_progress < 1.0:
		return

	if route_segment >= TURN_PATTERN.size():
		_end_drive()
		return

	_resolve_intersection()


func _resolve_intersection() -> void:
	var required_turn := int(TURN_PATTERN[route_segment])

	if player_choice == required_turn:
		_advance_to_next_block()
		return

	missed_turns += 1
	GameState.change_stress(2)
	GameState.increment_history("missed_turns")

	detour_active = true
	detour_progress = 0.0
	detour_direction = player_choice if player_choice != 0 else -required_turn
	road.set_detour_active(true)
	road.set_selected_turn(0)
	minimap.set_detour(true, detour_direction, detour_progress)


func _update_detour(delta: float) -> void:
	detour_progress += delta / maxf(0.2, wrong_turn_detour_seconds)
	detour_progress = minf(detour_progress, 1.0)

	road.set_approach_progress(0.0)
	minimap.set_detour(true, detour_direction, detour_progress)

	if detour_progress < 1.0:
		return

	detour_active = false
	road.set_detour_active(false)
	minimap.set_detour(false)
	_advance_to_next_block()


func _advance_to_next_block() -> void:
	route_segment += 1
	segment_progress = 0.0
	player_choice = 0

	road.set_selected_turn(0)
	road.set_approach_progress(0.0)
	minimap.set_route_progress(route_segment, 0.0)


func _update_car_visual(delta: float) -> void:
	var center_x := road.size.x * 0.5 - player_car.size.x * 0.5
	var turn_shift := 0.0

	# As the intersection reaches Darren, the car visibly commits toward the
	# selected branch. It recenters after the new block loads.
	if not detour_active and player_choice != 0:
		var commit := clampf((segment_progress - 0.50) / 0.50, 0.0, 1.0)
		turn_shift = float(player_choice) * 34.0 * commit

	var target_x := center_x + turn_shift + fatigue_drift
	player_car.position.x = move_toward(player_car.position.x, target_x, 180.0 * delta)

	var target_rotation := float(player_choice) * 0.18 if player_choice != 0 else 0.0
	player_car.rotation = move_toward(player_car.rotation, target_rotation, 0.9 * delta)


# -----------------------------------------------------------------------------
# FATIGUE
# -----------------------------------------------------------------------------

func _update_fatigue(delta: float) -> void:
	if fatigue_strength <= 0.0:
		fatigue_drift = move_toward(fatigue_drift, 0.0, 15.0 * delta)
		return

	fatigue_drift_timer -= delta
	if fatigue_drift_timer <= 0.0:
		fatigue_drift_target = randf_range(
			-lerpf(3.0, 18.0, fatigue_strength),
			lerpf(3.0, 18.0, fatigue_strength)
		)
		fatigue_drift_timer = randf_range(0.8, 1.5)

	fatigue_drift = move_toward(
		fatigue_drift,
		fatigue_drift_target,
		lerpf(5.0, 18.0, fatigue_strength) * delta
	)

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
