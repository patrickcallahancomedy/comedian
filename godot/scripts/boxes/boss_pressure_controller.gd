extends Node

## BOXES-specific glue for the reusable BossWindow scene.
## Keeps the boss visual state machine separate from the gameplay consequence.

@export_range(1.0, 8.0, 0.1) var pressure_thought_lifetime: float = 3.2

@onready var boss_window: BossWindow = get_parent() as BossWindow

var _module
var _thought_cycle_id := 0
var _caught_this_watch := false
var _pressure_thought_text := ""


func _ready() -> void:
	_module = boss_window.get_parent().get_parent()
	boss_window.state_changed.connect(_on_boss_state_changed)
	set_process(true)


func _process(_delta: float) -> void:
	if _module == null or not is_instance_valid(_module):
		return

	# Opening the notebook while Troy is fully watching counts as getting
	# distracted. If WRITE IT DOWN was already pressed during the approach,
	# that counts as catching the idea in time and we let that save finish.
	if (
		boss_window.state == BossWindow.State.WATCHING
		and _module.notebook_open
		and _module.pending_save_text == ""
		and not _caught_this_watch
	):
		_caught_this_watch = true
		_module._get_caught_writing()


func _on_boss_state_changed(new_state: int) -> void:
	if _module == null or not is_instance_valid(_module):
		return

	match new_state:
		BossWindow.State.APPROACH:
			_caught_this_watch = false
			_try_show_pressure_thought()
		BossWindow.State.WATCHING:
			# Existing BoxesModule logic also listens for WATCHING. Marking the
			# thought as shown during APPROACH prevents it from appearing twice.
			pass
		BossWindow.State.ANGRY:
			_caught_this_watch = true
		BossWindow.State.IDLE:
			_caught_this_watch = false


func _try_show_pressure_thought() -> void:
	if _module.shift_finished or not _module.auto_route_enabled or _module.second_thought_shown:
		return

	_module.second_thought_shown = true
	_module._show_pressure_thought()
	_pressure_thought_text = _module.active_thought
	_thought_cycle_id += 1
	_expire_pressure_thought(_thought_cycle_id)


func _expire_pressure_thought(cycle_id: int) -> void:
	await get_tree().create_timer(pressure_thought_lifetime).timeout

	if cycle_id != _thought_cycle_id:
		return
	if _module == null or not is_instance_valid(_module):
		return
	if _module.pending_save_text != "":
		return
	if _pressure_thought_text == "" or _module.active_thought != _pressure_thought_text:
		return

	# This is the important pressure: an idea can genuinely get away from Darren.
	# Waiting for Troy to leave is not always an option.
	_module.active_thought = ""
	_module.thought_bubble.hide()

	if _module.notebook_open:
		_module.notebook_open = false
		_module.notebook_overlay.hide()
		_module._resume_work_after_notebook()
