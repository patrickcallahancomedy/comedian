extends Control

const PAGES = [
	preload("res://scenes/story/pages/01_darren_intro.tscn"),
	preload("res://scenes/story/pages/02_not_comedian.tscn"),
	preload("res://scenes/story/pages/03_not_trying.tscn"),
]

const ADVANCE_DEBOUNCE_MS := 250

@onready var page_host: Control = $PageHost
var page_index := 0
var current_page: Control
var last_advance_ms := -ADVANCE_DEBOUNCE_MS

@export_file("*.tscn")
var next_scene_path: String = "res://scenes/boxes/boxes_module.tscn"


func _ready() -> void:
	_show_page(0)


func _show_page(index: int) -> void:
	if current_page != null:
		current_page.queue_free()

	page_index = index
	current_page = PAGES[page_index].instantiate()
	page_host.add_child(current_page)


func _input(event: InputEvent) -> void:
	var advance := false

	if event is InputEventMouseButton:
		advance = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		advance = event.pressed
	elif event.is_action_pressed("ui_accept"):
		advance = true

	if not advance:
		return

	var now_ms := Time.get_ticks_msec()
	if now_ms - last_advance_ms < ADVANCE_DEBOUNCE_MS:
		return

	last_advance_ms = now_ms

	var next_page := page_index + 1

	if next_page < PAGES.size():
		_show_page(next_page)
	else:
		get_tree().change_scene_to_file(next_scene_path)
