extends Control

@onready var story_text: RichTextLabel = $StoryMargin/StoryLayout/StoryText
@onready var continue_button: Button = $StoryMargin/StoryLayout/ContinueButton

var page := 0

var story_pages := [
	"[b]This is BOXES.[/b]",
	"This is where Darren works.",
	"Lately, Darren’s been getting ideas at work and writing them down in his notebook.",
	"His boss, Troy, has started noticing.",
	"[b]Try to get through the shift, save your ideas, and don’t get caught.[/b]",
	"[b]Clock in.[/b]"
]

func _ready() -> void:
	story_text.bbcode_enabled = true
	continue_button.pressed.connect(_on_continue_pressed)
	show_page()

func show_page() -> void:
	story_text.text = story_pages[page]

	if page == story_pages.size() - 1:
		continue_button.text = "CLOCK IN"
	else:
		continue_button.text = "CONTINUE"
		
func _on_continue_pressed() -> void:
	if page < story_pages.size() - 1:
		page += 1
		show_page()
	else:
		get_tree().change_scene_to_file("res://scenes/boxes/boxes_module.tscn")
