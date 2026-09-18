extends GameModule

## CAR v0.1 — a tiny lane-dodging drive with a GPS route to remember.
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
## arrival_minutes_before_signup, delay_minutes, collisions, missed_turns,
## picked_up_nate
##
## The important design rule: the drive only lasts a few real seconds, but the
## mistakes become in-game minutes that the next comedy-night module receives.

@export_category("Drive Tuning")
@export_range(6.0, 20.0, 0.5) var run_seconds: float = 12.0
@export_range(100.0, 500.0, 5.0) var traffic_speed: float = 255.0
@export_range(0.35, 1.5, 0.05) var traffic_spawn_seconds: float = 0.72
@export_range(5, 40, 1) var starting_signup_buffer_minutes: int = 18
@export_range(1, 15, 1) var missed_turn_penalty_minutes: int = 6
@export_range(1, 10, 1) var collision_penalty_minutes: int = 2
@export_range(1, 10, 1) var nate_pickup_penalty_minutes: int = 4

@onready var road: Control = $Road
@onready var traffic_layer: Control = $Road/TrafficLayer
@onready var player_car: ColorRect = $Road/PlayerCar
@onready var time_label: Label = $HUD/TimeLabel
@onready var signup_label: Label = $HUD/SignupLabel
@onready var gps_turn_label: Label = $HUD/GPSPanel/GPSMargin/GPSLayout/TurnLabel
@onready var gps_status_label: Label = $HUD/GPSPanel/GPSMargin/GPSLayout/StatusLabel
@onready var distraction_panel: PanelContainer = $HUD/DistractionPanel
@onready var distraction_timer_label: Label = $HUD/DistractionPanel/DistractionMargin/DistractionLayout/TimerLabel
@onready var feedback_label: Label = $HUD/FeedbackLabel
@onready var left_button: Button = $Controls/LeftButton
@onready var right_button: Button = $Controls/RightButton
@onready var result_panel: PanelContainer = $ResultPanel
@onready var result_label: Label = $ResultPanel/ResultMargin/ResultLayout/ResultLabel
@onready var continue_button: Button = $ResultPanel/ResultMargin/ResultLayout/ContinueButton

const LANE_X: Array[float] = [35.0, 144.0, 253.0]
const PLAYER_Y := 390.0
const CAR_SIZE := Vector2(46.0, 72.0)

var player_lane: int = 1
var time_left: float = 0.0
var spawn_left: float = 0.0
var delay_minutes: int = 0
var collisions: int = 0
var missed_turns: int = 0
var turn_checks_completed: int = 0
var required_turn: int = -1 # -1 = LEFT, 1 = RIGHT
var next_turn_check_at: float = 8.4
var second_turn_check_at: float = 4.2
var first_turn_checked := false
var second_turn_checked := false
var distraction_started := false
var distraction_resolved := false
var distraction_time_left: float = 2.6
var picked_up_nate := false
var finished := false
var active_traffic: Array[ColorRect] = []


func _ready() -> void:
	module_id = "car"
	if next_route_id.is_empty():
		next_route_id = "venue"

	time_left = run_seconds
	spawn_left = 0.35
	player_car.position = Vector2(LANE_X[player_lane], PLAYER_Y)
	distraction_panel.hide()
	result_panel.hide()
	feedback_label.text = ""

	required_turn = -1 if randi() % 2 == 0 else 1
	_refresh_gps()
	_refresh_hud()

	left_button.pressed.connect(_move_left)
	right_button.pressed.connect(_move_right)
	$HUD/DistractionPanel/DistractionMargin/DistractionLayout/IgnoreButton.pressed.connect(_ignore_nate)
	$HUD/DistractionPanel/DistractionMargin/DistractionLayout/PickupButton.pressed.connect(_pick_up_nate)
	continue_button.pressed.connect(_finish_and_continue)

	left_button.grab_focus()


func _process(delta: float) -> void:
	if finished:
		return

	time_left = maxf(0.0, time_left - delta)
	spawn_left -= delta

	if spawn_left <= 0.0:
		_spawn_traffic()
		spawn_left = _effective_spawn_interval()

	_update_traffic(delta)
	_update_route_checks()
	_update_distraction(delta)
	_refresh_hud()

	if time_left <= 0.0:
		_end_drive()


func _unhandled_key_input(event: InputEvent) -> void:
	if finished or not event.pressed:
		return
	if event.keycode == KEY_LEFT or event.keycode == KEY_A:
		_move_left()
	elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
		_move_right()


func _move_left() -> void:
	if finished:
		return
	player_lane = maxi(0, player_lane - 1)
	_move_player_to_lane()


func _move_right() -> void:
	if finished:
		return
	player_lane = mini(2, player_lane + 1)
	_move_player_to_lane()


func _move_player_to_lane() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	var intoxication := int(GameState.current_intoxication)
	var tiredness := 100 - int(GameState.energy)
	var move_time := 0.10 + float(intoxication) * 0.0015 + float(tiredness) * 0.0006
	tween.tween_property(player_car, "position:x", LANE_X[player_lane], move_time)


func _spawn_traffic() -> void:
	var traffic := ColorRect.new()
	traffic.name = "TrafficCar"
	traffic.size = CAR_SIZE
	traffic.position = Vector2(LANE_X[randi_range(0, 2)], -CAR_SIZE.y)
	traffic.color = Color(0.92, 0.46, 0.19, 1.0)
	traffic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	traffic_layer.add_child(traffic)
	active_traffic.append(traffic)


func _effective_spawn_interval() -> float:
	var condition_pressure := float(100 - GameState.car_condition) * 0.0018
	var intoxication_pressure := float(GameState.current_intoxication) * 0.0012
	return maxf(0.42, traffic_spawn_seconds - condition_pressure - intoxication_pressure)


func _update_traffic(delta: float) -> void:
	var speed_multiplier := 1.0 + float(GameState.current_intoxication) / 250.0
	var effective_speed := traffic_speed * speed_multiplier

	for i in range(active_traffic.size() - 1, -1, -1):
		var traffic := active_traffic[i]
		if not is_instance_valid(traffic):
			active_traffic.remove_at(i)
			continue

		traffic.position.y += effective_speed * delta

		if traffic.get_rect().intersects(player_car.get_rect()):
			_handle_collision(traffic)
			active_traffic.remove_at(i)
			continue

		if traffic.position.y > road.size.y + 90.0:
			traffic.queue_free()
			active_traffic.remove_at(i)


func _handle_collision(traffic: ColorRect) -> void:
	collisions += 1
	delay_minutes += collision_penalty_minutes
	GameState.change_stress(4)
	GameState.change_car_condition(-3)
	GameState.increment_history("car_collisions")
	traffic.queue_free()
	_flash_feedback("HONK. Jesus.  +%d MIN" % collision_penalty_minutes)


func _update_route_checks() -> void:
	if not first_turn_checked and time_left <= next_turn_check_at:
		first_turn_checked = true
		_check_turn()
	elif first_turn_checked and not second_turn_checked and time_left <= second_turn_check_at:
		second_turn_checked = true
		_check_turn()


func _check_turn() -> void:
	turn_checks_completed += 1
	var correct_lane := 0 if required_turn < 0 else 2
	if player_lane == correct_lane:
		_flash_feedback("GOT THE TURN")
	else:
		missed_turns += 1
		delay_minutes += missed_turn_penalty_minutes
		GameState.change_stress(3)
		GameState.increment_history("missed_turns")
		_flash_feedback("MISSED IT. RECALCULATING...  +%d MIN" % missed_turn_penalty_minutes)

	if turn_checks_completed < 2:
		required_turn = -1 if randi() % 2 == 0 else 1
		_refresh_gps()
	else:
		gps_turn_label.text = "STRAIGHT"
		gps_status_label.text = "VENUE AHEAD"


func _refresh_gps() -> void:
	gps_turn_label.text = "← LEFT" if required_turn < 0 else "RIGHT →"
	gps_status_label.text = "NEXT TURN"


func _update_distraction(delta: float) -> void:
	# Nate appears between the two GPS turns, forcing attention away from the map
	# without pausing traffic or disabling steering.
	if not distraction_started and time_left <= 6.7:
		distraction_started = true
		distraction_time_left = 2.6
		distraction_panel.show()

	if not distraction_started or distraction_resolved:
		return

	distraction_time_left = maxf(0.0, distraction_time_left - delta)
	distraction_timer_label.text = "%.1f" % distraction_time_left
	if distraction_time_left <= 0.0:
		_ignore_nate()


func _ignore_nate() -> void:
	if distraction_resolved:
		return
	distraction_resolved = true
	distraction_panel.hide()
	GameState.change_relationship("nate", -1)
	_flash_feedback("NATE: cool man")


func _pick_up_nate() -> void:
	if distraction_resolved:
		return
	distraction_resolved = true
	picked_up_nate = true
	delay_minutes += nate_pickup_penalty_minutes
	GameState.change_relationship("nate", 2)
	GameState.increment_history("nate_pickups")
	distraction_panel.hide()
	_flash_feedback("FINE. GET IN.  +%d MIN" % nate_pickup_penalty_minutes)


func _flash_feedback(text: String) -> void:
	feedback_label.text = text
	feedback_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.7)
	tween.tween_property(feedback_label, "modulate:a", 0.0, 0.35)


func _refresh_hud() -> void:
	time_label.text = "%0.1f SEC" % time_left
	var projected_buffer := starting_signup_buffer_minutes - delay_minutes
	if projected_buffer >= 0:
		signup_label.text = "SIGNUP IN %d MIN" % projected_buffer
	else:
		signup_label.text = "%d MIN LATE" % abs(projected_buffer)


func _end_drive() -> void:
	if finished:
		return
	finished = true
	left_button.disabled = true
	right_button.disabled = true

	if distraction_started and not distraction_resolved:
		_ignore_nate()

	var arrival_minutes_before_signup := starting_signup_buffer_minutes - delay_minutes

	GameState.change_energy(-2)
	GameState.change_gas(-3)
	if collisions == 0 and missed_turns == 0:
		GameState.change_stress(-2)

	GameState.night_context = {
		"arrival_minutes_before_signup": arrival_minutes_before_signup,
		"drive_delay_minutes": delay_minutes,
		"drive_collisions": collisions,
		"drive_missed_turns": missed_turns,
		"picked_up_nate": picked_up_nate,
	}
	GameState.increment_history("drives_completed")

	var arrival_text := (
		"%d MIN BEFORE SIGNUP CLOSES" % arrival_minutes_before_signup
		if arrival_minutes_before_signup >= 0
		else "%d MIN AFTER SIGNUP CLOSED" % abs(arrival_minutes_before_signup)
	)

	result_label.text = "YOU MADE IT.\n\n%s" % arrival_text
	result_panel.show()
	continue_button.grab_focus()


func _finish_and_continue() -> void:
	var arrival_minutes_before_signup := int(GameState.night_context.get(
		"arrival_minutes_before_signup",
		0
	))
	finish_module({
		"status": "drive_complete",
		"arrival_minutes_before_signup": arrival_minutes_before_signup,
		"delay_minutes": delay_minutes,
		"collisions": collisions,
		"missed_turns": missed_turns,
		"picked_up_nate": picked_up_nate,
	})
