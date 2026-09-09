extends Control

const ThoughtBubbleAsset = preload("res://scripts/boxes/thought_bubble_asset.gd")
const THOUGHT_BUBBLE_PATH := "res://assets/boxes/thought_bubble.png"

@onready var left_button_art: TextureRect = $GameplayLayer/LeftButton
@onready var right_button_art: TextureRect = $GameplayLayer/RightButton

@onready var left_hitbox: Button = $GameplayLayer/LeftHitbox
@onready var right_hitbox: Button = $GameplayLayer/RightHitbox

@onready var belt: TextureRect = $GameplayLayer/Belt
@onready var box_current: TextureRect = $GameplayLayer/BoxCurrent
@onready var box_routed: TextureRect = $GameplayLayer/BoxRouted
@onready var destination_label: Label = $GameplayLayer/BoxCurrent/DestinationTag/DestinationLabel
@onready var route_feedback: Label = $GameplayLayer/RouteFeedback
@onready var thought_bubble: TextureRect = $HUDLayer/ThoughtBubble

var belt_start_position: Vector2
var box_spawn_position: Vector2
var box_ready_position: Vector2
var current_destination := "left"
var correct_routes := 0
var wrong_routes := 0
var boxes_routed := 0
var first_thought_shown := false

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
	_load_thought_bubble_texture()
	_assign_destination()
	route_feedback.hide()
	thought_bubble.hide()

	left_hitbox.button_down.connect(_on_left_down)
	left_hitbox.button_up.connect(_on_left_up)

	right_hitbox.button_down.connect(_on_right_down)
	right_hitbox.button_up.connect(_on_right_up)
	thought_bubble.gui_input.connect(_on_thought_bubble_input)

	box_routed.hide()

	left_hitbox.disabled = true
	right_hitbox.disabled = true

	var tween = create_tween()
	tween.tween_property(box_current, "position", box_ready_position, 0.5)
	tween.finished.connect(_on_box_ready)


func _load_thought_bubble_texture() -> void:
	# Web builds materialize the real PNG before Godot exports the project.
	# Local/editor builds can still fall back to the embedded PNG data.
	if ResourceLoader.exists(THOUGHT_BUBBLE_PATH):
		var texture := load(THOUGHT_BUBBLE_PATH) as Texture2D
		if texture != null:
			thought_bubble.texture = texture
			return

	var png_bytes := Marshalls.base64_to_raw(ThoughtBubbleAsset.PNG_BASE64)
	var image := Image.new()
	var error := image.load_png_from_buffer(png_bytes)

	if error != OK:
		push_error("Could not load thought bubble art.")
		return

	thought_bubble.texture = ImageTexture.create_from_image(image)


func _assign_destination() -> void:
	current_destination = ["left", "right"].pick_random()
	destination_label.text = current_destination.to_upper()


func _on_box_ready() -> void:
	left_hitbox.disabled = false
	right_hitbox.disabled = false


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
	left_hitbox.disabled = true
	right_hitbox.disabled = true
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
	box_current.show()
	box_current.position = box_spawn_position
	_assign_destination()

	left_hitbox.disabled = true
	right_hitbox.disabled = true

	var tween = create_tween()
	tween.tween_property(box_current, "position", box_ready_position, 0.5)
	tween.finished.connect(_on_box_ready)


func _show_first_thought() -> void:
	left_hitbox.disabled = true
	right_hitbox.disabled = true
	thought_bubble.modulate.a = 0.0
	thought_bubble.show()

	var tween = create_tween()
	tween.tween_property(thought_bubble, "modulate:a", 1.0, 0.2)


func _on_thought_bubble_input(event: InputEvent) -> void:
	if not thought_bubble.visible:
		return

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_dismiss_first_thought()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_dismiss_first_thought()


func _dismiss_first_thought() -> void:
	thought_bubble.hide()
	_start_next_box()
