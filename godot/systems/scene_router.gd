extends Node

## SceneRouter is the one obvious place that knows where named game routes live.
## Modules request a route by ID instead of scattering scene paths across scripts.

signal route_changed(route_id: String)
signal module_completed(module_id: String, result: Dictionary)

const CAREER_EVENT_SCENE := "res://scenes/core/career_event_module.tscn"

const ROUTES: Dictionary = {
	"main_menu": "res://scenes/core/main_menu.tscn",
	"dev_menu": "res://scenes/core/developer_jump_menu.tscn",
	"minigame_lab": "res://scenes/core/minigame_lab_menu.tscn",
	"story_intro": "res://scenes/story/story_sequence.tscn",
	"story_generic": "res://scenes/story/story_module.tscn",
	"choice": "res://scenes/core/choice_module.tscn",
	"return_choice": "res://scenes/core/return_choice.tscn",
	"calendar": "res://scenes/core/calendar_module.tscn",
	"home": "res://scenes/home/home_module.tscn",
	"work": "res://scenes/home/work_module.tscn",
	"car": "res://scenes/drive/drive_module.tscn",
	"drive": "res://scenes/drive/drive_module.tscn",
	"travel": "res://scenes/core/travel_module.tscn",
	"venue": "res://scenes/venues/venue_module.tscn",
	"stage": "res://scenes/stage/stage_module.tscn",
	"boxes": "res://scenes/boxes/boxes_module.tscn",
	"placeholder": "res://scenes/placeholders/placeholder_module.tscn",
	"ending": "res://scenes/core/ending_module.tscn",

	# These route IDs intentionally share one ugly placeholder scene.
	# data/skeleton_flow.gd supplies text, milestones, gates, and next routes.
	"lunch": CAREER_EVENT_SCENE,
	"home_intro": CAREER_EVENT_SCENE,
	"first_mic_setup": CAREER_EVENT_SCENE,
	"after_first_mic": CAREER_EVENT_SCENE,
	"wait_week": CAREER_EVENT_SCENE,
	"title_reveal": CAREER_EVENT_SCENE,
	"open_micer": CAREER_EVENT_SCENE,
	"local_regular": CAREER_EVENT_SCENE,
	"first_paid_setup": CAREER_EVENT_SCENE,
	"regional_comic": CAREER_EVENT_SCENE,
	"regional_gig_setup": CAREER_EVENT_SCENE,
	"work_pressure": CAREER_EVENT_SCENE,
	"leave_boxes": CAREER_EVENT_SCENE,
	"working_comic": CAREER_EVENT_SCENE,
	"feature_setup": CAREER_EVENT_SCENE,
	"first_headline_setup": CAREER_EVENT_SCENE,
	"build_45": CAREER_EVENT_SCENE,
	"special_setup": CAREER_EVENT_SCENE,
}

var current_route_id: String = ""
var last_module_id: String = ""
var last_module_result: Dictionary = {}


func has_route(route_id: String) -> bool:
	return ROUTES.has(route_id)


func get_route_path(route_id: String) -> String:
	return str(ROUTES.get(route_id, ""))


func get_all_route_ids() -> Array[String]:
	var ids: Array[String] = []
	for route_id in ROUTES.keys():
		ids.append(str(route_id))
	return ids


func go_to(route_id: String) -> bool:
	var scene_path := get_route_path(route_id)
	if scene_path.is_empty():
		push_error("SceneRouter does not know route: %s" % route_id)
		return false
	if not ResourceLoader.exists(scene_path):
		push_error("SceneRouter route points to a missing scene: %s" % scene_path)
		return false

	# Set the route before the queued scene change so shared scenes know which
	# route data to read in _ready(). Roll back if Godot rejects the change.
	var previous_router_route := current_route_id
	var previous_game_route := GameState.current_route_id
	current_route_id = route_id
	GameState.current_route_id = route_id

	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		current_route_id = previous_router_route
		GameState.current_route_id = previous_game_route
		push_error("SceneRouter could not open route %s" % route_id)
		return false

	# Menu/dev/lab routes deliberately do not overwrite the last playable
	# checkpoint, so Continue still returns to the player's real game.
	if route_id != "main_menu" and route_id != "dev_menu" and route_id != "minigame_lab":
		SaveManager.save_game()
	route_changed.emit(route_id)
	return true


func finish_module(
	module_id: String,
	result: Dictionary = {},
	next_route_id: String = ""
) -> void:
	last_module_id = module_id
	last_module_result = result.duplicate(true)
	module_completed.emit(module_id, last_module_result)

	# The same real module can be launched from Minigame Lab. In that case the
	# lab records the result, restores the pre-test state, and returns to its
	# results screen instead of following the normal game route.
	var lab := get_node_or_null("/root/MinigameLab")
	if lab != null and bool(lab.get("active")):
		lab.call("complete_test", module_id, last_module_result)
		return

	if not next_route_id.is_empty():
		go_to(next_route_id)


func resume_saved_route() -> bool:
	return go_to(GameState.current_route_id)
