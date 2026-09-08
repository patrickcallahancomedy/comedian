extends Control

@onready var left_button_art: TextureRect = $GameplayLayer/LeftButton
@onready var right_button_art: TextureRect = $GameplayLayer/RightButton

@onready var left_hitbox: Button = $GameplayLayer/LeftHitbox
@onready var right_hitbox: Button = $GameplayLayer/RightHitbox

@onready var box_current: TextureRect = $GameplayLayer/BoxCurrent
@onready var box_routed: TextureRect = $GameplayLayer/BoxRouted
@onready var destination_label: Label = $GameplayLayer/BoxCurrent/DestinationTag/DestinationLabel

var box_spawn_position: Vector2
var box_ready_position: Vector2
var current_destination := "left"

var left_normal = preload("res://assets/boxes/left_button.png")
var left_pressed = preload("res://assets/boxes/left_button_pressed.png")

var right_normal = preload("res://assets/boxes/right_button.png")
var right_pressed = preload("res://assets/boxes/right_button_pressed.png")


func _ready() -> void:
	box_spawn_position = box_current.position
	box_ready_position = box_routed.position
	_assign_destination()
	
	left_hitbox.button_down.connect(_on_left_down)
	left_hitbox.button_up.connect(_on_left_up)

	right_hitbox.button_down.connect(_on_right_down)
	right_hitbox.button_up.connect(_on_right_up)
	
	box_routed.hide()

	left_hitbox.disabled = true
	right_hitbox.disabled = true

	var tween = create_tween()
	tween.tween_property(box_current, "position", box_ready_position, 0.5)
	tween.finished.connect(_on_box_ready)
	

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

	box_current.hide()
	box_routed.show()

	var target_x: float

	if direction == "left":
		target_x = -120
	else:
		target_x = 480

	var tween = create_tween()
	tween.tween_property(box_routed, "position:x", target_x, 0.6)
	tween.finished.connect(_reset_box)

func _reset_box() -> void:
	box_routed.hide()
	box_routed.position = box_ready_position

	box_current.show()
	box_current.position = box_spawn_position
	_assign_destination()

	left_hitbox.disabled = true
	right_hitbox.disabled = true

	var tween = create_tween()
	tween.tween_property(box_current, "position", box_ready_position, 0.5)
	tween.finished.connect(_on_box_ready)
