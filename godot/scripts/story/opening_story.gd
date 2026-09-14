extends Control

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

func _apply_page_content() -> void:
	story_text.text = story_pages[page]
	chapter_label.text = "BEFORE ANY OF THIS"
	darren.visible = page == 0

	if darren.visible:
		chapter_label.position.y = 42.0
		story_text.position.y = 500.0
		story_text.size.y = 150.0
		story_text.add_theme_font_size_override("normal_font_size", 24)
	else:
		chapter_label.position.y = 150.0
		story_text.position.y = 210.0
		story_text.size.y = 360.0
		story_text.add_theme_font_size_override("normal_font_size", 28)

func _show_next_page() -> void:
	transitioning = true
	continue_button.disabled = true

	var fade_out := create_tween()
	fade_out.set_parallel(true)
	fade_out.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade_out.tween_property(content, "modulate:a", 0.0, 0.16)
	fade_out.tween_property(content, "position:x", -18.0, 0.16)
	await fade_out.finished

	_apply_page_content()
	content.position.x = 18.0

	var fade_in := create_tween()
	fade_in.set_parallel(true)
	fade_in.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade_in.tween_property(content, "modulate:a", 1.0, 0.24)
	fade_in.tween_property(content, "position:x", 0.0, 0.24)
	await fade_in.finished

	continue_button.disabled = false
	transitioning = false

func _on_continue_pressed() -> void:
	if transitioning:
		return

	if page < story_pages.size() - 1:
		page += 1
		await _show_next_page()
	else:
		get_tree().change_scene_to_file("res://scenes/story/boxes_story.tscn")
