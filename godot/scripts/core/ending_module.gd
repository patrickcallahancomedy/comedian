extends Control

## Skeleton Alpha ending / epilogue. Final art, writing, and credits can replace
## the visual children later without changing the completed career state.

@onready var recap_label: Label = $Background/Layout/RecapLabel


func _ready() -> void:
	GameState.set_career_phase(GameState.CareerPhase.COMPLETE)
	GameState.mark_milestone("game_complete")
	SaveManager.save_game()

	recap_label.text = (
		"DARREN MADE IT TO THE HOMETOWN SPECIAL.\n\n"
		+ "WEEK: %d\nREPUTATION: %d\nMONEY: $%d\n"
		+ "PREMISES: %d\nTESTED BITS: %d\nRELIABLE JOKES: %d\n\n"
		+ "SKELETON ALPHA COMPLETE"
	) % [
		GameState.week,
		GameState.reputation,
		GameState.money,
		GameState.premises.size(),
		GameState.tested_bits.size(),
		GameState.reliable_jokes.size(),
	]
	$Background/Layout/MainMenuButton.grab_focus()


func _on_main_menu_button_pressed() -> void:
	SceneRouter.go_to("main_menu")


func _on_play_again_button_pressed() -> void:
	SaveManager.delete_save()
	GameState.reset_new_game()
	SaveManager.save_game()
	SceneRouter.go_to("story_intro")
