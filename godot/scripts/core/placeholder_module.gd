extends GameModule

## Generic Skeleton Alpha screen. Duplicate the scene, change the exported text
## and route IDs in the Inspector, then replace its visual children later.

@export_category("Placeholder Screen")
@export var placeholder_title: String = "PLACEHOLDER MODULE"
@export_multiline var placeholder_description: String = "This module has architecture but no finished gameplay yet."

@onready var title_label: Label = $Background/Content/Panel/VBox/TitleLabel
@onready var description_label: Label = $Background/Content/Panel/VBox/DescriptionLabel
@onready var continue_button: Button = $Background/Content/Panel/VBox/ContinueButton


func _ready() -> void:
	title_label.text = placeholder_title
	description_label.text = placeholder_description
	continue_button.grab_focus()


func _on_continue_button_pressed() -> void:
	finish_module({
		"status": "placeholder_complete",
		"title": placeholder_title,
	})
