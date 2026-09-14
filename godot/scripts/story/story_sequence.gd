class_name StorySequence
extends Control

signal finished
signal slide_changed(index: int)

const INTRO_SLIDE: StorySlide = preload("res://data/story/01_darren_intro.tres")

@export_range(0.0, 0.5, 0.01) var fade_seconds: float = 0.16

@onready var card: StoryCard = $StoryCard

var slides: Array[StorySlide] = [INTRO_SLIDE]
var _index := -1
var _transitioning := false
var _finished := false

func _ready() -> void:
	play()

func play() -> void:
	if slides.is_empty():
		push_warning("StorySequence has no slides.")
		return

	_finished = false
	_transitioning = false
	_index = 0
	card.modulate.a = 1.0
	card.present(slides[_index])
	slide_changed.emit(_index)

func advance() -> void:
	if _transitioning or _finished or slides.is_empty():
		return

	var next_index := _index + 1
	if next_index >= slides.size():
		_finished = true
		finished.emit()
		return

	_transition_to(next_index)

func _transition_to(next_index: int) -> void:
	_transitioning = true

	if fade_seconds <= 0.0:
		_swap_slide(next_index)
		_transitioning = false
		return

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate:a", 0.0, fade_seconds)
	tween.tween_callback(_swap_slide.bind(next_index))
	tween.tween_property(card, "modulate:a", 1.0, fade_seconds)
	tween.tween_callback(_finish_transition)

func _swap_slide(next_index: int) -> void:
	_index = next_index
	card.present(slides[_index])
	slide_changed.emit(_index)

func _finish_transition() -> void:
	_transitioning = false

func _input(event: InputEvent) -> void:
	var should_advance := false

	if event is InputEventScreenTouch:
		should_advance = event.pressed
	elif event is InputEventMouseButton:
		should_advance = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_right"):
		should_advance = true

	if should_advance:
		advance()
		get_viewport().set_input_as_handled()
