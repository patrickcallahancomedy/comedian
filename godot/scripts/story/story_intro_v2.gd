extends Control

@onready var exterior: TextureRect = $Exterior
@onready var shade: ColorRect = $Shade
@onready var darren: TextureRect = $Darren
@onready var kicker: Label = $Kicker
@onready var main_text: Label = $MainText
@onready var sub_text: Label = $SubText
@onready var skip_hint: Label = $SkipHint
@onready var fade: ColorRect = $Fade

var intro_running := true
var finishing := false
var can_skip := false

func _ready() -> void:
	_prepare_intro()
	_run_intro()

func _prepare_intro() -> void:
	fade.modulate.a = 1.0
	exterior.scale = Vector2(1.06, 1.06)
	shade.color.a = 0.30
	darren.visible = false
	darren.modulate.a = 0.0
	kicker.modulate.a = 0.0
	main_text.modulate.a = 0.0
	sub_text.modulate.a = 0.0
	skip_hint.modulate.a = 0.0

func _run_intro() -> void:
	var opening := create_tween()
	opening.set_parallel(true)
	opening.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	opening.tween_property(fade, "modulate:a", 0.0, 0.75)
	opening.tween_property(exterior, "scale", Vector2.ONE, 8.0)

	await get_tree().create_timer(0.55).timeout
	if finishing:
		return
	can_skip = true
	_fade_in(skip_hint, 0.30)
	await _show_line("Darren wasn't a comedian.", "")
	await get_tree().create_timer(1.55).timeout
	if finishing:
		return
	await _hide_line()

	darren.visible = true
	darren.position.y += 12.0
	var darren_in := create_tween()
	darren_in.set_parallel(true)
	darren_in.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	darren_in.tween_property(darren, "modulate:a", 1.0, 0.42)
	darren_in.tween_property(darren, "position:y", darren.position.y - 12.0, 0.42)
	await _show_line("He wasn't trying to become one.", "")
	await get_tree().create_timer(1.55).timeout
	if finishing:
		return
	await _hide_line()

	var darren_out := create_tween()
	darren_out.set_parallel(true)
	darren_out.tween_property(darren, "modulate:a", 0.0, 0.32)
	darren_out.tween_property(shade, "color:a", 0.18, 0.32)
	kicker.text = "MONDAY  •  6:47 AM"
	_fade_in(kicker, 0.28)
	await _show_line("He worked at BOXES.", "Most days looked about the same.")
	await get_tree().create_timer(1.55).timeout
	if finishing:
		return
	_finish_intro()

func _show_line(title: String, subtitle: String) -> void:
	main_text.text = title
	sub_text.text = subtitle
	main_text.position.y = 562.0
	sub_text.position.y = 668.0
	main_text.modulate.a = 0.0
	sub_text.modulate.a = 0.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(main_text, "modulate:a", 1.0, 0.30)
	tween.tween_property(main_text, "position:y", 550.0, 0.30)
	if not subtitle.is_empty():
		tween.tween_property(sub_text, "modulate:a", 1.0, 0.30).set_delay(0.08)
		tween.tween_property(sub_text, "position:y", 656.0, 0.30).set_delay(0.08)
	await tween.finished

func _hide_line() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(main_text, "modulate:a", 0.0, 0.22)
	tween.tween_property(sub_text, "modulate:a", 0.0, 0.22)
	await tween.finished

func _fade_in(item: CanvasItem, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(item, "modulate:a", 1.0, duration)

func _finish_intro() -> void:
	if finishing:
		return
	finishing = true
	intro_running = false
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(fade, "modulate:a", 1.0, 0.55)
	tween.tween_property(skip_hint, "modulate:a", 0.0, 0.20)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/boxes/boxes_module.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if not intro_running or not can_skip or finishing:
		return
	if event is InputEventScreenTouch and event.pressed:
		_finish_intro()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_finish_intro()
