extends GameModule

## Central day-selection screen for the post-prologue game loop.
## GameState owns day/week; this module only lets the player choose what to do.

@export_category("Activity Routes")
@export var work_route_id: String = "work"
@export var home_route_id: String = "home"
@export var comedy_route_id: String = "venue"
@export var travel_route_id: String = "travel"

@onready var day_label: Label = $Background/Layout/DayLabel
@onready var state_label: Label = $Background/Layout/StateLabel
@onready var work_button: Button = $Background/Layout/WorkButton
@onready var home_button: Button = $Background/Layout/HomeButton
@onready var comedy_button: Button = $Background/Layout/ComedyButton
@onready var travel_button: Button = $Background/Layout/TravelButton
@onready var skip_day_button: Button = $Background/Layout/SkipDayButton


func _ready() -> void:
	_refresh()
	work_button.grab_focus()


func _refresh() -> void:
	day_label.text = "WEEK %d — %s" % [GameState.week, GameState.get_day_name().to_upper()]
	state_label.text = "MONEY $%d    ENERGY %d    REP %d\nCAREER: %s" % [
		GameState.money,
		GameState.energy,
		GameState.reputation,
		GameState.get_career_phase_name().to_upper(),
	]

	work_button.disabled = GameState.job_status == GameState.JobStatus.LEFT_BOXES
	work_button.text = "WORK" if not work_button.disabled else "BOXES — LEFT JOB"

	# The first time the main calendar appears, COMEDY advances the compressed
	# Open-Micer placeholder. Later this button uses the normal venue route.
	if (
		GameState.career_phase == GameState.CareerPhase.OPEN_MICER
		and GameState.has_milestone("comedian_begun")
		and not GameState.has_milestone("open_micer_phase_complete")
	):
		comedy_button.text = "COMEDY — CONTINUE SKELETON CAREER"
	else:
		comedy_button.text = "COMEDY"
	comedy_button.disabled = false


func _go_to_activity(activity_id: String, route_id: String) -> void:
	next_route_id = route_id
	finish_module({
		"status": "activity_selected",
		"activity": activity_id,
		"day": GameState.get_day_name(),
		"week": GameState.week,
	})


func _on_work_button_pressed() -> void:
	if work_button.disabled:
		return
	_go_to_activity("work", work_route_id)


func _on_home_button_pressed() -> void:
	_go_to_activity("home", home_route_id)


func _on_comedy_button_pressed() -> void:
	if (
		GameState.career_phase == GameState.CareerPhase.OPEN_MICER
		and GameState.has_milestone("comedian_begun")
		and not GameState.has_milestone("open_micer_phase_complete")
	):
		_go_to_activity("comedy", "open_micer")
	else:
		_go_to_activity("comedy", comedy_route_id)


func _on_travel_button_pressed() -> void:
	_go_to_activity("travel", travel_route_id)


func _on_skip_day_button_pressed() -> void:
	GameState.advance_day()
	SaveManager.save_game()
	_refresh()
