extends SceneTree

## A model-based first-time player for the BOXES vertical slice.
##
## Unlike the fuzz test, this driver waits, hesitates, makes occasional mistakes,
## prioritizes interesting thoughts, and prints a first-person experience report.
## It is not a substitute for a human playtest; it is a repeatable prediction of
## where an ordinary curious player is likely to feel clarity, pressure, or drag.

const BOXES_SCENE := preload("res://scenes/boxes/boxes_module.tscn")
const PLAYER_NAME := "Alex"
const PLAYER_DESCRIPTION := "curious first-time player; imperfect reactions; wants to save every joke idea"
const DEFAULT_SEED := 20260916
const MAX_SIMULATION_FRAMES := 1600
const SIMULATION_TIME_SCALE := 8.0

var _rng := RandomNumberGenerator.new()
var _seed := DEFAULT_SEED
var _frames_elapsed := 0
var _route_attempts := 0
var _deliberate_mistakes := 0
var _timed_out_decisions := 0
var _close_calls := 0
var _thoughts_opened := 0
var _notebook_costs := 0


func _initialize() -> void:
	call_deferred("_run_playtest")


func _run_playtest() -> void:
	_read_options()
	_rng.seed = _seed
	seed(_seed)

	var original_time_scale := Engine.time_scale
	Engine.time_scale = SIMULATION_TIME_SCALE

	var game = BOXES_SCENE.instantiate()
	root.add_child(game)
	await _wait_frames(8)

	while not game.shift_finished and _frames_elapsed < MAX_SIMULATION_FRAMES:
		if game.notebook_open:
			await _handle_notebook(game)
		elif game.thought_bubble.visible:
			await _handle_thought(game)
		elif game.box_waiting_for_route:
			await _handle_waiting_box(game)
		else:
			await _wait_frames(1)

	Engine.time_scale = original_time_scale

	if not game.shift_finished:
		push_error("VIRTUAL PLAYER could not finish the shift")
		game.queue_free()
		quit(1)
		return

	_print_report(game)
	game.queue_free()
	await process_frame
	quit(0)


func _read_options() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			_seed = int(argument.trim_prefix("--seed="))


func _handle_thought(game) -> void:
	var thought_seen: String = game.active_thought
	var missed_before: int = game.missed_boxes
	# A first-time player pauses to read before realizing the bubble is clickable.
	await _wait_frames(_rng.randi_range(6, 13))

	if game.thought_bubble.visible and game.active_thought == thought_seen:
		game._open_notebook()
		_thoughts_opened += 1
		await _wait_until_notebook_closes(game)
		if game.missed_boxes > missed_before:
			_notebook_costs += game.missed_boxes - missed_before


func _handle_notebook(game) -> void:
	if not game.active_thought.is_empty() and game.pending_save_text.is_empty():
		# Reading both pages and finding the write control takes longer than routing.
		await _wait_frames(_rng.randi_range(7, 14))
		if game.notebook_open and not game.active_thought.is_empty():
			game._write_active_thought()
	else:
		await _wait_frames(1)


func _wait_until_notebook_closes(game) -> void:
	while game.notebook_open and not game.shift_finished:
		await _handle_notebook(game)


func _handle_waiting_box(game) -> void:
	var observed_cycle: int = game.box_cycle_id
	var reaction_frames := _rng.randi_range(7, 20)

	# An occasional attention lapse models looking at the quota, feedback, or boss.
	if _rng.randf() < 0.16:
		reaction_frames += _rng.randi_range(8, 17)
	if reaction_frames >= 22:
		_close_calls += 1

	await _wait_frames(reaction_frames)

	if not game.box_waiting_for_route or game.box_cycle_id != observed_cycle:
		_timed_out_decisions += 1
		return

	_route_attempts += 1
	var accuracy := 0.90 if game.shift_boxes_processed < 3 else 0.84
	var chosen_direction: String = game.current_destination
	if _rng.randf() > accuracy:
		chosen_direction = "right" if chosen_direction == "left" else "left"
		_deliberate_mistakes += 1

	if chosen_direction == "left":
		game._on_left_down()
		game._on_left_up()
	else:
		game._on_right_down()
		game._on_right_up()


func _wait_frames(frame_count: int) -> void:
	for _frame in range(frame_count):
		await process_frame
		_frames_elapsed += 1


func _print_report(game) -> void:
	var quota_met: bool = game.shift_correct_routes >= game.SHIFT_QUOTA
	var simulated_seconds := (
		float(_frames_elapsed) * SIMULATION_TIME_SCALE / 120.0
	)

	print("VIRTUAL PLAYER REPORT BEGIN")
	print("Player: %s (%s)" % [PLAYER_NAME, PLAYER_DESCRIPTION])
	print("Seed: %d" % _seed)
	print("Result: %s — %d/%d correct, %d wrong, %d timed out, %d premise(s) saved" % [
		"quota met" if quota_met else "quota missed",
		game.shift_correct_routes,
		game.SHIFT_BOX_LIMIT,
		game.wrong_routes,
		game.missed_boxes,
		game.premises_saved,
	])
	print("Estimated play time: %.1f seconds" % simulated_seconds)
	print("")
	print("WHAT I LIKED")
	print("- I understood the left/right sorting loop quickly because the destination is printed directly on each box.")
	print("- The notebook was the strongest idea. Saving a thought gave the repetitive job a story purpose.")
	if _notebook_costs > 0:
		print("- Writing cost me %d box(es), so the work-versus-creativity conflict felt real." % _notebook_costs)
	else:
		print("- Writing interrupted the rhythm, but this run never made me truly pay for that choice.")
	print("")
	print("WHERE I DRIFTED")
	print("- By about box six I had already seen the full physical action; later boxes repeated it without adding a new routing problem.")
	if game.boss_catches == 0:
		print("- Troy did not affect my result, so the boss pressure read more like atmosphere than gameplay.")
	else:
		print("- Troy reacted %d time(s), which made the quota pressure easier to notice." % game.boss_catches)
	if _timed_out_decisions > 0:
		print("- I hesitated long enough to lose %d decision(s); the two-second deadline can punish time spent reading the screen." % _timed_out_decisions)
	if _close_calls == 0:
		print("- I rarely felt close to failure outside the notebook, so ordinary sorting had limited tension.")
	else:
		print("- %d slow reaction(s) created some pressure, though the decision itself stayed binary." % _close_calls)
	print("")
	print("FUN VERDICT")
	if quota_met and game.premises_saved > 0:
		print("Promising, but not fully fun yet. The notebook choice is fun; sorting is currently the setup that makes that choice matter.")
	else:
		print("The theme is stronger than the moment-to-moment fun in this run. I would replay after clearer feedback or another mid-shift wrinkle.")
	print("Keep the short shift and notebook tension. Improve the second half before adding more boxes.")
	print("VIRTUAL PLAYER REPORT END")
