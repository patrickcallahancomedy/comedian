extends GameModule

## One reusable placeholder screen for major career milestones.
## Copy and progression live in data/skeleton_flow.gd so the scene stays simple
## and Patrick can freely rebuild the visuals beneath this root.

@export var allow_skeleton_gate_bypass: bool = true

@onready var phase_label: Label = $Background/Layout/PhaseLabel
@onready var title_label: Label = $Background/Layout/TitleLabel
@onready var description_label: Label = $Background/Layout/DescriptionLabel
@onready var gate_label: Label = $Background/Layout/GateLabel
@onready var continue_button: Button = $Background/Layout/ContinueButton

var event_data: Dictionary = {}
var route_id: String = ""


func _ready() -> void:
	route_id = GameState.current_route_id
	event_data = SkeletonFlow.get_event(route_id)

	if event_data.is_empty():
		title_label.text = "MISSING SKELETON EVENT"
		description_label.text = "No event data exists for route: %s" % route_id
		gate_label.text = "This route safely returns to the title screen."
		next_route_id = "main_menu"
		continue_button.grab_focus()
		return

	module_id = route_id
	phase_label.text = "CAREER: %s" % GameState.get_career_phase_name().to_upper()
	title_label.text = str(event_data.get("title", route_id.to_upper()))
	description_label.text = str(event_data.get("description", ""))
	_refresh_gate_text()
	continue_button.grab_focus()


func _refresh_gate_text() -> void:
	var required_milestone := str(event_data.get("required_milestone", ""))
	if required_milestone.is_empty():
		gate_label.text = "SKELETON ALPHA — STRUCTURAL PLACEHOLDER"
		return

	if GameState.has_milestone(required_milestone):
		gate_label.text = "PROGRESSION GATE MET: %s" % required_milestone
	else:
		gate_label.text = "GATE NOT MET: %s" % required_milestone
		if allow_skeleton_gate_bypass:
			gate_label.text += "\nSkeleton Alpha allows bypass so the full route cannot dead-end."
		else:
			continue_button.disabled = true


func _on_continue_button_pressed() -> void:
	var required_milestone := str(event_data.get("required_milestone", ""))
	if not required_milestone.is_empty() and not GameState.has_milestone(required_milestone):
		if not allow_skeleton_gate_bypass:
			return
		GameState.mark_milestone("skeleton_gate_bypass_" + route_id)

	var phase_name := str(event_data.get("career_phase", ""))
	if not phase_name.is_empty():
		var phase_value := int(GameState.CareerPhase.get(phase_name, -1))
		if phase_value >= 0:
			GameState.set_career_phase(phase_value)

	var job_name := str(event_data.get("job_status", ""))
	if not job_name.is_empty():
		var job_value := int(GameState.JobStatus.get(job_name, -1))
		if job_value >= 0:
			GameState.set_job_status(job_value)

	var milestone := str(event_data.get("milestone", ""))
	if not milestone.is_empty():
		GameState.mark_milestone(milestone)

	var reputation_floor := int(event_data.get("reputation_floor", 0))
	if GameState.reputation < reputation_floor:
		GameState.reputation = reputation_floor

	var gig_id := str(event_data.get("gig_id", ""))
	if not gig_id.is_empty():
		GameState.start_gig(gig_id)

	next_route_id = str(event_data.get("next_route", "main_menu"))
	SaveManager.save_game()
	finish_module({
		"status": "career_event_complete",
		"route_id": route_id,
		"title": title_label.text,
	})
