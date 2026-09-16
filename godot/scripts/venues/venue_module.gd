extends GameModule

## Generic venue-arrival shell. Specific clubs/mics can duplicate this scene and
## change the exported venue information without changing the architecture.

@export_category("Venue")
@export var venue_id: String = "local_venue"
@export var venue_name: String = "LOCAL VENUE"
@export_range(1, 120, 1) var set_length_minutes: int = 5
@export_range(0, 10000, 1) var expected_pay: int = 0

@export_category("Routes")
@export var stage_route_id: String = "placeholder"
@export var leave_route_id: String = "calendar"

@onready var venue_name_label: Label = $Background/Layout/VenueNameLabel
@onready var details_label: Label = $Background/Layout/DetailsLabel
@onready var perform_button: Button = $Background/Layout/PerformButton


func _ready() -> void:
	GameState.discover_venue(venue_id)
	venue_name_label.text = venue_name
	details_label.text = "SET: %d MIN    PAY: $%d" % [set_length_minutes, expected_pay]
	perform_button.grab_focus()


func _on_perform_button_pressed() -> void:
	next_route_id = stage_route_id
	finish_module({
		"status": "ready_for_stage",
		"venue_id": venue_id,
		"venue_name": venue_name,
		"set_length_minutes": set_length_minutes,
		"expected_pay": expected_pay,
	})


func _on_leave_button_pressed() -> void:
	GameState.advance_day()
	SaveManager.save_game()
	next_route_id = leave_route_id
	finish_module({
		"status": "left_venue",
		"venue_id": venue_id,
	})
