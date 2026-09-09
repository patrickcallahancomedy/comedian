extends Control

const THOUGHT_BUBBLE_TEXTURE = preload("res://assets/boxes/E45CC4E6-9696-43E3-8029-2CAAF946E8B9.png")
const FIRST_THOUGHT := "I wonder why they call it a lunch break when I never stop being tired."

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

@onready var thought_bubble: TextureRect = $HUDLayer/ThoughtBubble
@onready var thought_text: Label = $HUDLayer/ThoughtBubble/ThoughtText
@onready var notebook_overlay: Control = $HUDLayer/NotebookOverlay
@onready var tested_ideas_label: Label = $HUDLayer/NotebookOverlay/TestedIdeas
@onready var premises_list_label: Label = $HUDLayer/NotebookOverlay/PremisesList
@onready var new_thought_title: Label = $HUDLayer/NotebookOverlay/NewThoughtTitle
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
var boxes_routed := 0
var ideas_saved := 0
var first_thought_shown := false
var active_thought := ""
var pending_save_text := ""
var notebook_open := false
var box_waiting_for_route := false

# Right page = saved premises. Left page = ideas that have been tested later.
# The thought itself is temporary and only enters premises if WRITE IT DOWN is pressed.
var premises: Array[String] = []
var tested_ideas: Array[String] = []

const ROUTE_DURATION := 1.0
const BELT_SHIFT_RATIO := 0.06
const PRACTICE_BOXES_BEFORE_THOUGHT := 3

var left_normal = preload("res://assets/boxes/left_button.png")
var left_pressed = preload("res://assets/boxes/left_button_pressed.png")

var right_normal = preload("res://assets/boxes/right_button.png")
var right_pressed = preload("res://assets/boxes/right_button_pressed.png")


func _ready() -> void:
	belt_start_position = belt.position
	box_spawn_position = box_current.position
	box_ready_position = box_routed.position
	active_thought_start_position = active_thought_label.position
	thought_bubble.texture = THOUGHT_BUBBLE_TEXTURE
	thought_text.text = FIRST_THOUGHT
	_assign_destination()

	route_feedback.hide()
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

	var tween = create_tween()
	tween.tween_property(box_current, "position", box_ready_position, 0.5)
	tween.finished.connect(_on_box_ready)


func _assign_destination() -> void:
	current_destination = ["left", "right"].pick_random()
	destination_label.text = current_destination.to_upper()


func _on_box_ready() -> void:
	box_waiting_for_route = true
	left_hitbox.disabled = false
	right_hitbox.disabled = false
	notebook_hitbox.disabled = false


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


func _route_box(direction: String) -> void:
	if notebook_open:
		return

	box_waiting_for_route = false
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

	# Match the old HTML trick: the frame stays fixed while the oversized
	# belt surface shifts only about 6% inside the cropped game frame.
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

	# The opening is intentionally quiet: after a few practice boxes, stop
	# the conveyor and let Darren's first thought become the player's focus.
	if boxes_routed >= PRACTICE_BOXES_BEFORE_THOUGHT and not first_thought_shown:
		first_thought_shown = true
		_show_first_thought()
		return

	_start_next_box()


func _start_next_box() -> void:
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


func _show_first_thought() -> void:
	active_thought = FIRST_THOUGHT
	left_hitbox.disabled = true
	right_hitbox.disabled = true
	notebook_hitbox.disabled = false
	thought_bubble.modulate.a = 0.0
	thought_bubble.show()

	var tween = create_tween()
	tween.tween_property(thought_bubble, "modulate:a", 1.0, 0.2)


func _on_thought_bubble_input(event: InputEvent) -> void:
	if not thought_bubble.visible or notebook_open:
		return

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_open_notebook()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_open_notebook()


func _open_notebook() -> void:
	if notebook_open:
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
	tested_ideas_label.text = _format_idea_list(tested_ideas, "Nothing tested yet.")
	premises_list_label.text = _format_idea_list(premises, "No premises saved yet.")

	active_thought_label.position = active_thought_start_position
	active_thought_label.modulate.a = 1.0
	write_idea_button.disabled = false

	if active_thought.is_empty():
		new_thought_title.hide()
		active_thought_label.hide()
		write_idea_button.hide()
	else:
		new_thought_title.show()
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

	# Thoughts are temporary. If the player closes the notebook without
	# writing one down, that thought is gone and never becomes a premise.
	if not active_thought.is_empty():
		active_thought = ""
		thought_bubble.hide()
		notebook_hitbox.disabled = true
		_start_next_box()
		return

	if box_waiting_for_route:
		left_hitbox.disabled = false
		right_hitbox.disabled = false
		notebook_hitbox.disabled = false


func _write_active_thought() -> void:
	if active_thought.is_empty() or not pending_save_text.is_empty():
		return

	pending_save_text = active_thought
	write_idea_button.disabled = true

	# Simple first-pass save animation: the temporary thought slides upward
	# toward the premises list and fades, so it feels like it is entering the notebook.
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(active_thought_label, "position:y", premises_list_label.position.y, 0.35)
	tween.tween_property(active_thought_label, "modulate:a", 0.0, 0.35)
	tween.finished.connect(_finish_write_active_thought)


func _finish_write_active_thought() -> void:
	premises.append(pending_save_text)
	ideas_saved += 1
	print("Ideas saved: ", ideas_saved)

	pending_save_text = ""
	active_thought = ""
	_refresh_notebook_pages()

	# Leave the newly saved premise visible for a beat before returning to work.
	var tween = create_tween()
	tween.tween_interval(0.35)
	tween.finished.connect(_finish_notebook_save_and_resume)


func _finish_notebook_save_and_resume() -> void:
	notebook_open = false
	notebook_overlay.hide()
	thought_bubble.hide()
	notebook_hitbox.disabled = true
	_start_next_box()


# Later modules can call this after a premise has been tried on someone or onstage.
func mark_premise_tested(premise_index: int) -> void:
	if premise_index < 0 or premise_index >= premises.size():
		return

	var tested_idea := premises.pop_at(premise_index)
	tested_ideas.append(tested_idea)
