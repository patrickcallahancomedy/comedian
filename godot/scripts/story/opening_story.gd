extends Control

@onready var left_page: TextureRect = $LeftPage
@onready var right_page: TextureRect = $RightPage
@onready var story_text: RichTextLabel = $StoryText
@onready var continue_button: Button = $ContinueButton

var page := 0

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
	show_page()

func show_page() -> void:
	story_text.text = story_pages[page]

	var show_left_page := page % 2 == 0
	left_page.visible = show_left_page
	right_page.visible = not show_left_page

func _on_continue_pressed() -> void:
	if page < story_pages.size() - 1:
		page += 1
		show_page()
	else:
		get_tree().change_scene_to_file("res://scenes/story/boxes_story.tscn")
