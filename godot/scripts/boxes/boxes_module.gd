extends Control

const FIRST_THOUGHT := "I wonder why they call it a lunch break when I never stop being tired."
# Placeholder copy for the second tutorial thought. Easy to swap later.
const SECOND_THOUGHT := "Every box has somewhere to be before I do."

@onready var left_button_art: TextureRect = $GameplayLayer/LeftButton
@onready var right_button_art: TextureRect = $GameplayLayer/RightButton

@onready var left_hitbox: Button = $GameplayLayer/LeftHitbox
@onready var right_hitbox: Button = $GameplayLayer/RightHitbox
@onready var notebook_hitbox: Button = $GameplayLayer/NotebookHitbox

@onready var belt: TextureRect = $GameplayLayer/Belt
@onready var box_current: TextureRect = $GameplayLayer/BoxCurrent
@onready var box_routed: TextureRect = $GameplayLayer/BoxRouted
@onready var destination_label: Label = $GameplayLayer/BoxCurrent/DestinationTag/DestinationLabel
@onready var route_feedback: Label = $GameplayLayer/RouteFeedback

@onready var quota_hud: Label = $HUDLayer/QuotaHUD
@onready var shift_count_hud: Label = $HUDLayer/ShiftCountHUD
@onready var shift_result_label: Label = $HUDLayer/ShiftResultLabel
@onready var thought_bubble: TextureRect = $HUDLayer/ThoughtBubble
@onready var thought_text: Label = $HUDLayer/ThoughtBubble/ThoughtText
@onready var notebook_overlay: Control = $HUDLayer/NotebookOverlay
@onready var premises_list_label: Label = $HUDLayer/NotebookOverlay/PremisesList
@onready var active_thought_label: Label = $HUDLayer/NotebookOverlay/ActiveThought
@onready var write_idea_button: Button = $HUDLayer/NotebookOverlay/WriteIdeaButton
@onready var close_notebook_button: Button = $HUDLayer/NotebookOverlay/CloseNotebookButton

var belt_start_position: Vector2
var box_spawn_position: Vector2
var box_ready_position: Vector2
var active_thought_start_position: Vector2
var current_destination := "left"
var correct_routes := 0
var wrong_routes := 0
var missed_boxes := 0
var boxes_routed := 0
var premises_saved := 0
var first_thought_shown := false
var second_thought_shown := false
var active_thought := ""
var pending_save_text := ""
var notebook_open := false
var box_waiting_for_route := false
var auto_route_enabled := false
var box_cycle_id := 0

# The quota exists from the first box. The opening boxes still teach the
# controls safely, but they count toward the same 10-box shift the player sees.
var shift_active := false
var shift_finished := false
var shift_boxes_processed := 0
var shift_correct_routes := 0

# Work notebook:
#   left page  = PREMISES already written down
#   right page = IDEAS currently in Darren's head
# Writing an idea down moves it from the right page to the left page.
#
# Later/home notebook:
#   left page  = TESTED JOKES
#   right page = PREMISES
# These arrays will eventually move into persistent GameState so every module
# sees the same material.
var premises: Array[String] = []
var tested_jokes: Array[String] = []

const ROUTE_DURATION := 1.0
const BELT_SHIFT_RATIO := 0.06
const PRACTICE_BOXES_BEFORE_THOUGHT := 3
const SECOND_THOUGHT_AT_SHIFT_BOX := 5
const AUTO_ROUTE_DELAY := 2.0
const SHIFT_QUOTA := 8
const SHIFT_BOX_LIMIT := 10

var left_normal = preload("res://assets/boxes/left_button.png")
var left_pressed = preload("res://assets/boxes/left_button_pressed.png")

var right_normal = preload("res://assets/boxes/right_button.png")
var right_pressed = preload("res://assets/boxes/right_button_pressed.png")


func _ready() -> void:
	belt_start_position = belt.position
	box_spawn_position = box_current.position
	box_ready_position = box_routed.position
	active_thought_start_position = active_thought_label.position

	thought_text.text = FIRST_THOUGHT
	_assign_destination()

	route_feedback.hide()
	shift_result_label.hide()
	thought_bubble.hide()
	notebook_overlay.hide()
	write_idea_button.hide()

	left_hitbox.button_down.connect(_on_left_down)
	left_hitbox.button_up.connect(_on_left_up)
	right_hitbox.button_down.connect(_on_right_down)
	right_hitbox.button_up.connect(_on_right_up)

	notebook_hitbox.pressed.connect(_open_notebook)
	thought_bubble.gui_input.connect(_on_thought_bubble_input)
	write_idea_button.pressed.connect(_write_active_thought)
	close_notebook_button.pressed.connect(_close_notebook)

	box_routed.hide()
	left_hitbox.disabled = true
	right_hitbox.disabled = true
	notebook_hitbox.disabled = true

	# The player sees the goal immediately, and the first three tutorial boxes
	# already count toward it. Only the automatic routing pressure waits until
	# after the notebook tutorial.
	_start_scored_shift()

	var tween = create_tween()
	tween.tween_property(box_current, "position", box_ready_position, 0.5)
	tween.finished.connect(_on_box_ready)


func _assign_destination() -> void:
	current_destination = ["left", "right"].pick_random()
	destination_label.text = current_destination.to_upper()


func _on_box_ready() -> void:
	if shift_finished:
		return

	box_waiting_for_route = true

	# Once the safe tutorial is over, work keeps moving whether Darren pays
	# attention or not. Each ready box gets its own deadline.
	if auto_route_enabled:
		box_cycle_id += 1
		_start_auto_route_countdown(box_cycle_id)

	if notebook_open:
		left_hitbox.disabled = true
		right_hitbox.disabled = true
		notebook_hitbox.disabled = true
	else:
		left_hitbox.disabled = false
		right_hitbox.disabled = false
		notebook_hitbox.disabled = false

	# The second thought arrives after two pressured boxes have followed the
	# three safe opening boxes. It cannot appear during the tutorial anymore.
	if auto_route_enabled and shift_boxes_processed >= SECOND_THOUGHT_AT_SHIFT_BOX and not second_thought_shown:
		second_thought_shown = true
		_show_pressure_thought()


func _start_auto_route_countdown(cycle_id: int) -> void:
	await get_tree().create_timer(AUTO_ROUTE_DELAY).timeout

	# If the player already handled this box, its cycle id will no longer match.
	if cycle_id != box_cycle_id or not box_waiting_for_route or shift_finished:
		return

	missed_boxes += 1
	print("Missed boxes: ", missed_boxes)

	# Doing nothing still sends the box somewhere. It deliberately travels the
	# wrong direction so a missed box has the same consequence as a bad route.
	var wrong_direction := "right" if current_destination == "left" else "left"
	_route_box(wrong_direction, true)


func _on_left_down() -> void:
	left_button_art.texture = left_pressed


func _on_left_up() -> void:
	left_button_art.texture = left_normal
	_route_box("left")


func _on_right_down() -> void:
	right_button_art.texture = right_pressed


func _on_right_up() -> void:
	right_button_art.texture = right_normal
	_route_box("right")


func _route_box(direction: String, forced := false) -> void:
	if shift_finished:
		return
	if notebook_open and not forced:
		return
	if not box_waiting_for_route:
		return

	box_waiting_for_route = false
	box_cycle_id += 1 # invalidate the countdown for the box that just routed
	left_hitbox.disabled = true
	right_hitbox.disabled = true
	notebook_hitbox.disabled = true
	boxes_routed += 1
	print("Boxes routed: ", boxes_routed)

	var is_correct := direction == current_destination
	if is_correct:
		correct_routes += 1
	else:
		wrong_routes += 1

	if shift_active:
		shift_boxes_processed += 1
		if is_correct:
			shift_correct_routes += 1
		_update_shift_hud()

	_show_route_feedback(is_correct)

	box_current.hide()
	box_routed.show()

	var target_x: float
	var belt_shift := belt.size.x * BELT_SHIFT_RATIO
	var target_belt_x: float

	if direction == "left":
		target_x = -120
		target_belt_x = belt_start_position.x - belt_shift
	else:
		target_x = 480
		target_belt_x = belt_start_position.x + belt_shift

	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(box_routed, "position:x", target_x, ROUTE_DURATION)
	tween.tween_property(belt, "position:x", target_belt_x, ROUTE_DURATION)
	tween.finished.connect(_reset_box)


func _show_route_feedback(is_correct: bool) -> void:
	route_feedback.modulate.a = 1.0
	route_feedback.text = "CORRECT" if is_correct else "WRONG WAY"
	route_feedback.add_theme_color_override(
		"font_color",
		Color(0.58, 0.78, 0.62, 1.0) if is_correct else Color(0.86, 0.46, 0.43, 1.0)
	)
	route_feedback.show()

	var tween = create_tween()
	tween.tween_interval(0.55)
	tween.tween_property(route_feedback, "modulate:a", 0.0, 0.25)
	tween.finished.connect(route_feedback.hide)


func _reset_box() -> void:
	box_routed.hide()
	box_routed.position = box_ready_position
	belt.position = belt_start_position

	if shift_active and shift_boxes_processed >= SHIFT_BOX_LIMIT:
		_end_live_shift()
		return

	# Keep the first three boxes completely safe. The conveyor pauses here for
	# Darren's first thought so the player learns the notebook before pressure.
	if boxes_routed >= PRACTICE_BOXES_BEFORE_THOUGHT and not first_thought_shown:
		first_thought_shown = true
		_show_first_thought()
		return

	_start_next_box()


func _start_next_box() -> void:
	if shift_finished:
		return

	box_waiting_for_route = false
	box_current.show()
	box_current.position = box_spawn_position
	_assign_destination()

	left_hitbox.disabled = true
	right_hitbox.disabled = true
	notebook_hitbox.disabled = true

	var tween = create_tween()
	tween.tween_property(box_current, "position", box_ready_position, 0.5)
	tween.finished.connect(_on_box_ready)


func _start_scored_shift() -> void:
	shift_active = true
	shift_finished = false
	shift_boxes_processed = 0
	shift_correct_routes = 0
	auto_route_enabled = false
	_update_shift_hud()
	quota_hud.show()
	shift_count_hud.show()


func _update_shift_hud() -> void:
	quota_hud.text = "QUOTA  %d / %d" % [shift_correct_routes, SHIFT_QUOTA]
	shift_count_hud.text = "BOXES  %d / %d" % [shift_boxes_processed, SHIFT_BOX_LIMIT]


func _end_live_shift() -> void:
	shift_active = false
	shift_finished = true
	auto_route_enabled = false
	box_waiting_for_route = false
	box_cycle_id += 1

	left_hitbox.disabled = true
	right_hitbox.disabled = true
	notebook_hitbox.disabled = true
	thought_bubble.hide()
	notebook_overlay.hide()
	notebook_open = false

	var quota_met := shift_correct_routes >= SHIFT_QUOTA
	shift_result_label.text = (
		"SHIFT COMPLETE\nQUOTA MET\n%d / %d" % [shift_correct_routes, SHIFT_QUOTA]
		if quota_met
		else "SHIFT COMPLETE\nMISSED QUOTA\n%d / %d" % [shift_correct_routes, SHIFT_QUOTA]
	)
	shift_result_label.show()


func _show_first_thought() -> void:
	active_thought = FIRST_THOUGHT
	thought_text.text = FIRST_THOUGHT
	left_hitbox.disabled = true
	right_hitbox.disabled = true
	notebook_hitbox.disabled = false
	thought_bubble.modulate.a = 0.0
	thought_bubble.show()

	var tween = create_tween()
	tween.tween_property(thought_bubble, "modulate:a", 1.0, 0.2)


func _show_pressure_thought() -> void:
	active_thought = SECOND_THOUGHT
	thought_text.text = SECOND_THOUGHT
	thought_bubble.modulate.a = 0.0
	thought_bubble.show()

	# Unlike the first tutorial thought, the work controls stay live and the
	# current box countdown does not stop.
	var tween = create_tween()
	tween.tween_property(thought_bubble, "modulate:a", 1.0, 0.2)


func _on_thought_bubble_input(event: InputEvent) -> void:
	if not thought_bubble.visible or notebook_open or shift_finished:
		return

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_open_notebook()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_open_notebook()


func _open_notebook() -> void:
	if notebook_open or shift_finished:
		return

	notebook_open = true
	left_hitbox.disabled = true
	right_hitbox.disabled = true
	notebook_hitbox.disabled = true
	thought_bubble.hide()
	_refresh_notebook_pages()

	notebook_overlay.modulate.a = 0.0
	notebook_overlay.show()

	var tween = create_tween()
	tween.tween_property(notebook_overlay, "modulate:a", 1.0, 0.15)


func _refresh_notebook_pages() -> void:
	premises_list_label.text = _format_idea_list(premises, "No premises yet.")

	active_thought_label.position = active_thought_start_position
	active_thought_label.modulate.a = 1.0
	write_idea_button.disabled = false

	if active_thought.is_empty():
		active_thought_label.text = "No new ideas."
		active_thought_label.show()
		write_idea_button.hide()
	else:
		active_thought_label.text = active_thought
		active_thought_label.show()
		write_idea_button.show()


func _format_idea_list(items: Array[String], empty_text: String) -> String:
	if items.is_empty():
		return empty_text

	var lines := PackedStringArray()
	for item in items:
		lines.append("• " + item)
	return "\n\n".join(lines)


func _close_notebook() -> void:
	if not notebook_open:
		return

	notebook_open = false
	notebook_overlay.hide()

	# Closing without writing loses the temporary idea.
	if not active_thought.is_empty():
		active_thought = ""
		thought_bubble.hide()

	_resume_work_after_notebook()


func _write_active_thought() -> void:
	if active_thought.is_empty() or not pending_save_text.is_empty():
		return

	pending_save_text = active_thought
	write_idea_button.disabled = true

	# The idea visibly crosses the spiral from the right IDEAS page into the
	# left PREMISES page. The live conveyor keeps running underneath this overlay.
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(active_thought_label, "position:x", premises_list_label.position.x, 0.4)
	tween.tween_property(active_thought_label, "position:y", premises_list_label.position.y, 0.4)
	tween.tween_property(active_thought_label, "modulate:a", 0.15, 0.4)
	tween.finished.connect(_finish_write_active_thought)


func _finish_write_active_thought() -> void:
	premises.append(pending_save_text)
	premises_saved += 1
	print("Premises saved: ", premises_saved)

	pending_save_text = ""
	active_thought = ""
	_refresh_notebook_pages()

	var tween = create_tween()
	tween.tween_interval(0.45)
	tween.finished.connect(_finish_notebook_save_and_resume)


func _finish_notebook_save_and_resume() -> void:
	if shift_finished:
		return

	notebook_open = false
	notebook_overlay.hide()
	thought_bubble.hide()
	_resume_work_after_notebook()


func _resume_work_after_notebook() -> void:
	if shift_finished:
		return

	# The quota has already been running since box one. Resolving the first safe
	# thought only turns on the automatic conveyor pressure; it does not reset score.
	if not auto_route_enabled:
		auto_route_enabled = true
		notebook_hitbox.disabled = true
		_start_next_box()
		return

	# During live work, never manufacture a replacement box here. The conveyor
	# is already progressing behind the notebook. Just restore controls if the
	# current box is still waiting for the player.
	if box_waiting_for_route:
		left_hitbox.disabled = false
		right_hitbox.disabled = false
		notebook_hitbox.disabled = false


# Future home/later notebook behavior: a tested premise can graduate into a
# tested joke. That later notebook view will show tested jokes on the left and
# remaining premises on the right.
func mark_premise_tested(premise_index: int) -> void:
	if premise_index < 0 or premise_index >= premises.size():
		return

	var tested_joke: String = premises[premise_index]
	premises.remove_at(premise_index)
	tested_jokes.append(tested_joke)
