extends GameModule

## Reusable two-choice conversation/decision module.
## Configure copy, milestones, and destination routes in the Inspector.

@export_category("Conversation")
@export var speaker_name: String = "DARREN"
@export_multiline var prompt_text: String = "A choice goes here."

@export_category("Option A")
@export var option_a_text: String = "OPTION A"
@export var option_a_milestone: String = ""
@export var option_a_next_route: String = ""

@export_category("Option B")
@export var option_b_text: String = "OPTION B"
@export var option_b_milestone: String = ""
@export var option_b_next_route: String = ""

@onready var speaker_label: Label = $Background/Layout/SpeakerLabel
@onready var prompt_label: Label = $Background/Layout/PromptLabel
@onready var option_a_button: Button = $Background/Layout/OptionAButton
@onready var option_b_button: Button = $Background/Layout/OptionBButton


func _ready() -> void:
	speaker_label.text = speaker_name
	prompt_label.text = prompt_text
	option_a_button.text = option_a_text
	option_b_button.text = option_b_text
	option_a_button.grab_focus()


func _choose(choice_id: String, choice_text: String, milestone: String, route_id: String) -> void:
	if not milestone.is_empty():
		GameState.mark_milestone(milestone)
	if not route_id.is_empty():
		next_route_id = route_id

	finish_module({
		"status": "choice_complete",
		"choice_id": choice_id,
		"choice_text": choice_text,
	})


func _on_option_a_button_pressed() -> void:
	_choose("a", option_a_text, option_a_milestone, option_a_next_route)


func _on_option_b_button_pressed() -> void:
	_choose("b", option_b_text, option_b_milestone, option_b_next_route)
