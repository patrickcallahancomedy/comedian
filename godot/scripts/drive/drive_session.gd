extends GameModule

## DRIVE v0.8 — owns arrival and replay; driving presentation stays isolated in CityMap.
## Consequences apply once, only on CONTINUE. Replay is a free practice run.
@export var departure_clock_minutes := 19 * 60 + 16
@export var signup_close_clock_minutes := 19 * 60 + 45
var trip_result: Dictionary = {}
var handed_off := false

@onready var city: Control = $CityMap
@onready var arrival: PanelContainer = $Arrival
@onready var arrival_text: Label = $Arrival/Layout/ArrivalText

func _ready() -> void:
	module_id = "drive"
	next_route_id = "venue"
	arrival.hide()
	city.trip_finished.connect(_on_arrival)
	$Arrival/Layout/Replay.pressed.connect(_replay)
	$Arrival/Layout/Continue.pressed.connect(_continue_trip)
	# Steering uses key events, so UI focus cannot consume arrow keys or Space.
	for button in $TouchControls.get_children():
		button.focus_mode = Control.FOCUS_NONE

func _on_arrival(result: Dictionary) -> void:
	if not trip_result.is_empty():
		return
	trip_result = result.duplicate(true)
	var minutes := maxi(1, ceili(float(result.real_drive_seconds) * 0.45))
	var clock := departure_clock_minutes + minutes
	trip_result["arrival_clock_minutes"] = clock
	trip_result["arrival_minutes_before_signup"] = signup_close_clock_minutes - clock
	var timing := "You have a few minutes before signup closes."
	if clock >= signup_close_clock_minutes:
		timing = "You're late. Better get inside."
	arrival_text.text = "PARKED — %d:%02d PM\n\n%s" % [posmod(clock / 60 - 1, 12) + 1, clock % 60, timing]
	arrival.show()

func _replay() -> void:
	get_tree().reload_current_scene()

func _continue_trip() -> void:
	if handed_off or trip_result.is_empty():
		return
	handed_off = true
	GameState.change_energy(-2)
	GameState.change_gas(-3)
	GameState.change_car_condition(-2 * int(trip_result.bumps))
	GameState.change_stress(int(trip_result.missed_turns) + 2 * int(trip_result.bumps))
	GameState.increment_history("drives_completed")
	GameState.increment_history("missed_turns", int(trip_result.missed_turns))
	for key in ["arrival_clock_minutes", "arrival_minutes_before_signup"]:
		GameState.night_context[key] = trip_result[key]
	GameState.night_context["drive_real_seconds"] = trip_result.real_drive_seconds
	GameState.night_context["drive_missed_turns"] = trip_result.missed_turns
	finish_module(trip_result)
