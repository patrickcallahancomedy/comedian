extends Control

## Fast navigation for building art and modules. Each career jump seeds only the
## minimum state needed for that destination so Patrick never has to replay the
## whole game to work on one scene.

@onready var status_label: Label = $Background/Layout/StatusLabel


func _ready() -> void:
	status_label.text = "DEV JUMPS SEED SAFE PLACEHOLDER STATE"
	$Background/Layout/MinigameLabButton.grab_focus()


func _seed_basics() -> void:
	GameState.reset_new_game()
	GameState.money = 500
	GameState.energy = 100


func _jump(route_id: String) -> void:
	SaveManager.save_game()
	if not SceneRouter.go_to(route_id):
		status_label.text = "UNKNOWN ROUTE: %s" % route_id


func _on_minigame_lab_button_pressed() -> void:
	SceneRouter.go_to("minigame_lab")


func _on_opening_button_pressed() -> void:
	_seed_basics()
	_jump("story_intro")


func _on_boxes_button_pressed() -> void:
	_seed_basics()
	_jump("work")


func _on_first_mic_button_pressed() -> void:
	_seed_basics()
	GameState.mark_milestone("mic_discovered")
	GameState.set_career_phase(GameState.CareerPhase.FIRST_MIC)
	GameState.start_gig("first_mic")
	_jump("venue")


func _on_calendar_button_pressed() -> void:
	GameState.set_career_phase(GameState.CareerPhase.OPEN_MICER)
	GameState.mark_milestone("comedian_begun")
	_jump("calendar")


func _on_regional_button_pressed() -> void:
	_seed_basics()
	GameState.set_career_phase(GameState.CareerPhase.REGIONAL_COMIC)
	GameState.reputation = 20
	GameState.start_gig("regional_gig")
	_jump("travel")


func _on_feature_button_pressed() -> void:
	_seed_basics()
	GameState.set_career_phase(GameState.CareerPhase.WORKING_COMIC)
	GameState.set_job_status(GameState.JobStatus.LEFT_BOXES)
	GameState.reputation = 35
	GameState.start_gig("feature_gig")
	_jump("travel")


func _on_headline_button_pressed() -> void:
	_seed_basics()
	GameState.set_career_phase(GameState.CareerPhase.HEADLINER)
	GameState.set_job_status(GameState.JobStatus.LEFT_BOXES)
	GameState.reputation = 50
	GameState.start_gig("first_headline")
	_jump("venue")


func _on_special_button_pressed() -> void:
	_seed_basics()
	GameState.set_career_phase(GameState.CareerPhase.SPECIAL)
	GameState.set_job_status(GameState.JobStatus.LEFT_BOXES)
	GameState.reputation = 70
	GameState.start_gig("hometown_special")
	_jump("venue")


func _on_ending_button_pressed() -> void:
	_seed_basics()
	GameState.set_job_status(GameState.JobStatus.LEFT_BOXES)
	GameState.mark_milestone("hometown_special_complete")
	_jump("ending")


func _on_main_menu_button_pressed() -> void:
	SceneRouter.go_to("main_menu")
