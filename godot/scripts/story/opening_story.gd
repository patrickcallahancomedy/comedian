extends Control

const LEFT_BOOK_X := -126.0
const RIGHT_BOOK_X := -544.0
const BOOK_Y := -174.0

@onready var story_book: TextureRect = $StoryBook
@onready var content: Control = $Content
@onready var darren: TextureRect = $Content/Darren
@onready var chapter_label: Label = $Content/ChapterLabel
@onready var story_text: RichTextLabel = $Content/StoryText
@onready var continue_button: Button = $Content/ContinueButton

var page := 0
var transitioning := false

var story_pages := [
	"[b]This is Darren.[/b]",
	"[b]Darren wasn’t a comedian.[/b]\nHe wasn’t really trying to become one, either.",
	"His life was mostly routines, obligations, and places he was supposed to be.",
	"But Darren noticed things. Dumb things. Weird things. Little things that made him laugh when nobody else was paying attention.",
	"Most of those thoughts disappeared. [b]Lately, a few had started sticking around.[/b]"
]

func _ready() -> void:
	story_text.bbcode_enabled = true
	continue_button.pressed.connect(_on_continue_pressed)
	_apply_page_content()
	story_book.position = Vector2(_book_x_for_page(page), BOOK_Y)

func _book_x_for_page(page_index: int) -> float:
	return LEFT_BOOK_X if page_index % 2 == 0 else RIGHT_BOOK_X

func _apply_page_content() -> void:
	story_text.text = story_pages[page]
	chapter_label.text = "BEFORE ANY OF THIS"
	darren.visible = page == 0

	if darren.visible:
		chapter_label.position.y = 390.0
		story_text.position.y = 424.0
		story_text.size.y = 222.0
	else:
		chapter_label.position.y = 226.0
		story_text.position.y = 262.0
		story_text.size.y = 360.0

func _show_page_with_turn() -> void:
	transitioning = true
	continue_button.disabled = true

	var fade_out := create_tween()
	fade_out.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade_out.tween_property(content, "modulate:a", 0.0, 0.14)
	await fade_out.finished

	_apply_page_content()

	var target_x := _book_x_for_page(page)
	var direction := signf(target_x - story_book.position.x)
	var overshoot_x := target_x + (18.0 * direction)
	var book_turn := create_tween()
	book_turn.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	book_turn.tween_property(story_book, "position:x", overshoot_x, 0.44)
	book_turn.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	book_turn.tween_property(story_book, "position:x", target_x, 0.14)
	await book_turn.finished

	content.position.y = 12.0
	var fade_in := create_tween()
	fade_in.set_parallel(true)
	fade_in.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade_in.tween_property(content, "modulate:a", 1.0, 0.22)
	fade_in.tween_property(content, "position:y", 0.0, 0.22)
	await fade_in.finished

	continue_button.disabled = false
	transitioning = false

func _on_continue_pressed() -> void:
	if transitioning:
		return

	if page < story_pages.size() - 1:
		page += 1
		await _show_page_with_turn()
	else:
		get_tree().change_scene_to_file("res://scenes/story/boxes_story.tscn")
