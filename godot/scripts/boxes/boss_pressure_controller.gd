extends Node

## BOXES-specific glue for the reusable BossWindow scene.
## Troy watches Darren's work pace. Writing in the notebook is allowed, but if
## Darren falls behind quota while Troy is watching, Troy reacts.

@export_range(1.0, 8.0, 0.1) var pressure_thought_lifetime: float = 4.8
@export_range(0.1, 3.0, 0.05) var quota_check_delay: float = 0.85

@onready var boss_window: BossWindow = get_parent() as BossWindow

var _module
var _thought_cycle_id := 0
var _quota_warning_this_watch := false
var _watch_elapsed := 0.0
var _pressure_thought_text := ""


func _ready() -> void:
	_module = boss_window.get_parent()
	boss_window.state_changed.connect(_on_boss_state_changed)
	set_process(true)


func _process(delta: float) -> void:
	if _module == null or not is_instance_valid(_module):
		return

	if boss_window.state != BossWindow.State.WATCHING:
		_watch_elapsed = 0.0
		return

	_watch_elapsed += delta
	if _watch_elapsed < quota_check_delay or _quota_warning_this_watch:
		return

	# Troy does not care that Darren used the notebook. He cares whether the work
	# is slipping. Keep checking during the watch so a missed box can still make
	# him react, while a fast write-and-return stays safe.
	if _module.is_behind_quota_pace():
		_quota_warning_this_watch = true
		_module._get_called_out_for_quota()


func _on_boss_state_changed(new_state: int) -> void:
	if _module == null or not is_instance_valid(_module):
		return

	match new_state:
		BossWindow.State.APPROACH:
			_quota_warning_this_watch = false
			_watch_elapsed = 0.0
			_try_show_pressure_thought()
		BossWindow.State.WATCHING:
			_watch_elapsed = 0.0
		BossWindow.State.ANGRY:
			_quota_warning_this_watch = true
		BossWindow.State.IDLE:
			_quota_warning_this_watch = false
			_watch_elapsed = 0.0


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

	# Ideas can still get away from Darren if he ignores them too long. Troy's
	# presence creates time pressure, but notebook use itself is not a violation.
	_module.active_thought = ""
	_module.thought_bubble.hide()

	if _module.notebook_open:
		_module.notebook_open = false
		_module.notebook_overlay.hide()
		_module._resume_work_after_notebook()
