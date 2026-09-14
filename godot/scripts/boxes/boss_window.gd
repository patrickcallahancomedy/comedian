class_name BossWindow
extends Control

## Reusable supervisor window interaction.
## The window stays part of the warehouse background. Troy is a separate layer
## clipped to the window opening so the art can be repositioned/tuned in Godot.

signal state_changed(state: int)

enum State {
	IDLE,
	WARNING,
	WATCHING,
	LEAVING,
}

@export_range(0.5, 10.0, 0.1) var warning_duration: float = 3.5
@export_range(0.5, 15.0, 0.1) var watching_duration: float = 6.0
@export_range(0.1, 2.0, 0.05) var enter_duration: float = 0.65
@export_range(0.1, 2.0, 0.05) var leave_duration: float = 0.65

@onready var state_tint: ColorRect = $StateTint
@onready var troy: TextureRect = $Troy

var state: int = State.IDLE
var _state_elapsed := 0.0
var _hidden_x := 0.0
var _warning_x := 0.0
var _watch_x := 0.0
var _motion_tween: Tween


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout_troy)
	_layout_troy()
	_apply_state_style()
	set_process(false)


func _process(delta: float) -> void:
	_state_elapsed += delta

	if state == State.WARNING and _state_elapsed >= warning_duration:
		_start_watching()
	elif state == State.WATCHING and _state_elapsed >= watching_duration:
		_start_leaving()


func begin_cycle() -> void:
	if state != State.IDLE:
		return

	_set_state(State.WARNING)
	_state_elapsed = 0.0
	_layout_troy()
	troy.position.x = _hidden_x
	troy.modulate.a = 0.0
	set_process(true)

	_kill_motion_tween()
	_motion_tween = create_tween()
	_motion_tween.set_parallel(true)
	_motion_tween.set_trans(Tween.TRANS_QUAD)
	_motion_tween.set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(troy, "position:x", _warning_x, enter_duration)
	_motion_tween.tween_property(troy, "modulate:a", 0.72, enter_duration)


func cancel_cycle() -> void:
	_kill_motion_tween()
	set_process(false)
	_set_state(State.IDLE)
	_layout_troy()
	troy.modulate.a = 0.0


func is_watching() -> bool:
	return state == State.WATCHING


func flash_caught() -> void:
	if state != State.WATCHING:
		return

	var resting_color := state_tint.color
	state_tint.color = Color(0.78, 0.16, 0.12, 0.28)

	var tween := create_tween()
	tween.tween_interval(0.12)
	tween.tween_property(state_tint, "color", resting_color, 0.32)


func _start_watching() -> void:
	_set_state(State.WATCHING)
	_state_elapsed = 0.0

	_kill_motion_tween()
	_motion_tween = create_tween()
	_motion_tween.set_parallel(true)
	_motion_tween.set_trans(Tween.TRANS_QUAD)
	_motion_tween.set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(troy, "position:x", _watch_x, 0.35)
	_motion_tween.tween_property(troy, "modulate:a", 0.96, 0.25)


func _start_leaving() -> void:
	_set_state(State.LEAVING)
	_state_elapsed = 0.0
	set_process(false)

	_kill_motion_tween()
	_motion_tween = create_tween()
	_motion_tween.set_parallel(true)
	_motion_tween.set_trans(Tween.TRANS_QUAD)
	_motion_tween.set_ease(Tween.EASE_IN)
	_motion_tween.tween_property(troy, "position:x", _hidden_x, leave_duration)
	_motion_tween.tween_property(troy, "modulate:a", 0.0, leave_duration)
	_motion_tween.finished.connect(_finish_cycle)


func _finish_cycle() -> void:
	_set_state(State.IDLE)
	_layout_troy()
	troy.modulate.a = 0.0


func _set_state(new_state: int) -> void:
	if state == new_state:
		_apply_state_style()
		return

	state = new_state
	_apply_state_style()
	state_changed.emit(state)


func _apply_state_style() -> void:
	match state:
		State.WARNING:
			state_tint.color = Color(0.83, 0.56, 0.24, 0.08)
			_set_troy_tint(Color(0.16, 0.12, 0.10, 0.90))
		State.WATCHING:
			state_tint.color = Color(0.55, 0.20, 0.16, 0.10)
			_set_troy_tint(Color(0.09, 0.08, 0.08, 0.96))
		State.LEAVING:
			state_tint.color = Color(0.38, 0.28, 0.20, 0.04)
			_set_troy_tint(Color(0.13, 0.11, 0.10, 0.82))
		_:
			state_tint.color = Color(0.0, 0.0, 0.0, 0.0)
			_set_troy_tint(Color(0.14, 0.12, 0.11, 0.0))


func _set_troy_tint(color: Color) -> void:
	var shader_material := troy.material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter("tint", color)


func _layout_troy() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return

	# Troy's full-body character art is deliberately oversized, then clipped by
	# the window. That lets only his head/upper torso appear without editing art.
	var visual_height := maxf(size.y * 2.9, 250.0)
	var visual_width := visual_height * 0.585
	troy.size = Vector2(visual_width, visual_height)
	troy.position.y = -size.y * 0.08

	_hidden_x = size.x + visual_width * 0.08
	_warning_x = size.x - visual_width * 0.42
	_watch_x = (size.x - visual_width) * 0.5

	match state:
		State.IDLE:
			troy.position.x = _hidden_x
		State.WARNING:
			if troy.modulate.a <= 0.01:
				troy.position.x = _warning_x
		State.WATCHING:
			troy.position.x = _watch_x


func _kill_motion_tween() -> void:
	if _motion_tween != null:
		_motion_tween.kill()
		_motion_tween = null
