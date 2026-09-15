class_name BossWindow
extends Control

## BossWindow controls only the VISUAL sequence in the supervisor window.
## Gameplay rules (quota checks, thoughts, consequences) stay outside this file.
##
## Visual flow:
##   LIGHT -> APPROACH -> WATCHING -> LEAVING
##                         |
##                         -> ANGRY -> LEAVING

signal state_changed(state: int)

enum State {
	IDLE,
	LIGHT,
	APPROACH,
	WATCHING,
	ANGRY,
	LEAVING,
}

@export_category("Timing")
@export_range(0.2, 5.0, 0.1) var light_duration: float = 1.0
@export_range(0.5, 8.0, 0.1) var approach_duration: float = 3.4
@export_range(0.5, 15.0, 0.1) var watching_duration: float = 5.5
@export_range(0.3, 5.0, 0.1) var angry_duration: float = 2.2
@export_range(0.1, 1.5, 0.05) var fade_duration: float = 0.35
@export_range(0.1, 2.0, 0.05) var leave_duration: float = 0.65

@onready var warning_glow: ColorRect = $WarningGlow
@onready var troy_silhouette: TextureRect = $TroySilhouette
@onready var troy: TextureRect = $Troy
@onready var angry_tint: ColorRect = $AngryTint

var state: int = State.IDLE
var _sequence: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_visuals()


## Starts one complete Troy visit.
func begin_cycle() -> void:
	if state != State.IDLE:
		return

	_stop_sequence()
	_reset_visuals()
	_set_state(State.LIGHT)

	warning_glow.show()
	warning_glow.modulate.a = 0.0

	_sequence = create_tween()
	_sequence.set_trans(Tween.TRANS_QUAD)
	_sequence.set_ease(Tween.EASE_IN_OUT)

	# 1. The office/window lights up first. This is the earliest warning.
	_sequence.tween_property(warning_glow, "modulate:a", 1.0, fade_duration)
	_sequence.tween_interval(maxf(0.0, light_duration - fade_duration))

	# 2. Use Patrick's real silhouette asset. No shader-generated silhouette.
	_sequence.tween_callback(_show_approach)
	_sequence.tween_property(troy_silhouette, "modulate:a", 1.0, fade_duration)
	_sequence.tween_interval(maxf(0.0, approach_duration - fade_duration))

	# 3. Replace the silhouette with Troy himself.
	_sequence.tween_callback(_show_watching)
	_sequence.tween_property(troy_silhouette, "modulate:a", 0.0, fade_duration)
	_sequence.parallel().tween_property(troy, "modulate:a", 1.0, fade_duration)
	_sequence.tween_callback(_hide_silhouette)
	_sequence.tween_interval(watching_duration)

	# 4. If gameplay did not make him angry, he simply leaves.
	_sequence.tween_callback(_show_leaving)
	_sequence.tween_property(troy, "modulate:a", 0.0, leave_duration)
	_sequence.parallel().tween_property(warning_glow, "modulate:a", 0.0, leave_duration)
	_sequence.tween_callback(_finish_cycle)


## Gameplay can call this while Troy is WATCHING.
func react_angry() -> void:
	if state != State.WATCHING:
		return

	_stop_sequence()
	_set_state(State.ANGRY)

	troy_silhouette.hide()
	troy.show()
	troy.modulate.a = 1.0
	warning_glow.show()
	warning_glow.modulate.a = 1.0
	angry_tint.show()
	angry_tint.modulate.a = 0.0

	_sequence = create_tween()
	_sequence.set_trans(Tween.TRANS_QUAD)
	_sequence.set_ease(Tween.EASE_IN_OUT)
	_sequence.tween_property(angry_tint, "modulate:a", 1.0, 0.12)
	_sequence.tween_interval(maxf(0.0, angry_duration - 0.12))
	_sequence.tween_callback(_show_leaving)
	_sequence.tween_property(troy, "modulate:a", 0.0, leave_duration)
	_sequence.parallel().tween_property(warning_glow, "modulate:a", 0.0, leave_duration)
	_sequence.parallel().tween_property(angry_tint, "modulate:a", 0.0, leave_duration)
	_sequence.tween_callback(_finish_cycle)


## Compatibility alias for older callers.
func flash_caught() -> void:
	react_angry()


func cancel_cycle() -> void:
	_stop_sequence()
	_reset_visuals()
	_set_state(State.IDLE)


func is_watching() -> bool:
	return state == State.WATCHING


func _show_approach() -> void:
	_set_state(State.APPROACH)
	troy_silhouette.show()
	troy_silhouette.modulate.a = 0.0


func _show_watching() -> void:
	_set_state(State.WATCHING)
	troy.show()
	troy.modulate.a = 0.0


func _hide_silhouette() -> void:
	troy_silhouette.hide()


func _show_leaving() -> void:
	_set_state(State.LEAVING)


func _finish_cycle() -> void:
	_sequence = null
	_reset_visuals()
	_set_state(State.IDLE)


func _reset_visuals() -> void:
	warning_glow.hide()
	warning_glow.modulate.a = 1.0

	troy_silhouette.hide()
	troy_silhouette.modulate.a = 1.0

	troy.hide()
	troy.modulate.a = 1.0

	angry_tint.hide()
	angry_tint.modulate.a = 1.0


func _set_state(new_state: int) -> void:
	if state == new_state:
		return

	state = new_state
	state_changed.emit(state)


func _stop_sequence() -> void:
	if _sequence != null:
		_sequence.kill()
		_sequence = null
