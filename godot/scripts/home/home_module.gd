extends GameModule

## Skeleton home hub. The finished room can replace every visual child later.
## For now it proves that home can read persistent material and affect life state.

@export_range(0, 100, 1) var rest_energy_gain: int = 20

@onready var status_label: Label = $Background/Layout/StatusLabel
@onready var notebook_label: Label = $Background/Layout/NotebookLabel
@onready var rest_button: Button = $Background/Layout/RestButton


func _ready() -> void:
	_refresh()
	rest_button.grab_focus()


func _refresh() -> void:
	status_label.text = "WEEK %d — %s\nENERGY %d    MONEY $%d" % [
		GameState.week,
		GameState.get_day_name().to_upper(),
		GameState.energy,
		GameState.money,
	]
	notebook_label.text = (
		"NOTEBOOK\nPremises: %d\nTested bits: %d\nReliable jokes: %d\nBurned: %d"
		% [
			GameState.premises.size(),
			GameState.tested_bits.size(),
			GameState.reliable_jokes.size(),
			GameState.burned_material.size(),
		]
	)


func _on_rest_button_pressed() -> void:
	GameState.energy = clampi(GameState.energy + rest_energy_gain, 0, 100)
	GameState.advance_day()
	SaveManager.save_game()
	finish_module({
		"status": "rested",
		"energy_gain": rest_energy_gain,
	})


func _on_back_button_pressed() -> void:
	finish_module({"status": "left_home"})
