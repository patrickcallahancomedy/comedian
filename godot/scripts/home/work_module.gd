extends GameModule

## Work shell. It loads the existing BOXES scene without rewriting that scene.
## Patrick's BOXES art/layout remains authoritative while the larger game gets a
## standard module handoff.

const BOXES_SCENE := preload("res://scenes/boxes/boxes_module.tscn")

@onready var menu_panel: Control = $MenuPanel
@onready var job_label: Label = $MenuPanel/Layout/JobLabel
@onready var start_shift_button: Button = $MenuPanel/Layout/StartShiftButton
@onready var boxes_host: Control = $BoxesHost
@onready var result_overlay: Control = $ResultOverlay
@onready var result_label: Label = $ResultOverlay/Panel/Layout/ResultLabel

var boxes_instance: Control
var boxes_result: Dictionary = {}
var result_captured: bool = false
var opening_shift: bool = false


func _ready() -> void:
	boxes_host.hide()
	result_overlay.hide()
	opening_shift = not GameState.has_milestone("opening_boxes_complete")
	_refresh_job_text()
	set_process(true)

	# The locked opening story flows directly into BOXES. Later visits to Work
	# show the normal menu instead.
	if opening_shift and GameState.job_status != GameState.JobStatus.LEFT_BOXES:
		menu_panel.hide()
		call_deferred("_on_start_shift_button_pressed")
	else:
		start_shift_button.grab_focus()


func _refresh_job_text() -> void:
	if GameState.job_status == GameState.JobStatus.LEFT_BOXES:
		job_label.text = "DARREN NO LONGER WORKS AT BOXES."
		start_shift_button.disabled = true
		start_shift_button.text = "NO SHIFT AVAILABLE"
	else:
		job_label.text = "BOXES — DAY SHIFT"
		start_shift_button.disabled = false
		start_shift_button.text = "START SHIFT"


func _on_start_shift_button_pressed() -> void:
	if boxes_instance != null:
		return
	if GameState.job_status == GameState.JobStatus.LEFT_BOXES:
		return

	menu_panel.hide()
	boxes_host.show()
	boxes_instance = BOXES_SCENE.instantiate()
	boxes_host.add_child(boxes_instance)


func _process(_delta: float) -> void:
	if boxes_instance == null or result_captured:
		return
	if not is_instance_valid(boxes_instance):
		return
	if bool(boxes_instance.get("shift_finished")):
		_capture_boxes_result()


func _capture_boxes_result() -> void:
	result_captured = true
	var correct := int(boxes_instance.get("shift_correct_routes"))
	var processed := int(boxes_instance.get("shift_boxes_processed"))
	var missed := int(boxes_instance.get("missed_boxes"))
	var boss_catches := int(boxes_instance.get("boss_catches"))
	var premises_saved := int(boxes_instance.get("premises_saved"))

	# Read the existing result label instead of reaching into BOXES constants.
	# That keeps the wrapper tolerant of future BOXES tuning.
	var boxes_result_label = boxes_instance.get("shift_result_label")
	var quota_met := false
	if boxes_result_label is Label:
		quota_met = boxes_result_label.text.contains("QUOTA MET")

	boxes_result = {
		"status": "boxes_shift_complete",
		"quota_met": quota_met,
		"correct_routes": correct,
		"boxes_processed": processed,
		"missed_boxes": missed,
		"boss_catches": boss_catches,
		"premises_saved": premises_saved,
	}

	result_label.text = (
		"SHIFT COMPLETE\n%d / %d CORRECT\nPREMISES SAVED: %d"
		% [correct, processed, premises_saved]
	)
	result_overlay.show()
	SaveManager.save_game()


func _on_finish_work_button_pressed() -> void:
	if opening_shift:
		GameState.mark_milestone("opening_boxes_complete")
		next_route_id = "lunch"
	else:
		next_route_id = "calendar"

	GameState.advance_day()
	SaveManager.save_game()
	finish_module(boxes_result)


func _on_back_button_pressed() -> void:
	next_route_id = "calendar"
	finish_module({"status": "work_skipped"})
