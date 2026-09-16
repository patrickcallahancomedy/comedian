extends SceneTree

## Fast structural/state test for Skeleton Alpha.
## It checks route coverage, career-flow links, gig resources, material promotion,
## save/load round-trips, and randomized GameState mutations.

const FLOW := preload("res://data/skeleton_flow.gd")
const GIGS := preload("res://data/gig_database.gd")
const FUZZ_STEPS := 500

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("SKELETON STATE TEST START")
	_test_routes_exist()
	_test_flow_links()
	_test_gig_resources()
	_test_material_pipeline()
	_test_save_round_trip()
	_test_state_fuzz()

	if failures.is_empty():
		print("SKELETON STATE TEST PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("SKELETON STATE TEST FAIL count=%d" % failures.size())
		quit(1)


func _test_routes_exist() -> void:
	for route_id in SceneRouter.get_all_route_ids():
		var path := SceneRouter.get_route_path(route_id)
		_check(not path.is_empty(), "Route %s has no path" % route_id)
		_check(ResourceLoader.exists(path), "Route %s points to missing scene %s" % [route_id, path])


func _test_flow_links() -> void:
	for value in FLOW.EVENTS.keys():
		var route_id := str(value)
		var event := FLOW.get_event(route_id)
		_check(SceneRouter.has_route(route_id), "Career event has no router entry: %s" % route_id)
		var next_route := str(event.get("next_route", ""))
		_check(SceneRouter.has_route(next_route), "Career event %s has invalid next route %s" % [route_id, next_route])

	# These non-data transitions complete the main spine between career cards.
	for route_id in ["return_choice", "venue", "stage", "ending"]:
		_check(SceneRouter.has_route(route_id), "Required spine route missing: %s" % route_id)


func _test_gig_resources() -> void:
	for value in GIGS.GIG_PATHS.keys():
		var gig_id := str(value)
		var gig := GIGS.get_gig(gig_id)
		_check(gig != null, "Gig resource failed to load: %s" % gig_id)
		if gig == null:
			continue
		_check(gig.gig_id == gig_id, "Gig ID mismatch for %s" % gig_id)
		_check(SceneRouter.has_route(gig.next_route_id), "Gig %s has invalid next route %s" % [gig_id, gig.next_route_id])


func _test_material_pipeline() -> void:
	GameState.reset_new_game()
	_check(GameState.add_thought("test thought"), "Could not add thought")
	_check(GameState.promote_thought_to_premise(0), "Thought did not promote to premise")
	_check(GameState.promote_premise_to_tested_bit(0), "Premise did not promote to tested bit")
	_check(GameState.promote_tested_bit_to_reliable_joke(0), "Tested bit did not promote to reliable joke")
	_check(GameState.burn_reliable_joke(0), "Reliable joke did not move to burned material")
	_check(GameState.burned_material == ["test thought"], "Material changed text while moving through pipeline")


func _test_save_round_trip() -> void:
	GameState.reset_new_game()
	GameState.week = 7
	GameState.day_index = 3
	GameState.money = 123
	GameState.energy = 44
	GameState.reputation = 19
	GameState.set_career_phase(GameState.CareerPhase.REGIONAL_COMIC)
	GameState.set_job_status(GameState.JobStatus.EMPLOYED_AT_BOXES)
	GameState.current_route_id = "regional_gig_setup"
	GameState.start_gig("regional_gig")
	GameState.mark_milestone("round_trip_test")
	GameState.add_premise("saved premise")

	_check(SaveManager.save_game(), "SaveManager could not write round-trip save")
	GameState.reset_new_game()
	_check(SaveManager.load_game(), "SaveManager could not load round-trip save")

	_check(GameState.week == 7, "Save/load lost week")
	_check(GameState.day_index == 3, "Save/load lost day")
	_check(GameState.money == 123, "Save/load lost money")
	_check(GameState.energy == 44, "Save/load lost energy")
	_check(GameState.reputation == 19, "Save/load lost reputation")
	_check(GameState.career_phase == GameState.CareerPhase.REGIONAL_COMIC, "Save/load lost career phase")
	_check(GameState.current_route_id == "regional_gig_setup", "Save/load lost route")
	_check(GameState.current_gig_id == "regional_gig", "Save/load lost active gig")
	_check(GameState.has_milestone("round_trip_test"), "Save/load lost milestone")
	_check(GameState.premises.has("saved premise"), "Save/load lost material")
	SaveManager.delete_save()


func _test_state_fuzz() -> void:
	GameState.reset_new_game()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916

	for index in range(FUZZ_STEPS):
		match rng.randi_range(0, 7):
			0:
				GameState.advance_day()
			1:
				GameState.add_money(rng.randi_range(-25, 50))
			2:
				GameState.change_energy(rng.randi_range(-30, 30))
			3:
				GameState.add_reputation(rng.randi_range(-4, 8))
			4:
				GameState.mark_milestone("fuzz_%d" % index)
			5:
				GameState.add_thought("thought_%d" % index)
			6:
				if not GameState.thoughts.is_empty():
					GameState.promote_thought_to_premise(0)
			7:
				if not GameState.premises.is_empty():
					GameState.promote_premise_to_tested_bit(0)

		_check(GameState.day_index >= 0 and GameState.day_index < GameState.DAY_NAMES.size(), "Fuzz produced invalid day index")
		_check(GameState.week >= 1, "Fuzz produced invalid week")
		_check(GameState.energy >= 0 and GameState.energy <= 100, "Fuzz produced invalid energy")
		_check(GameState.reputation >= 0, "Fuzz produced negative reputation")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
