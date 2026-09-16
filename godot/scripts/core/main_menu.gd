extends Control

## Skeleton Alpha title screen. New Game and Continue are intentionally simple
## so save/load can be tested before final menu art exists.

@onready var continue_button: Button = $Background/Layout/ContinueButton
@onready var status_label: Label = $Background/Layout/StatusLabel


func _ready() -> void:
	continue_button.disabled = not SaveManager.has_save()
	status_label.text = "SKELETON ALPHA — NEW GAME TO ENDING IS WIRED"
	$Background/Layout/NewGameButton.grab_focus()


func _on_new_game_button_pressed() -> void:
	SaveManager.delete_save()
	GameState.reset_new_game()
	SaveManager.save_game()
	SceneRouter.go_to("story_intro")


func _on_continue_button_pressed() -> void:
	if not SaveManager.load_game():
		status_label.text = "SAVE COULD NOT BE LOADED"
		return
	if not SceneRouter.resume_saved_route():
		status_label.text = "SAVED ROUTE IS NO LONGER VALID"


func _on_developer_button_pressed() -> void:
	SceneRouter.go_to("dev_menu")
