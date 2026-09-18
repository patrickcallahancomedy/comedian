extends GameModule

## CAR v0.2 — tiny road game, tiny town GPS, quiet consequences.
##
## STATE READS:
## energy, stress, current_intoxication, car_condition, gas
##
## STATE WRITES:
## energy, stress, car_condition, gas, relationships.nate, night_context
##
## HISTORY:
## drives_completed, car_collisions, missed_turns, nate_pickups
##
## RESULT:
## arrival_minutes_before_signup, arrival_clock_minutes, collisions,
## missed_turns, picked_up_nate, real_drive_seconds
##
## PLAYER EXPERIENCE:
## Drive with only LEFT / RIGHT. Glance at the tiny town GPS to know which side
## to be on for the next intersection. Traffic, phone interruptions, and Darren's
## condition steal attention. The car game never shows an RPG-style time penalty.
## The next comedy-night module is where the player discovers what the drive cost.

@export_category("Drive Tuning")
@export_range(1.0, 4.0, 0.05) var seconds_per_block: float = 1.80
@export_range(0.8, 3.0, 0.05) var final_block_seconds: float = 1.25
@export_range(100.0, 500.0, 5.0) var traffic_speed: float = 250.0
@export_range(0.35, 1.5, 0.05) var traffic_spawn_seconds: float = 0.72
@export_range(100.0, 500.0, 5.0) var road_scroll_speed: float = 265.0
@export_range(0.5, 5.0, 0.1) var missed_turn_detour_seconds: float = 1.8
@export_range(0.5, 6.0, 0.1) var nate_pickup_detour_seconds: float = 2.6

@export_category("Comedy Night Clock")
@export var departure_clock_minutes: int = 19 * 60 + 16
@export var signup_close_clock_minutes: int = 19 * 60 + 45

@onready var road: CarRoad = $Road
@onready var traffic_layer: Control = $Road/TrafficLayer
@onready var player_car: ColorRect = $Road/PlayerCar
@onready var minimap: CarMinimap = $HUD/GPSPanel/GPSMargin/GPSLayout/MiniMap
@onready var map_status_label: Label = $HUD/GPSPanel/GPSMargin/GPSLayout/MapStatusLabel
@onready var feedback_label: Label = $HUD/FeedbackLabel
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

# These eight instructions match the eight corners in car_minimap.gd.
# 1 = right turn, -1 = left turn.
const TURN_PATTERN := [1, -1, 1, -1, -1, 1, 1, -1]

var player_lane: int = 1
var route_segment: int = 0
var block_progress: float = 0.0
var current_block_seconds: float = 1.8
var next_block_extra_seconds: float = 0.0
var turn_checked: bool = false
var final_leg: bool = false

var drive_elapsed: float = 0.0
var road_scroll: float = 0.0
var collision_slowdown_timer: float = 0.0

var collisions: int = 0
var missed_turns: int = 0
var picked_up_nate: bool = false
var finished: bool = false

var active_traffic: Array[ColorRect] = []
var traffic_spawn_timer: float = 0.45
var last_traffic_lane: int = -1

var phone_event_id: int = 0
var first_phone_shown: bool = false
var second_phone_shown: bool = false

var map_status_timer: float = 0.0

var fatigue_strength: float = 0.0
var fatigue_wait_timer: float = 99.0
var fatigue_blink_elapsed: float = 0.0
var fatigue_blink_duration: float = 0.0
var fatigue_blinking: bool = false
var eye_closure: float = 0.0
var drift_offset: float = 0.0
var drift_target: float = 0.0
var drift_change_timer: float = 0.0


func _ready() -> void:
	module_id = "car"
	if next_route_id.is_empty():
		next_route_id = "venue"

	current_block_seconds = seconds_per_block
	fatigue_strength = clampf(float(50 - GameState.energy) / 50.0, 0.0, 1.0)
	if fatigue_strength > 0.0:
		fatigue_wait_timer = lerpf(4.6, 2.1, fatigue_strength)
	else:
		fatigue_wait_timer = 99.0

	phone_overlay.hide()
	result_panel.hide()
	feedback_label.text = ""
	map_status_label.text = "TO THE BACK ROOM"

	player_car.position.x = _lane_x(player_lane)
	_set_eye_closure(0.0)
	minimap.set_route_progress(route_segment, block_progress)

	left_button.pressed.connect(_move_left)
	right_button.pressed.connect(_move_right)
	phone_positive_button.pressed.connect(_on_phone_positive)
	phone_negative_button.pressed.connect(_on_phone_negative)
	continue_button.pressed.connect(_finish_and_continue)

	left_button.grab_focus()


func _process(delta: float) -> void:
	if finished:
		return

	drive_elapsed += delta
	_update_fatigue(delta)
	_update_player_position(delta)
	_update_road(delta)
	_update_traffic(delta)
	_update_route(delta)
	_update_phone_events()
	_update_map_status(delta)


func _unhandled_key_input(event: InputEvent) -> void:
	if finished or phone_overlay.visible or not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if not key_event.pressed:
		return

	if key_event.keycode == KEY_LEFT or key_event.keycode == KEY_A:
		_move_left()
	elif key_event.keycode == KEY_RIGHT or key_event.keycode == KEY_D:
		_move_right()


# -----------------------------------------------------------------------------
# STEERING / ROAD
# -----------------------------------------------------------------------------

func _move_left() -> void:
	if finished or phone_overlay.visible:
		return
	player_lane = maxi(0, player_lane - 1)


func _move_right() -> void:
	if finished or phone_overlay.visible:
		return
	player_lane = mini(2, player_lane + 1)


func _lane_x(lane: int) -> float:
	var lane_width := road.size.x / 3.0
	return lane_width * (float(lane) + 0.5) - player_car.size.x * 0.5


func _update_player_position(delta: float) -> void:
	var intoxication := clampf(float(GameState.current_intoxication) / 100.0, 0.0, 1.0)
	var steering_speed := lerpf(720.0, 390.0, intoxication)
	var target_x := _lane_x(player_lane) + drift_offset
	player_car.position.x = move_toward(player_car.position.x, target_x, steering_speed * delta)


func _update_road(delta: float) -> void:
	var speed_multiplier := 0.48 if collision_slowdown_timer > 0.0 else 1.0
	road_scroll += road_scroll_speed * speed_multiplier * delta
	road.set_scroll_offset(road_scroll)

	if final_leg:
		road.set_intersection_progress(-1.0)
	else:
		road.set_intersection_progress(block_progress)

	if collision_slowdown_timer > 0.0:
		collision_slowdown_timer = maxf(0.0, collision_slowdown_timer - delta)


# -----------------------------------------------------------------------------
# ROUTE / GPS
# -----------------------------------------------------------------------------

func _update_route(delta: float) -> void:
	var route_speed_multiplier := 0.48 if collision_slowdown_timer > 0.0 else 1.0
	block_progress += delta * route_speed_multiplier / maxf(0.1, current_block_seconds)
	block_progress = minf(block_progress, 1.0)

	minimap.set_route_progress(route_segment, block_progress)

	if not final_leg and not turn_checked and block_progress >= 0.82:
		turn_checked = true
		_check_turn()

	if block_progress < 1.0:
		return

	if final_leg:
		_end_drive()
		return

	route_segment += 1
	block_progress = 0.0
	turn_checked = false

	if route_segment >= TURN_PATTERN.size():
		final_leg = true
		current_block_seconds = final_block_seconds + next_block_extra_seconds
	else:
		current_block_seconds = seconds_per_block + next_block_extra_seconds
	next_block_extra_seconds = 0.0

	minimap.set_route_progress(route_segment, block_progress)


func _check_turn() -> void:
	var required_turn := int(TURN_PATTERN[route_segment])
	var correct_lane := 0 if required_turn < 0 else 2

	if player_lane == correct_lane:
		map_status_label.text = "ON ROUTE"
		map_status_timer = 0.65
		return

	missed_turns += 1
	next_block_extra_seconds += missed_turn_detour_seconds
	GameState.change_stress(3)
	GameState.increment_history("missed_turns")
	map_status_label.text = "RECALCULATING..."
	map_status_timer = 1.15


func _update_map_status(delta: float) -> void:
	if map_status_timer <= 0.0:
		return
	map_status_timer = maxf(0.0, map_status_timer - delta)
	if map_status_timer <= 0.0:
		map_status_label.text = "TO THE BACK ROOM"


# -----------------------------------------------------------------------------
# TRAFFIC
# -----------------------------------------------------------------------------

func _update_traffic(delta: float) -> void:
	traffic_spawn_timer -= delta
	if traffic_spawn_timer <= 0.0 and not final_leg:
		_spawn_traffic()
		traffic_spawn_timer = _next_traffic_spawn_delay()

	var intoxication_multiplier := 1.0 + float(GameState.current_intoxication) / 280.0

	for i in range(active_traffic.size() - 1, -1, -1):
		var traffic := active_traffic[i]
		if not is_instance_valid(traffic):
			active_traffic.remove_at(i)
			continue

		var speed := float(traffic.get_meta("speed", traffic_speed))
		traffic.position.y += speed * intoxication_multiplier * delta

		var traffic_rect := Rect2(traffic.position, traffic.size)
		var player_rect := Rect2(player_car.position, player_car.size)
		if traffic_rect.intersects(player_rect):
			_handle_collision(traffic)
			active_traffic.remove_at(i)
			continue

		if traffic.position.y > road.size.y + 100.0:
			traffic.queue_free()
			active_traffic.remove_at(i)


func _spawn_traffic() -> void:
	var lane := randi_range(0, 2)
	if lane == last_traffic_lane and randi() % 100 < 60:
		lane = (lane + 1 + randi_range(0, 1)) % 3
	last_traffic_lane = lane

	var traffic := ColorRect.new()
	traffic.name = "TrafficCar"
	traffic.size = Vector2(48, 78)
	traffic.position = Vector2(_lane_x(lane), -90.0)
	traffic.color = Color(0.95, 0.48, 0.18, 1.0)
	traffic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	traffic.set_meta("speed", traffic_speed + randf_range(-24.0, 42.0))

	var windshield := ColorRect.new()
	windshield.position = Vector2(8, 8)
	windshield.size = Vector2(32, 17)
	windshield.color = Color(0.65, 0.84, 0.90, 1.0)
	windshield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	traffic.add_child(windshield)

	traffic_layer.add_child(traffic)
	active_traffic.append(traffic)


func _next_traffic_spawn_delay() -> float:
	var bad_car := float(100 - GameState.car_condition) / 100.0
	var intoxication := float(GameState.current_intoxication) / 100.0
	return maxf(
		0.44,
		traffic_spawn_seconds - bad_car * 0.10 - intoxication * 0.12 + randf_range(-0.10, 0.16)
	)


func _handle_collision(traffic: ColorRect) -> void:
	collisions += 1
	collision_slowdown_timer = maxf(collision_slowdown_timer, 0.85)
	GameState.change_stress(4)
	GameState.change_car_condition(-3)
	GameState.increment_history("car_collisions")
	traffic.queue_free()
	_flash_feedback("HONK. Jesus.")


func _flash_feedback(text: String) -> void:
	feedback_label.text = text
	feedback_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.65)
	tween.tween_property(feedback_label, "modulate:a", 0.0, 0.32)


# -----------------------------------------------------------------------------
# PHONE DISTRACTIONS
# -----------------------------------------------------------------------------

func _update_phone_events() -> void:
	if phone_overlay.visible:
		return

	if not first_phone_shown and route_segment >= 2 and block_progress >= 0.18:
		first_phone_shown = true
		_show_phone_event(
			1,
			"NATE",
			"u going up tonight?",
			"YEAH",
			"PROBABLY"
		)
		return

	if not second_phone_shown and route_segment >= 5 and block_progress >= 0.16:
		second_phone_shown = true
		_show_phone_event(
			2,
			"NATE",
			"can you pick me up?",
			"FINE",
			"NO"
		)


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
			next_block_extra_seconds += nate_pickup_detour_seconds
			GameState.change_relationship("nate", 2)
			GameState.increment_history("nate_pickups")
	_hide_phone()


func _on_phone_negative() -> void:
	if phone_event_id == 2:
		GameState.change_relationship("nate", -1)
	_hide_phone()


# -----------------------------------------------------------------------------
# FATIGUE / CONDITION
# -----------------------------------------------------------------------------

func _update_fatigue(delta: float) -> void:
	if fatigue_strength <= 0.0:
		drift_offset = move_toward(drift_offset, 0.0, 25.0 * delta)
		return

	drift_change_timer -= delta
	if drift_change_timer <= 0.0:
		var max_drift := lerpf(5.0, 24.0, fatigue_strength)
		drift_target = randf_range(-max_drift, max_drift)
		drift_change_timer = randf_range(0.65, 1.25)
	drift_offset = move_toward(
		drift_offset,
		drift_target,
		lerpf(8.0, 22.0, fatigue_strength) * delta
	)

	if fatigue_blinking:
		fatigue_blink_elapsed += delta
		var t := clampf(fatigue_blink_elapsed / fatigue_blink_duration, 0.0, 1.0)
		eye_closure = sin(t * PI)
		_set_eye_closure(eye_closure)

		if t >= 1.0:
			fatigue_blinking = false
			_set_eye_closure(0.0)
			fatigue_wait_timer = randf_range(
				lerpf(4.8, 2.2, fatigue_strength),
				lerpf(6.2, 3.0, fatigue_strength)
			)
		return

	fatigue_wait_timer -= delta
	if fatigue_wait_timer <= 0.0:
		fatigue_blinking = true
		fatigue_blink_elapsed = 0.0
		fatigue_blink_duration = randf_range(
			lerpf(0.30, 0.75, fatigue_strength),
			lerpf(0.48, 1.20, fatigue_strength)
		)

		# A micro-sleep can pull the car sideways while the player cannot see.
		if fatigue_strength > 0.55 and randi() % 100 < int(35.0 * fatigue_strength):
			drift_target = randf_range(-30.0, 30.0)


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
	if collisions == 0 and missed_turns == 0:
		GameState.change_stress(-2)

	GameState.night_context["arrival_minutes_before_signup"] = arrival_minutes_before_signup
	GameState.night_context["arrival_clock_minutes"] = arrival_clock_minutes
	GameState.night_context["drive_real_seconds"] = drive_elapsed
	GameState.night_context["drive_collisions"] = collisions
	GameState.night_context["drive_missed_turns"] = missed_turns
	GameState.night_context["picked_up_nate"] = picked_up_nate
	GameState.increment_history("drives_completed")

	result_time_label.text = _format_clock(arrival_clock_minutes)
	if collisions == 0:
		result_label.text = "YOU MADE IT.\n\nYou park and sit there for about three seconds longer than necessary."
	else:
		result_label.text = "YOU MADE IT.\n\nThe drive was not graceful. You are still here."

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
		"collisions": collisions,
		"missed_turns": missed_turns,
		"picked_up_nate": picked_up_nate,
		"real_drive_seconds": snappedf(drive_elapsed, 0.1),
	})
