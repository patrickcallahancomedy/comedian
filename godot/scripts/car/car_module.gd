extends GameModule

## CAR v0.3 — tiny navigation maze.
##
## STATE READS:
## energy, car_condition
##
## STATE WRITES:
## energy, gas, stress, relationships.nate, night_context
##
## HISTORY:
## drives_completed, missed_turns, nate_pickups
##
## RESULT:
## arrival_minutes_before_signup, arrival_clock_minutes, missed_turns,
## picked_up_nate, real_drive_seconds
##
## PLAYER EXPERIENCE:
## The car moves forward automatically. The player only chooses LEFT or RIGHT at
## intersections while glancing at the tiny whole-town map. Wrong turns create
## real extra driving. Phone popups and tiredness steal attention. The game does
## not explain the time consequence; the comedy night reveals it later.

@export_category("Drive Tuning")
@export_range(0.8, 3.0, 0.05) var seconds_per_block: float = 1.55
@export_range(0.6, 2.5, 0.05) var final_block_seconds: float = 1.05
@export_range(0.6, 4.0, 0.05) var wrong_turn_detour_seconds: float = 1.65
@export_range(0.5, 5.0, 0.1) var nate_pickup_extra_seconds: float = 2.2
@export_range(80.0, 400.0, 5.0) var road_scroll_speed: float = 215.0

@export_category("Comedy Night Clock")
@export var departure_clock_minutes: int = 19 * 60 + 16
@export var signup_close_clock_minutes: int = 19 * 60 + 45

@onready var road: CarRoad = $Road
@onready var player_car: ColorRect = $Road/PlayerCar
@onready var minimap: CarMinimap = $HUD/GPSPanel/GPSMargin/MiniMap
@onready var left_button: Button = $Controls/LeftButton
@onready var right_button: Button = $Controls/RightButton

@onready var phone_overlay: Control = $PhoneOverlay
@onready var phone_sender_label: Label = $PhoneOverlay/PhoneCard/PhoneMargin/PhoneLayout/SenderLabel
@onready var phone_message_label: Label = $PhoneOverlay/PhoneCard/PhoneMargin/PhoneLayout/MessageLabel
@onready var phone_positive_button: Button = $PhoneOverlay/PhoneCard/PhoneMargin/PhoneLayout/ChoiceRow/PositiveButton
@onready var phone_negative_button: Button = $PhoneOverlay/PhoneCard/PhoneMargin/PhoneLayout/ChoiceRow/NegativeButton

@onready var fatigue_overlay: Control = $FatigueOverlay
@onready var top_lid: ColorRect = $FatigueOverlay/TopLid
@onready var bottom_lid: ColorRect = $FatigueOverlay/BottomLid

@onready var result_panel: PanelContainer = $ResultPanel
@onready var result_time_label: Label = $ResultPanel/ResultMargin/ResultLayout/TimeLabel
@onready var result_label: Label = $ResultPanel/ResultMargin/ResultLayout/ResultLabel
@onready var continue_button: Button = $ResultPanel/ResultMargin/ResultLayout/ContinueButton

# 1 = right, -1 = left. The minimap is the only thing that tells the player.
const TURN_PATTERN := [1, -1, 1, -1, -1, 1, 1, -1]

var route_segment: int = 0
var segment_progress: float = 0.0
var player_choice: int = 0
var current_extra_seconds: float = 0.0

var detour_active: bool = false
var detour_progress: float = 0.0
var detour_direction: int = 1

var drive_elapsed: float = 0.0
var road_scroll: float = 0.0
var missed_turns: int = 0
var picked_up_nate: bool = false
var finished: bool = false

var phone_event_id: int = 0
var first_phone_shown: bool = false
var second_phone_shown: bool = false

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

	phone_overlay.hide()
	result_panel.hide()
	_set_eye_closure(0.0)

	road.set_selected_turn(0)
	road.set_detour_active(false)
	minimap.set_route_progress(route_segment, segment_progress)
	minimap.set_detour(false)

	left_button.pressed.connect(_choose_left)
	right_button.pressed.connect(_choose_right)
	phone_positive_button.pressed.connect(_on_phone_positive)
	phone_negative_button.pressed.connect(_on_phone_negative)
	continue_button.pressed.connect(_finish_and_continue)

	left_button.grab_focus()


func _process(delta: float) -> void:
	if finished:
		return

	drive_elapsed += delta
	road_scroll += road_scroll_speed * delta
	road.set_travel_scroll(road_scroll)

	_update_fatigue(delta)

	if detour_active:
		_update_detour(delta)
	else:
		_update_route(delta)

	_update_phone_events()


func _unhandled_key_input(event: InputEvent) -> void:
	if finished or phone_overlay.visible or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed:
		return
	if key_event.keycode == KEY_LEFT or key_event.keycode == KEY_A:
		_choose_left()
	elif key_event.keycode == KEY_RIGHT or key_event.keycode == KEY_D:
		_choose_right()


func _choose_left() -> void:
	_choose_turn(-1)


func _choose_right() -> void:
	_choose_turn(1)


func _choose_turn(direction: int) -> void:
	if finished or phone_overlay.visible or detour_active:
		return
	if route_segment >= TURN_PATTERN.size():
		return

	player_choice = direction
	road.set_selected_turn(player_choice)

	# Small visual lean only. Navigation is the mechanic, not steering physics.
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(player_car, "rotation", float(direction) * 0.10, 0.08)


func _effective_block_seconds() -> float:
	var base := final_block_seconds if route_segment >= TURN_PATTERN.size() else seconds_per_block
	var condition_factor := lerpf(1.22, 1.0, float(GameState.car_condition) / 100.0)
	return maxf(0.45, (base + current_extra_seconds) * condition_factor)


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
	current_extra_seconds = 0.0

	road.set_selected_turn(0)
	road.set_approach_progress(0.0)
	player_car.rotation = 0.0
	minimap.set_route_progress(route_segment, 0.0)


# -----------------------------------------------------------------------------
# PHONE DISTRACTIONS
# -----------------------------------------------------------------------------

func _update_phone_events() -> void:
	if phone_overlay.visible:
		return

	if not first_phone_shown and route_segment >= 2 and segment_progress >= 0.28:
		first_phone_shown = true
		_show_phone_event(1, "NATE", "u going up tonight?", "YEAH", "PROBABLY")
		return

	if not second_phone_shown and route_segment >= 5 and segment_progress >= 0.30:
		second_phone_shown = true
		_show_phone_event(2, "NATE", "can you pick me up?", "FINE", "NO")


func _show_phone_event(
	event_id: int,
	sender: String,
	message: String,
	positive_text: String,
	negative_text: String
) -> void:
	phone_event_id = event_id
	phone_sender_label.text = sender
	phone_message_label.text = message
	phone_positive_button.text = positive_text
	phone_negative_button.text = negative_text
	phone_overlay.show()
	phone_positive_button.grab_focus()


func _hide_phone() -> void:
	phone_event_id = 0
	phone_overlay.hide()
	left_button.grab_focus()


func _on_phone_positive() -> void:
	match phone_event_id:
		1:
			GameState.change_relationship("nate", 1)
		2:
			picked_up_nate = true
			current_extra_seconds += nate_pickup_extra_seconds
			GameState.change_relationship("nate", 2)
			GameState.increment_history("nate_pickups")
	_hide_phone()


func _on_phone_negative() -> void:
	if phone_event_id == 2:
		GameState.change_relationship("nate", -1)
	_hide_phone()


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
	phone_overlay.hide()
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
	GameState.night_context["picked_up_nate"] = picked_up_nate
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
		"picked_up_nate": picked_up_nate,
		"real_drive_seconds": snappedf(drive_elapsed, 0.1),
	})
