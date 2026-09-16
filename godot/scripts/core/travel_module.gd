extends GameModule

## Generic travel shell. Configure destination/costs in the Inspector.
## The finished travel minigame can replace the visuals and internal interaction
## without changing how the rest of the game hands off to the destination.

@export_category("Destination")
@export var destination_id: String = "destination"
@export var destination_name: String = "DESTINATION"
@export var arrival_route_id: String = "venue"
@export var cancel_route_id: String = "calendar"

@export_category("Cost")
@export_range(0, 10000, 1) var travel_cost: int = 0
@export_range(0, 100, 1) var energy_cost: int = 5

@onready var destination_label: Label = $Background/Layout/DestinationLabel
@onready var cost_label: Label = $Background/Layout/CostLabel
@onready var feedback_label: Label = $Background/Layout/FeedbackLabel
@onready var travel_button: Button = $Background/Layout/TravelButton


func _ready() -> void:
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

	GameState.money -= travel_cost
	GameState.energy = clampi(GameState.energy - energy_cost, 0, 100)
	GameState.mark_milestone("visited_" + destination_id)
	SaveManager.save_game()

	next_route_id = arrival_route_id
	finish_module({
		"status": "travel_complete",
		"destination_id": destination_id,
		"destination_name": destination_name,
		"cost": travel_cost,
		"energy_cost": energy_cost,
	})


func _on_cancel_button_pressed() -> void:
	next_route_id = cancel_route_id
	finish_module({"status": "travel_cancelled"})
