extends Control

@onready var exterior: TextureRect = $Exterior
@onready var darren_shadow: TextureRect = $DarrenShadow
@onready var darren: TextureRect = $Darren
@onready var time_label: Label = $TimeLabel
@onready var main_text: Label = $MainText
@onready var sub_text: Label = $SubText
@onready var tap_hint: Label = $TapHint
@onready var fade: ColorRect = $Fade

var beat := 0
var transitioning := false
var ready_for_input := false

var beats := [
	{
		"title": "This is Darren.",
		"subtitle": "He works here.",
		"show_darren": true,
		"camera_scale": 1.025,
		"camera_y": 0.0
	},
	{
		"title": "He's been coming to BOXES for years.",
		"subtitle": "Long enough for most mornings to feel exactly the same.",
		"show_darren": true,
		"camera_scale": 1.04,
		"camera_y": -4.0
	},
	{
		"title": "Darren wasn't a comedian.",
		"subtitle": "He wasn't trying to become one.",
		"show_darren": true,
		"camera_scale": 1.055,
		"camera_y": -8.0
	},
	{
		"title": "He just noticed things.",
		"subtitle": "Little things. Dumb things. Weird things.",
		"show_darren": false,
		"camera_scale": 1.075,
		"camera_y": -12.0
	},
	{
		"title": "Most of those thoughts disappeared.",
		"subtitle": "Lately, a few had started sticking around.",
		"show_darren": false,
		"camera_scale": 1.09,
		"camera_y": -18.0
	}
]

func _ready() -> void:
	_prepare_scene()
	_play_establishing_shot()

func _prepare_scene() -> void:
	fade.modulate.a = 1.0
	exterior.scale = Vector2(1.01, 1.01)
	exterior.position = Vector2.ZERO
	time_label.modulate.a = 0.0
	main_text.modulate.a = 0.0
	sub_text.modulate.a = 0.0
	tap_hint.modulate.a = 0.0
	darren.visible = false
	darren_shadow.visible = false

func _play_establishing_shot() -> void:
	var opening := create_tween()
	opening.set_parallel(true)
	opening.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	opening.tween_property(fade, "modulate:a", 0.0, 0.85)
	opening.tween_property(exterior, "scale", Vector2(1.02, 1.02), 2.1)
	opening.tween_property(time_label, "modulate:a", 1.0, 0.55).set_delay(0.55)
	await opening.finished
	await get_tree().create_timer(0.55).timeout
	await _show_beat(0, true)

func _show_beat(index: int, first_beat: bool = false) -> void:
	transitioning = true
	ready_for_input = false
	beat = index
	var data: Dictionary = beats[index]

	main_text.text = data["title"]
	sub_text.text = data["subtitle"]
	tap_hint.text = "TAP TO CLOCK IN" if index == beats.size() - 1 else "TAP TO CONTINUE"

	var should_show_darren: bool = data["show_darren"]
	if should_show_darren:
		darren.visible = true
		darren_shadow.visible = true
	else:
		darren.visible = false
		darren_shadow.visible = false

	main_text.position.y = 546.0
	sub_text.position.y = 636.0
	main_text.modulate.a = 0.0
	sub_text.modulate.a = 0.0
	tap_hint.modulate.a = 0.0
	if should_show_darren and first_beat:
		darren.modulate.a = 0.0
		darren_shadow.modulate.a = 0.0
		darren.position.y = 178.0
		darren_shadow.position.y = 184.0

	var target_scale: float = data["camera_scale"]
	var target_y: float = data["camera_y"]
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(exterior, "scale", Vector2(target_scale, target_scale), 0.7)
	tween.tween_property(exterior, "position:y", target_y, 0.7)
	tween.tween_property(main_text, "modulate:a", 1.0, 0.36).set_delay(0.08)
	tween.tween_property(main_text, "position:y", 534.0, 0.36).set_delay(0.08)
	tween.tween_property(sub_text, "modulate:a", 1.0, 0.34).set_delay(0.18)
	tween.tween_property(sub_text, "position:y", 626.0, 0.34).set_delay(0.18)
	tween.tween_property(tap_hint, "modulate:a", 1.0, 0.28).set_delay(0.44)
	if should_show_darren and first_beat:
		tween.tween_property(darren, "modulate:a", 1.0, 0.5)
		tween.tween_property(darren, "position:y", 166.0, 0.5)
		tween.tween_property(darren_shadow, "modulate:a", 0.28, 0.5)
		tween.tween_property(darren_shadow, "position:y", 172.0, 0.5)
	await tween.finished

	transitioning = false
	ready_for_input = true

func _advance() -> void:
	if not ready_for_input or transitioning:
		return
	ready_for_input = false
	transitioning = true

	var out_tween := create_tween()
	out_tween.set_parallel(true)
	out_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	out_tween.tween_property(main_text, "modulate:a", 0.0, 0.22)
	out_tween.tween_property(sub_text, "modulate:a", 0.0, 0.22)
	out_tween.tween_property(tap_hint, "modulate:a", 0.0, 0.16)
	await out_tween.finished

	if beat >= beats.size() - 1:
		await _enter_boxes()
		return

	await _show_beat(beat + 1)

func _enter_boxes() -> void:
	var ending := create_tween()
	ending.set_parallel(true)
	ending.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	ending.tween_property(fade, "modulate:a", 1.0, 0.75)
	ending.tween_property(exterior, "scale", exterior.scale + Vector2(0.025, 0.025), 0.75)
	ending.tween_property(time_label, "modulate:a", 0.0, 0.35)
	ending.tween_property(darren, "modulate:a", 0.0, 0.35)
	ending.tween_property(darren_shadow, "modulate:a", 0.0, 0.35)
	await ending.finished
	get_tree().change_scene_to_file("res://scenes/boxes/boxes_module.tscn")

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_advance()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()
