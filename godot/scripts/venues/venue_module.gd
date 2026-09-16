extends GameModule

## Generic venue-arrival shell. If GameState has an active GigData booking, this
## scene reads it automatically. Specific venues can later duplicate this scene
## and replace all visual children without changing the booking/stage handoff.

@export_category("Fallback Venue")
@export var venue_id: String = "local_venue"
@export var venue_name: String = "LOCAL VENUE"
@export_range(1, 120, 1) var set_length_minutes: int = 5
@export_range(0, 10000, 1) var expected_pay: int = 0

@export_category("Routes")
@export var stage_route_id: String = "stage"
@export var leave_route_id: String = "calendar"

@onready var venue_name_label: Label = $Background/Layout/VenueNameLabel
@onready var details_label: Label = $Background/Layout/DetailsLabel
@onready var arrival_text: Label = $Background/Layout/ArrivalText
@onready var perform_button: Button = $Background/Layout/PerformButton

var gig: GigData


func _ready() -> void:
	gig = GigDatabase.get_gig(GameState.current_gig_id)
	if gig != null:
		venue_id = gig.venue_id
		venue_name = gig.venue_name
		set_length_minutes = gig.set_length_minutes
		expected_pay = gig.pay

	GameState.discover_venue(venue_id)
	venue_name_label.text = venue_name
	details_label.text = "SET: %d MIN    PAY: $%d" % [set_length_minutes, expected_pay]

	if gig != null and GameState.reputation < gig.reputation_required:
		perform_button.disabled = true
		arrival_text.text = "BOOKING GATE: REP %d REQUIRED — CURRENT REP %d" % [
			gig.reputation_required,
			GameState.reputation,
		]
	else:
		arrival_text.text = "ARRIVAL / SIGN-UP / BACKSTAGE / SOCIAL PLACEHOLDER"
		perform_button.grab_focus()


func _on_perform_button_pressed() -> void:
	next_route_id = stage_route_id
	finish_module({
		"status": "ready_for_stage",
		"gig_id": GameState.current_gig_id,
		"venue_id": venue_id,
		"venue_name": venue_name,
		"set_length_minutes": set_length_minutes,
		"expected_pay": expected_pay,
	})


func _on_leave_button_pressed() -> void:
	GameState.clear_current_gig()
	GameState.advance_day()
	SaveManager.save_game()
	next_route_id = leave_route_id
	finish_module({
		"status": "left_venue",
		"venue_id": venue_id,
	})
