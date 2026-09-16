extends GameModule

## Universal comedy-performance shell for Skeleton Alpha.
## The finished stage minigame can replace everything below this root later.
## This script only owns the shared handoff: booking -> performance result -> career state.

@export_category("Skeleton Performance Tuning")
@export_range(0, 100, 1) var base_score: int = 45
@export_range(0, 25, 1) var reliable_joke_bonus: int = 10
@export_range(0, 20, 1) var tested_bit_bonus: int = 5
@export_range(0, 10, 1) var premise_bonus: int = 2

@onready var gig_label: Label = $Background/Layout/GigLabel
@onready var details_label: Label = $Background/Layout/DetailsLabel
@onready var material_label: Label = $Background/Layout/MaterialLabel
@onready var result_label: Label = $Background/Layout/ResultLabel
@onready var perform_button: Button = $Background/Layout/PerformButton
@onready var continue_button: Button = $Background/Layout/ContinueButton

var gig: GigData
var performance_result: Dictionary = {}
var performed := false


func _ready() -> void:
	gig = GigDatabase.get_gig(GameState.current_gig_id)
	continue_button.hide()
	result_label.text = ""
	_refresh_screen()
	perform_button.grab_focus()


func _refresh_screen() -> void:
	if gig == null:
		gig_label.text = "OPEN STAGE"
		details_label.text = "NO BOOKING DATA — GENERIC STAGE TEST"
	else:
		gig_label.text = gig.gig_title
		details_label.text = "%s — %s\nSET: %d MIN    PAY: $%d" % [
			gig.venue_name,
			gig.city,
			gig.set_length_minutes,
			gig.pay,
		]

	material_label.text = (
		"MATERIAL\nPREMISES: %d    TESTED BITS: %d    RELIABLE JOKES: %d"
		% [GameState.premises.size(), GameState.tested_bits.size(), GameState.reliable_jokes.size()]
	)


func _on_perform_button_pressed() -> void:
	if performed:
		return
	performed = true

	var score := clampi(
		base_score
		+ GameState.reliable_jokes.size() * reliable_joke_bonus
		+ GameState.tested_bits.size() * tested_bit_bonus
		+ GameState.premises.size() * premise_bonus
		+ mini(GameState.reputation, 20),
		0,
		100
	)

	# One piece of material advances per Skeleton Alpha performance. This is
	# intentionally simple infrastructure, not the final joke-testing design.
	if not GameState.premises.is_empty():
		GameState.promote_premise_to_tested_bit(0)
	elif score >= 60 and not GameState.tested_bits.is_empty():
		GameState.promote_tested_bit_to_reliable_joke(0)

	var pay := 0
	var energy_cost := 5
	var milestone := ""
	if gig != null:
		pay = gig.pay
		energy_cost = gig.energy_cost
		milestone = gig.completion_milestone

	var reputation_gain := maxi(1, int(score / 20))
	GameState.add_money(pay)
	GameState.change_energy(-energy_cost)
	GameState.add_reputation(reputation_gain)
	if not milestone.is_empty():
		GameState.mark_milestone(milestone)

	performance_result = {
		"status": "performance_complete",
		"gig_id": GameState.current_gig_id,
		"score": score,
		"pay": pay,
		"reputation_gain": reputation_gain,
	}

	result_label.text = "SET COMPLETE\nCROWD RESULT: %d / 100\nREP +%d    PAY $%d" % [
		score,
		reputation_gain,
		pay,
	]
	perform_button.hide()
	continue_button.show()
	continue_button.grab_focus()
	_refresh_screen()
	SaveManager.save_game()


func _on_continue_button_pressed() -> void:
	if not performed:
		return

	var route_after := "calendar"
	if gig != null and not gig.next_route_id.is_empty():
		route_after = gig.next_route_id

	GameState.clear_current_gig()
	GameState.advance_day()
	SaveManager.save_game()
	next_route_id = route_after
	finish_module(performance_result)
