extends SceneTree

## Deterministic stateful fuzz tester for the real BOXES scene.
##
## Run from the repository root:
##   godot --headless --path godot --fixed-fps 120 \
##     --script res://tests/boxes_fuzz.gd -- --runs=1000 --seed=1
##
## Every run has its own seed. A failure prints that seed and the recent action
## trace, so the exact playthrough can be reproduced with --runs=1.

const BOXES_SCENE := preload("res://scenes/boxes/boxes_module.tscn")
const DEFAULT_RUNS := 1000
const DEFAULT_BASE_SEED := 1
const MAX_STEPS_PER_RUN := 300
const TRACE_LIMIT := 60
const SIMULATION_TIME_SCALE := 12.0

var _active_seed := 0
var _trace: Array[String] = []
var _failure_message := ""


func _initialize() -> void:
	call_deferred("_run_suite")


func _run_suite() -> void:
	var options := _read_options()
	var run_count: int = options.runs
	var base_seed: int = options.seed
	var original_time_scale := Engine.time_scale
	Engine.time_scale = SIMULATION_TIME_SCALE

	print("BOXES FUZZ START runs=%d base_seed=%d" % [run_count, base_seed])

	for run_index in range(run_count):
		var run_seed := base_seed + run_index
		var passed := await _run_seed(run_seed)
		if not passed:
			Engine.time_scale = original_time_scale
			_print_failure()
			quit(1)
			return

		if (run_index + 1) % 100 == 0 or run_index + 1 == run_count:
			print("BOXES FUZZ progress=%d/%d last_seed=%d" % [
				run_index + 1,
				run_count,
				run_seed,
			])

	Engine.time_scale = original_time_scale
	print("BOXES FUZZ PASS runs=%d seeds=%d..%d" % [
		run_count,
		base_seed,
		base_seed + run_count - 1,
	])
	quit(0)


func _read_options() -> Dictionary:
	var options := {
		"runs": DEFAULT_RUNS,
		"seed": DEFAULT_BASE_SEED,
	}

	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--runs="):
			options.runs = maxi(1, int(argument.trim_prefix("--runs=")))
		elif argument.begins_with("--seed="):
			options.seed = int(argument.trim_prefix("--seed="))

	return options


func _run_seed(run_seed: int) -> bool:
	_active_seed = run_seed
	_trace.clear()
	_failure_message = ""

	# BOXES uses the global random generator for destinations. The driver uses a
	# separate RNG so changing game randomness does not change the action stream.
	seed(run_seed)
	var driver_rng := RandomNumberGenerator.new()
	driver_rng.seed = run_seed ^ 0x5F3759DF

	var game = BOXES_SCENE.instantiate()
	root.add_child(game)
	_record("scene-created")

	if not await _advance_frames(game, 8):
		await _destroy_game(game)
		return false

	var thought_wait_steps := 0
	var notebook_wait_steps := 0
	var step := 0

	while not game.shift_finished and step < MAX_STEPS_PER_RUN:
		step += 1
		var action := _choose_action(game, driver_rng, thought_wait_steps, notebook_wait_steps)
		_perform_action(game, action)
		_record("step=%d action=%s state=%s" % [step, action, _state_summary(game)])

		if game.thought_bubble.visible and not game.notebook_open:
			thought_wait_steps += 1
		else:
			thought_wait_steps = 0

		if game.notebook_open:
			notebook_wait_steps += 1
		else:
			notebook_wait_steps = 0

		# Variable pauses exercise input on arrival/exit tween boundaries, before
		# deadlines, exactly at deadlines, and after forced missed-box routing.
		var frames_to_advance := driver_rng.randi_range(1, 9)
		if action == "idle-long":
			frames_to_advance = driver_rng.randi_range(20, 34)

		if not await _advance_frames(game, frames_to_advance):
			await _destroy_game(game)
			return false

	if not game.shift_finished:
		_fail("shift did not finish within %d driver steps" % MAX_STEPS_PER_RUN)
		await _destroy_game(game)
		return false

	if not _validate(game):
		await _destroy_game(game)
		return false

	# Keep attacking the completed state. Counters and the result must remain
	# immutable even if late releases or notebook clicks arrive after game-over.
	var completed_snapshot := _completion_snapshot(game)
	for post_action in ["left", "right", "double-route", "open-notebook", "write", "close"]:
		_perform_action(game, post_action)
		if not await _advance_frames(game, 2):
			await _destroy_game(game)
			return false

	if _completion_snapshot(game) != completed_snapshot:
		_fail("completed shift mutated after late input")
		await _destroy_game(game)
		return false

	await _destroy_game(game)
	return true


func _choose_action(
	game,
	rng: RandomNumberGenerator,
	thought_wait_steps: int,
	notebook_wait_steps: int
) -> String:
	# Required tutorial interactions are eventually forced so every randomized
	# run remains a liveness test rather than waiting forever by design.
	if game.thought_bubble.visible and not game.notebook_open and thought_wait_steps >= 8:
		return "tap-thought"
	if game.notebook_open and notebook_wait_steps >= 8:
		return "write" if not game.active_thought.is_empty() and rng.randf() < 0.7 else "close"

	var roll := rng.randi_range(0, 99)

	if game.notebook_open:
		if roll < 34:
			return "write"
		if roll < 68:
			return "close"
		if roll < 82:
			return "double-route"
		return "idle"

	if game.thought_bubble.visible:
		if roll < 52:
			return "tap-thought"
		if roll < 70:
			return "left"
		if roll < 88:
			return "right"
		return "idle"

	if game.box_waiting_for_route:
		if roll < 25:
			return "left"
		if roll < 50:
			return "right"
		if roll < 61:
			return "double-route"
		if roll < 73:
			return "open-notebook"
		if roll < 88:
			return "idle"
		return "idle-long"

	# Spam during box travel and route animation should be harmless.
	if roll < 22:
		return "left"
	if roll < 44:
		return "right"
	if roll < 57:
		return "double-route"
	if roll < 68:
		return "open-notebook"
	if roll < 78:
		return "close"
	if roll < 88:
		return "write"
	return "idle"


func _perform_action(game, action: String) -> void:
	match action:
		"left":
			if not game.left_hitbox.disabled:
				game._on_left_down()
				game._on_left_up()
		"right":
			if not game.right_hitbox.disabled:
				game._on_right_down()
				game._on_right_up()
		"double-route":
			if not game.left_hitbox.disabled:
				game._on_left_down()
				game._on_left_up()
			# This deliberately arrives immediately after the first release. The
			# module must reject it once that box is no longer waiting.
			if not game.right_hitbox.disabled:
				game._on_right_down()
				game._on_right_up()
		"tap-thought":
			if game.thought_bubble.visible and not game.notebook_open:
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = true
				game._on_thought_bubble_input(click)
		"open-notebook":
			if not game.notebook_hitbox.disabled:
				game._open_notebook()
		"write":
			if game.notebook_open and game.write_idea_button.visible and not game.write_idea_button.disabled:
				game._write_active_thought()
		"close":
			if game.notebook_open:
				game._close_notebook()
		"idle", "idle-long":
			pass


func _advance_frames(game, frame_count: int) -> bool:
	for _frame in range(frame_count):
		await process_frame
		if not is_instance_valid(game):
			_fail("BOXES scene was freed unexpectedly")
			return false
		if not _validate(game):
			return false
	return true


func _validate(game) -> bool:
	if game.shift_boxes_processed < 0 or game.shift_boxes_processed > game.SHIFT_BOX_LIMIT:
		return _fail("processed-box counter outside 0..%d" % game.SHIFT_BOX_LIMIT)
	if game.shift_correct_routes < 0 or game.shift_correct_routes > game.shift_boxes_processed:
		return _fail("correct-route counter exceeds processed boxes")
	if game.boxes_routed != game.correct_routes + game.wrong_routes:
		return _fail("route totals disagree")
	if game.shift_boxes_processed != game.boxes_routed:
		return _fail("shift processed count disagrees with routed count")
	if game.missed_boxes < 0 or game.missed_boxes > game.wrong_routes:
		return _fail("missed-box count is inconsistent with wrong routes")
	if game.premises_saved != game.premises.size():
		return _fail("saved-premise counter disagrees with notebook contents")
	if not game.pending_save_text.is_empty() and not game.notebook_open:
		return _fail("pending notebook save survived after notebook closed")

	if game.notebook_open:
		if not game.notebook_overlay.visible:
			return _fail("notebook state is open but overlay is hidden")
		if not game.left_hitbox.disabled or not game.right_hitbox.disabled:
			return _fail("routing controls enabled while notebook is open")

	if game.box_waiting_for_route and not game.notebook_open and not game.shift_finished:
		if game.left_hitbox.disabled or game.right_hitbox.disabled:
			return _fail("waiting box has no enabled routing controls")

	if game.shift_finished:
		if game.shift_active:
			return _fail("finished shift is still active")
		if game.shift_boxes_processed != game.SHIFT_BOX_LIMIT:
			return _fail("shift finished before all boxes were processed")
		if game.box_waiting_for_route:
			return _fail("finished shift still has a waiting box")
		if game.auto_route_enabled:
			return _fail("automatic routing remains enabled after shift")
		if not game.shift_result_label.visible:
			return _fail("finished shift has no visible result")
		if not game.left_hitbox.disabled or not game.right_hitbox.disabled or not game.notebook_hitbox.disabled:
			return _fail("finished shift accepts gameplay controls")

		var quota_met: bool = game.shift_correct_routes >= game.SHIFT_QUOTA
		if quota_met and "QUOTA MET" not in game.shift_result_label.text:
			return _fail("successful result text reports failure")
		if not quota_met and "MISSED QUOTA" not in game.shift_result_label.text:
			return _fail("failed result text reports success")

	return true


func _completion_snapshot(game) -> String:
	return "%d|%d|%d|%d|%d|%s" % [
		game.boxes_routed,
		game.correct_routes,
		game.wrong_routes,
		game.missed_boxes,
		game.premises_saved,
		game.shift_result_label.text,
	]


func _state_summary(game) -> String:
	return "processed=%d correct=%d waiting=%s notebook=%s thought=%s auto=%s finished=%s" % [
		game.shift_boxes_processed,
		game.shift_correct_routes,
		game.box_waiting_for_route,
		game.notebook_open,
		game.thought_bubble.visible,
		game.auto_route_enabled,
		game.shift_finished,
	]


func _record(entry: String) -> void:
	_trace.append(entry)
	if _trace.size() > TRACE_LIMIT:
		_trace.pop_front()


func _fail(message: String) -> bool:
	if _failure_message.is_empty():
		_failure_message = message
	return false


func _print_failure() -> void:
	push_error("BOXES FUZZ FAILURE seed=%d reason=%s" % [_active_seed, _failure_message])
	print("BOXES FUZZ REPRODUCE: --runs=1 --seed=%d" % _active_seed)
	print("BOXES FUZZ TRACE BEGIN")
	for entry in _trace:
		print(entry)
	print("BOXES FUZZ TRACE END")


func _destroy_game(game) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame

