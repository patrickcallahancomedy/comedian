extends GameModule

## DRIVE — Step 1.
##
## This scene intentionally does only one thing right now:
## show the road, Patrick's external car PNG, and LEFT / RIGHT buttons.
##
## Step 2 will make the buttons move the car. Do not add anything else yet.

@onready var player_car: TextureRect = $Road/PlayerCar
@onready var left_button: Button = $Controls/LeftButton
@onready var right_button: Button = $Controls/RightButton


func _ready() -> void:
	module_id = "drive"
	if next_route_id.is_empty():
		next_route_id = "venue"

	# Buttons are deliberately active even though Step 1 gives them no behavior.
	left_button.disabled = false
	right_button.disabled = false
