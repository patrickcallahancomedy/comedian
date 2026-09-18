extends Control

## Phone-friendly front end for the MinigameLab autoload. This scene contains no
## duplicate minigames: each button launches the exact route used by the game.

@onready var status_label: Label = $Background/Margin/Scroll/Layout/StatusLabel
@onready var result_panel: PanelContainer = $Background/Margin/Scroll/Layout/ResultPanel
@onready var result_label: Label = $Background/Margin/Scroll/Layout/ResultPanel/ResultMargin/ResultLabel
@onready var replay_button: Button = $Background/Margin/Scroll/Layout/ReplayButton


func _ready() -> void:
	_refresh_result()
	$Background/Margin/Scroll/Layout/CarToMicButton.grab_focus()


func _lab() -> Node:
	return get_node("/root/MinigameLab")


func _start_test(test_id: String) -> void:
	status_label.text = "LOADING %s..." % str(_lab().call("get_test_label", test_id))
	if not bool(_lab().call("begin_test", test_id)):
		status_label.text = "COULD NOT START LAB TEST."


func _refresh_result() -> void:
	var lab := _lab()
	var last_test_id := str(lab.get("last_test_id"))
	replay_button.disabled = last_test_id.is_empty()

	if last_test_id.is_empty():
		result_panel.hide()
		status_label.text = "TEST A REAL MODULE WITHOUT TOUCHING YOUR SAVE."
		return

	result_panel.show()
	result_label.text = str(lab.call("get_last_summary"))
	status_label.text = "LAB RUN COMPLETE — REAL SAVE RESTORED."


func _on_car_to_mic_button_pressed() -> void:
	_start_test("car_to_mic")


func _on_car_tired_button_pressed() -> void:
	_start_test("car_tired")


func _on_boxes_normal_button_pressed() -> void:
	_start_test("boxes_normal")


func _on_boxes_tired_button_pressed() -> void:
	_start_test("boxes_tired")


func _on_stage_first_mic_button_pressed() -> void:
	_start_test("stage_first_mic")


func _on_stage_paid_set_button_pressed() -> void:
	_start_test("stage_paid_set")


func _on_travel_regional_button_pressed() -> void:
	_start_test("travel_regional")


func _on_replay_button_pressed() -> void:
	status_label.text = "REPLAYING..."
	if not bool(_lab().call("replay_last_test")):
		status_label.text = "NOTHING TO REPLAY."


func _on_back_button_pressed() -> void:
	get_node("/root/SceneRouter").call("go_to", "dev_menu")
