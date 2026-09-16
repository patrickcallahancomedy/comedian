extends GameModule

## Generic travel shell. An active GigData booking automatically supplies the
## destination and costs. Final travel gameplay can replace the visuals and
## interaction without changing this handoff.

@export_category("Fallback Destination")
@export var destination_id: String = "destination"
@export var destination_name: String = "DESTINATION"
@export var arrival_route_id: String = "venue"
@export var cancel_route_id: String = "calendar"

@export_category("Fallback Cost")
@export_range(0, 10000, 1) var travel_cost: int = 0
@export_range(0, 100, 1) var energy_cost: int = 5

@onready var destination_label: Label = $Background/Layout/DestinationLabel
@onready var cost_label: Label = $Background/Layout/CostLabel
@onready var feedback_label: Label = $Background/Layout/FeedbackLabel
@onready var travel_button: Button = $Background/Layout/TravelButton

var gig: GigData


func _ready() -> void:
	gig = GigDatabase.get_gig(GameState.current_gig_id)
	if gig != null:
		destination_id = gig.venue_id
		destination_name = "%s — %s" % [gig.venue_name, gig.city]
		travel_cost = gig.travel_cost
		energy_cost = gig.energy_cost

	destination_label.text = destination_name
	_refresh_cost_text()
	feedback_label.text = ""
	travel_button.grab_focus()


func _refresh_cost_text() -> void:
	cost_label.text = "COST $%d    ENERGY -%d\nYOU HAVE $%d    ENERGY %d" % [
		travel_cost,
		energy_cost,
		GameState.money,
		GameState.energy,
	]


func _on_travel_button_pressed() -> void:
	if GameState.money < travel_cost:
		feedback_label.text = "NOT ENOUGH MONEY"
		return

	GameState.add_money(-travel_cost)
	GameState.change_energy(-energy_cost)
	GameState.mark_milestone("visited_" + destination_id)
	SaveManager.save_game()

	next_route_id = arrival_route_id
	finish_module({
		"status": "travel_complete",
		"gig_id": GameState.current_gig_id,
		"destination_id": destination_id,
		"destination_name": destination_name,
		"cost": travel_cost,
		"energy_cost": energy_cost,
	})


func _on_cancel_button_pressed() -> void:
	GameState.clear_current_gig()
	next_route_id = cancel_route_id
	finish_module({"status": "travel_cancelled"})
