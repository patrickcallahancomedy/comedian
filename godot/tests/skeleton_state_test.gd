extends SceneTree

## Fast structural/state test for Skeleton Alpha.
## It checks route coverage, career-flow links, gig resources, the return choice,
## material promotion, multiple save/load checkpoints, and randomized state changes.

const FLOW := preload("res://data/skeleton_flow.gd")
const GIGS := preload("res://data/gig_database.gd")
const FUZZ_STEPS := 500

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("SKELETON STATE TEST START")
	_test_main_scene()
	_test_routes_exist()
	_test_flow_links()
	_test_return_choice()
	_test_gig_resources()
	_test_material_pipeline()
	_test_save_checkpoints()
	_test_state_fuzz()

	if failures.is_empty():
		print("SKELETON STATE TEST PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("SKELETON STATE TEST FAIL count=%d" % failures.size())
		quit(1)


func _test_main_scene() -> void:
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	_check(main_scene == "res://scenes/core/main_menu.tscn", "Project does not start at Skeleton Alpha main menu")


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

	for route_id in ["return_choice", "calendar", "travel", "venue", "stage", "ending"]:
		_check(SceneRouter.has_route(route_id), "Required spine route missing: %s" % route_id)

	_check(str(FLOW.get_event("title_reveal").get("next_route", "")) == "calendar", "COMEDIAN reveal does not enter the calendar loop")
	_check(str(FLOW.get_event("special_setup").get("next_route", "")) == "venue", "Special setup does not reach venue")


func _test_return_choice() -> void:
	var packed := load("res://scenes/core/return_choice.tscn") as PackedScene
	_check(packed != null, "Return-to-comedy choice scene failed to load")
	if packed == null:
		return
	var choice = packed.instantiate()
	_check(str(choice.get("option_a_next_route")) == "title_reveal", "GO BACK choice does not begin comedy career")
	_check(str(choice.get("option_b_next_route")) == "wait_week", "NOT YET choice does not loop back later")
	choice.free()


func _test_gig_resources() -> void:
	var expected_next_routes := {
		"first_mic": "after_first_mic",
		"first_paid_gig": "regional_comic",
		"regional_gig": "work_pressure",
		"feature_gig": "first_headline_setup",
		"first_headline": "build_45",
		"hometown_special": "ending",
	}

	for value in GIGS.GIG_PATHS.keys():
		var gig_id := str(value)
		var gig := GIGS.get_gig(gig_id)
		_check(gig != null, "Gig resource failed to load: %s" % gig_id)
		if gig == null:
			continue
		_check(gig.gig_id == gig_id, "Gig ID mismatch for %s" % gig_id)
		_check(SceneRouter.has_route(gig.next_route_id), "Gig %s has invalid next route %s" % [gig_id, gig.next_route_id])
		if expected_next_routes.has(gig_id):
			_check(gig.next_route_id == expected_next_routes[gig_id], "Gig %s breaks the main career spine" % gig_id)


func _test_material_pipeline() -> void:
	GameState.reset_new_game()
	_check(GameState.add_thought("test thought"), "Could not add thought")
	_check(GameState.promote_thought_to_premise(0), "Thought did not promote to premise")
	_check(GameState.promote_premise_to_tested_bit(0), "Premise did not promote to tested bit")
	_check(GameState.promote_tested_bit_to_reliable_joke(0), "Tested bit did not promote to reliable joke")
	_check(GameState.burn_reliable_joke(0), "Reliable joke did not move to burned material")
	_check(GameState.burned_material.size() == 1 and GameState.burned_material[0] == "test thought", "Material changed while moving through pipeline")


func _test_save_checkpoints() -> void:
	var checkpoints := [
		{"route": "first_mic_setup", "phase": GameState.CareerPhase.FIRST_MIC, "gig": "first_mic", "rep": 1},
		{"route": "regional_gig_setup", "phase": GameState.CareerPhase.REGIONAL_COMIC, "gig": "regional_gig", "rep": 19},
		{"route": "feature_setup", "phase": GameState.CareerPhase.WORKING_COMIC, "gig": "feature_gig", "rep": 33},
		{"route": "special_setup", "phase": GameState.CareerPhase.SPECIAL, "gig": "hometown_special", "rep": 70},
	]

	for checkpoint in checkpoints:
		GameState.reset_new_game()
		GameState.week = 7
		GameState.day_index = 3
		GameState.money = 123
		GameState.energy = 44
		GameState.reputation = int(checkpoint["rep"])
		GameState.set_career_phase(int(checkpoint["phase"]))
		GameState.current_route_id = str(checkpoint["route"])
		GameState.start_gig(str(checkpoint["gig"]))
		GameState.mark_milestone("checkpoint_test")
		GameState.add_premise("saved premise")

		_check(SaveManager.save_game(), "Could not save checkpoint %s" % checkpoint["route"])
		GameState.reset_new_game()
		_check(SaveManager.load_game(), "Could not load checkpoint %s" % checkpoint["route"])

		_check(GameState.week == 7, "Save/load lost week at %s" % checkpoint["route"])
		_check(GameState.day_index == 3, "Save/load lost day at %s" % checkpoint["route"])
		_check(GameState.money == 123, "Save/load lost money at %s" % checkpoint["route"])
		_check(GameState.energy == 44, "Save/load lost energy at %s" % checkpoint["route"])
		_check(GameState.reputation == int(checkpoint["rep"]), "Save/load lost reputation at %s" % checkpoint["route"])
		_check(GameState.career_phase == int(checkpoint["phase"]), "Save/load lost career phase at %s" % checkpoint["route"])
		_check(GameState.current_route_id == str(checkpoint["route"]), "Save/load lost route at %s" % checkpoint["route"])
		_check(GameState.current_gig_id == str(checkpoint["gig"]), "Save/load lost active gig at %s" % checkpoint["route"])
		_check(GameState.has_milestone("checkpoint_test"), "Save/load lost milestone at %s" % checkpoint["route"])
		_check(GameState.premises.has("saved premise"), "Save/load lost material at %s" % checkpoint["route"])

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
