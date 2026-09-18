extends Node

## Developer-only test harness for playing one module repeatedly without touching
## the player's real save. A test gets temporary GameState, runs the real scene,
## records what changed, restores the previous state, then returns to the lab.

var active: bool = false
var last_test_id: String = ""
var last_module_id: String = ""
var last_result: Dictionary = {}
var last_state_changes: Array[String] = []

var _saved_state: Dictionary = {}
var _test_baseline: Dictionary = {}

const TESTS: Dictionary = {
	"boxes_normal": {
		"label": "BOXES — NORMAL SHIFT",
		"route_id": "work",
	},
	"boxes_tired": {
		"label": "BOXES — TIRED",
		"route_id": "work",
	},
	"stage_first_mic": {
		"label": "STAGE — FIRST MIC",
		"route_id": "stage",
	},
	"stage_paid_set": {
		"label": "STAGE — PAID SET",
		"route_id": "stage",
	},
	"travel_regional": {
		"label": "TRAVEL — REGIONAL",
		"route_id": "travel",
	},
}

const SIMPLE_STATE_KEYS: Array[String] = [
	"money",
	"energy",
	"reputation",
	"career_phase",
	"job_status",
	"current_gig_id",
]

const COUNT_STATE_KEYS: Array[String] = [
	"thoughts",
	"premises",
	"tested_bits",
	"reliable_jokes",
	"burned_material",
	"discovered_venues",
	"bookings",
]


func begin_test(test_id: String) -> bool:
	if active or not TESTS.has(test_id):
		return false

	var game_state := get_node_or_null("/root/GameState")
	var scene_router := get_node_or_null("/root/SceneRouter")
	if game_state == null or scene_router == null:
		return false

	_saved_state = game_state.call("to_save_data").duplicate(true)
	last_test_id = test_id
	last_module_id = ""
	last_result = {}
	last_state_changes.clear()

	# Lab state is temporary from this point forward. SaveManager ignores writes
	# while active, so even modules that save during play cannot touch real saves.
	active = true
	game_state.call("reset_new_game")
	_seed_test_state(test_id, game_state)
	_test_baseline = game_state.call("to_save_data").duplicate(true)

	var route_id := str(TESTS[test_id].get("route_id", ""))
	if route_id.is_empty() or not bool(scene_router.call("go_to", route_id)):
		_restore_saved_state()
		active = false
		return false

	return true


func complete_test(module_id: String, result: Dictionary) -> void:
	if not active:
		return

	var game_state := get_node_or_null("/root/GameState")
	var scene_router := get_node_or_null("/root/SceneRouter")
	if game_state == null or scene_router == null:
		active = false
		return

	var final_state: Dictionary = game_state.call("to_save_data")
	last_module_id = module_id
	last_result = result.duplicate(true)
	last_state_changes = _summarize_state_changes(_test_baseline, final_state)

	_restore_saved_state()
	active = false

	# minigame_lab is a no-save developer route, so returning here still cannot
	# overwrite the player's real Continue checkpoint.
	scene_router.call("go_to", "minigame_lab")


func replay_last_test() -> bool:
	if last_test_id.is_empty():
		return false
	return begin_test(last_test_id)


func get_test_label(test_id: String) -> String:
	if not TESTS.has(test_id):
		return test_id
	return str(TESTS[test_id].get("label", test_id))


func get_last_summary() -> String:
	if last_test_id.is_empty():
		return "NO LAB RUN YET."

	var lines := PackedStringArray()
	lines.append(get_test_label(last_test_id))
	if not last_module_id.is_empty():
		lines.append("MODULE: %s" % last_module_id)

	if not last_result.is_empty():
		lines.append("")
		lines.append("RESULT")
		for key in last_result.keys():
			lines.append("%s: %s" % [str(key), _format_value(last_result[key])])

	lines.append("")
	lines.append("STATE CHANGES")
	if last_state_changes.is_empty():
		lines.append("No tracked persistent state changed.")
	else:
		for change in last_state_changes:
			lines.append(change)

	return "\n".join(lines)


func _seed_test_state(test_id: String, game_state: Node) -> void:
	game_state.set("money", 500)
	game_state.set("energy", 80)

	match test_id:
		"boxes_normal":
			game_state.call("mark_milestone", "opening_boxes_complete")
		"boxes_tired":
			game_state.set("energy", 25)
			game_state.call("mark_milestone", "opening_boxes_complete")
		"stage_first_mic":
			game_state.call("start_gig", "first_mic")
			game_state.call("add_premise", "Lunch break premise")
			game_state.call("add_premise", "Boxes premise")
		"stage_paid_set":
			game_state.call("start_gig", "first_paid_gig")
			game_state.set("reputation", 8)
			game_state.call("add_premise", "New premise")
			game_state.get("tested_bits").append("Tested warehouse bit")
			game_state.get("reliable_jokes").append("Reliable lunch joke")
		"travel_regional":
			game_state.call("start_gig", "regional_gig")
			game_state.set("money", 100)
			game_state.set("energy", 70)


func _restore_saved_state() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null and not _saved_state.is_empty():
		game_state.call("load_save_data", _saved_state)

	_saved_state = {}
	_test_baseline = {}


func _summarize_state_changes(before: Dictionary, after: Dictionary) -> Array[String]:
	var changes: Array[String] = []

	for key in SIMPLE_STATE_KEYS:
		var old_value: Variant = before.get(key)
		var new_value: Variant = after.get(key)
		if old_value != new_value:
			changes.append("%s: %s -> %s" % [
				key,
				_format_value(old_value),
				_format_value(new_value),
			])

	for key in COUNT_STATE_KEYS:
		var old_value: Variant = before.get(key, [])
		var new_value: Variant = after.get(key, [])
		if typeof(old_value) == TYPE_ARRAY and typeof(new_value) == TYPE_ARRAY:
			if old_value.size() != new_value.size():
				changes.append("%s: %d -> %d" % [
					key,
					old_value.size(),
					new_value.size(),
				])

	var old_relationships: Dictionary = before.get("relationships", {})
	var new_relationships: Dictionary = after.get("relationships", {})
	for relationship_id in new_relationships.keys():
		var old_relationship: Variant = old_relationships.get(relationship_id, 0)
		var new_relationship: Variant = new_relationships[relationship_id]
		if old_relationship != new_relationship:
			changes.append("relationship.%s: %s -> %s" % [
				str(relationship_id),
				_format_value(old_relationship),
				_format_value(new_relationship),
			])

	var old_milestones: Dictionary = before.get("milestones", {})
	var new_milestones: Dictionary = after.get("milestones", {})
	for milestone_id in new_milestones.keys():
		if not bool(old_milestones.get(milestone_id, false)) and bool(new_milestones[milestone_id]):
			changes.append("milestone + %s" % str(milestone_id))

	return changes


func _format_value(value: Variant) -> String:
	if typeof(value) == TYPE_BOOL:
		return "yes" if bool(value) else "no"
	if typeof(value) == TYPE_STRING:
		return str(value) if not str(value).is_empty() else "(none)"
	return str(value)
