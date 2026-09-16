extends GameModule

## Reusable story-screen module for Skeleton Alpha.
##
## Patrick can replace every visual child in the matching scene. Keep this root
## script, Module ID, Next Route ID, and the named labels/buttons unless you also
## update these node paths.

@export_category("Story")
@export var story_title: String = "STORY"
@export var pages: Array[String] = [
	"Story page one.",
	"Story page two.",
]

@onready var title_label: Label = $Background/Layout/TitleLabel
@onready var story_text: Label = $Background/Layout/StoryText
@onready var page_counter: Label = $Background/Layout/PageCounter
@onready var continue_button: Button = $Background/Layout/ContinueButton

var page_index: int = 0


func _ready() -> void:
	if pages.is_empty():
		pages.append("EMPTY STORY MODULE")
	_show_page(0)
	continue_button.grab_focus()


func _show_page(index: int) -> void:
	page_index = clampi(index, 0, pages.size() - 1)
	title_label.text = story_title
	story_text.text = pages[page_index]
	page_counter.text = "%d / %d" % [page_index + 1, pages.size()]
	continue_button.text = "CONTINUE" if page_index < pages.size() - 1 else "FINISH"


func _on_continue_button_pressed() -> void:
	if page_index < pages.size() - 1:
		_show_page(page_index + 1)
		return

	finish_module({
		"status": "story_complete",
		"story_title": story_title,
		"pages_seen": pages.size(),
	})
