class_name BossWindow
extends Control

## Reusable supervisor-window visual state machine.
## Visible player-facing sequence:
##   light comes on -> silhouette approaches -> Troy is visible -> angry if caught.
## If Darren stays focused, Troy never enters ANGRY and simply leaves.

signal state_changed(state: int)

enum State {
	IDLE,
	LIGHT,
	APPROACH,
	WATCHING,
	ANGRY,
	LEAVING,
}

@export_range(0.2, 5.0, 0.1) var light_duration: float = 0.9
@export_range(0.5, 8.0, 0.1) var approach_duration: float = 2.2
@export_range(0.5, 15.0, 0.1) var watching_duration: float = 5.5
@export_range(0.3, 5.0, 0.1) var angry_duration: float = 1.4
@export_range(0.1, 2.0, 0.05) var enter_duration: float = 0.8
@export_range(0.1, 2.0, 0.05) var leave_duration: float = 0.65

@onready var backlight: ColorRect = $Backlight
@onready var state_tint: ColorRect = $StateTint
@onready var troy: TextureRect = $Troy

var state: int = State.IDLE
var _state_elapsed := 0.0
var _hidden_x := 0.0
var _approach_x := 0.0
var _watch_x := 0.0
var _motion_tween: Tween
var _light_tween: Tween


func _ready() -> void:
	# Match the actual illuminated supervisor window in the warehouse art.
	# Ratios keep the overlay aligned when the portrait viewport scales.
	anchor_left = 0.25
	anchor_top = 0.105
	anchor_right = 0.735
	anchor_bottom = 0.217
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout_troy)
	_layout_troy()
	_apply_state_style()
	set_process(false)


func _process(delta: float) -> void:
	_state_elapsed += delta

	match state:
		State.LIGHT:
			if _state_elapsed >= light_duration:
				_start_approach()
		State.APPROACH:
			if _state_elapsed >= approach_duration:
				_start_watching()
		State.WATCHING:
			if _state_elapsed >= watching_duration:
				_start_leaving()
		State.ANGRY:
			if _state_elapsed >= angry_duration:
				_start_leaving()


func begin_cycle() -> void:
	if state != State.IDLE:
		return

	_set_state(State.LIGHT)
	_state_elapsed = 0.0
	_layout_troy()
	troy.position.x = _hidden_x
	troy.modulate.a = 0.0
	set_process(true)

	_kill_light_tween()
	_set_light_intensity(0.08)
	_light_tween = create_tween()
	_light_tween.set_trans(Tween.TRANS_QUAD)
	_light_tween.set_ease(Tween.EASE_OUT)
	_light_tween.tween_method(_set_light_intensity, 0.08, 1.0, 0.35)


func cancel_cycle() -> void:
	_kill_motion_tween()
	_kill_light_tween()
	set_process(false)
	_set_state(State.IDLE)
	_layout_troy()
	troy.modulate.a = 0.0
	_set_light_intensity(0.0)


func is_watching() -> bool:
	return state == State.WATCHING


func flash_caught() -> void:
	react_angry()


func react_angry() -> void:
	if state != State.WATCHING:
		return

	_set_state(State.ANGRY)
	_state_elapsed = 0.0
	set_process(true)

	# No separate angry character asset is required for the system to work.
	# The current Troy art gives a clear reactive beat through tint + a short
	# physical snap. An angry pose can replace this later without changing logic.
	_kill_motion_tween()
	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_SINE)
	_motion_tween.tween_property(troy, "position:x", _watch_x - 5.0, 0.06)
	_motion_tween.tween_property(troy, "position:x", _watch_x + 4.0, 0.07)
	_motion_tween.tween_property(troy, "position:x", _watch_x - 2.0, 0.06)
	_motion_tween.tween_property(troy, "position:x", _watch_x, 0.08)


func _start_approach() -> void:
	_set_state(State.APPROACH)
	_state_elapsed = 0.0
	_layout_troy()
	troy.position.x = _hidden_x
	troy.modulate.a = 0.0

	_kill_motion_tween()
	_motion_tween = create_tween()
	_motion_tween.set_parallel(true)
	_motion_tween.set_trans(Tween.TRANS_QUAD)
	_motion_tween.set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(troy, "position:x", _approach_x, enter_duration)
	_motion_tween.tween_property(troy, "modulate:a", 0.88, enter_duration)


func _start_watching() -> void:
	_set_state(State.WATCHING)
	_state_elapsed = 0.0
	set_process(true)

	# Start as the dark approach silhouette, then reveal Troy as he reaches the
	# glass. This is intentionally a state transition, not a new image asset.
	_set_silhouette_mix(1.0)
	_kill_motion_tween()
	_motion_tween = create_tween()
	_motion_tween.set_parallel(true)
	_motion_tween.set_trans(Tween.TRANS_QUAD)
	_motion_tween.set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(troy, "position:x", _watch_x, 0.35)
	_motion_tween.tween_property(troy, "modulate:a", 1.0, 0.25)
	_motion_tween.tween_method(_set_silhouette_mix, 1.0, 0.0, 0.38)


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

	_kill_light_tween()
	_light_tween = create_tween()
	_light_tween.tween_method(_set_light_intensity, _get_light_intensity(), 0.0, leave_duration + 0.15)


func _finish_cycle() -> void:
	_set_state(State.IDLE)
	_layout_troy()
	troy.modulate.a = 0.0
	_set_light_intensity(0.0)


func _set_state(new_state: int) -> void:
	if state == new_state:
		_apply_state_style()
		return

	state = new_state
	_apply_state_style()
	state_changed.emit(state)


func _apply_state_style() -> void:
	match state:
		State.LIGHT:
			state_tint.color = Color(0.92, 0.69, 0.32, 0.05)
			_set_troy_shader(Color(0.10, 0.085, 0.07, 1.0), 1.0, 0.0)
		State.APPROACH:
			state_tint.color = Color(0.83, 0.56, 0.24, 0.07)
			_set_light_intensity(1.0)
			_set_troy_shader(Color(0.08, 0.07, 0.065, 1.0), 1.0, 0.0)
		State.WATCHING:
			state_tint.color = Color(0.35, 0.25, 0.18, 0.035)
			_set_light_intensity(1.0)
			_set_troy_shader(Color(0.16, 0.12, 0.10, 1.0), 0.0, 0.0)
		State.ANGRY:
			state_tint.color = Color(0.82, 0.12, 0.08, 0.24)
			_set_light_intensity(1.15)
			_set_troy_shader(Color(0.58, 0.09, 0.06, 1.0), 0.0, 0.42)
		State.LEAVING:
			state_tint.color = Color(0.38, 0.28, 0.20, 0.03)
			_set_troy_shader(Color(0.16, 0.12, 0.10, 1.0), 0.0, 0.12)
		_:
			state_tint.color = Color(0.0, 0.0, 0.0, 0.0)
			_set_troy_shader(Color(0.10, 0.09, 0.08, 1.0), 1.0, 0.0)


func _set_troy_shader(tint: Color, silhouette_mix: float, tint_mix: float) -> void:
	var shader_material := troy.material as ShaderMaterial
	if shader_material == null:
		return
	shader_material.set_shader_parameter("tint", tint)
	shader_material.set_shader_parameter("silhouette_mix", silhouette_mix)
	shader_material.set_shader_parameter("tint_mix", tint_mix)


func _set_silhouette_mix(value: float) -> void:
	var shader_material := troy.material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter("silhouette_mix", value)


func _set_light_intensity(value: float) -> void:
	var shader_material := backlight.material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter("intensity", value)


func _get_light_intensity() -> float:
	var shader_material := backlight.material as ShaderMaterial
	if shader_material == null:
		return 0.0
	return float(shader_material.get_shader_parameter("intensity"))


func _layout_troy() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return

	# Troy's full-body art is oversized and clipped by the glass so only his
	# head/upper torso appears. Source art remains untouched and replaceable.
	var visual_height := maxf(size.y * 3.35, 250.0)
	var visual_width := visual_height * 0.585
	troy.size = Vector2(visual_width, visual_height)
	troy.position.y = -size.y * 0.06
	troy.pivot_offset = troy.size * 0.5

	_hidden_x = size.x + visual_width * 0.08
	_approach_x = size.x - visual_width * 0.30
	_watch_x = (size.x - visual_width) * 0.5

	match state:
		State.IDLE, State.LIGHT:
			troy.position.x = _hidden_x
		State.APPROACH:
			if troy.modulate.a <= 0.01:
				troy.position.x = _approach_x
		State.WATCHING, State.ANGRY:
			troy.position.x = _watch_x


func _kill_motion_tween() -> void:
	if _motion_tween != null:
		_motion_tween.kill()
		_motion_tween = null


func _kill_light_tween() -> void:
	if _light_tween != null:
		_light_tween.kill()
		_light_tween = null
