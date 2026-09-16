extends GameModule

## Central day-selection screen for the post-prologue game loop.
## This scene does not own the calendar. GameState owns day/week; this module
## only lets the player choose what to do next.

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
	state_label.text = "MONEY $%d    ENERGY %d    REP %d" % [
		GameState.money,
		GameState.energy,
		GameState.reputation,
	]

	# Darren can always inspect the comedy path in Skeleton Alpha. Individual
	# story gates can disable or relabel this later without changing the router.
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
	_go_to_activity("work", work_route_id)


func _on_home_button_pressed() -> void:
	_go_to_activity("home", home_route_id)


func _on_comedy_button_pressed() -> void:
	_go_to_activity("comedy", comedy_route_id)


func _on_travel_button_pressed() -> void:
	_go_to_activity("travel", travel_route_id)


func _on_skip_day_button_pressed() -> void:
	GameState.advance_day()
	SaveManager.save_game()
	_refresh()
