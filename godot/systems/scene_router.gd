extends Node

## SceneRouter is the one obvious place that knows where named game routes live.
## Modules should request a route by ID instead of scattering scene paths across
## unrelated scripts.

signal route_changed(route_id: String)
signal module_completed(module_id: String, result: Dictionary)

const ROUTES: Dictionary = {
	"story_intro": "res://scenes/story/story_sequence.tscn",
	"story_generic": "res://scenes/story/story_module.tscn",
	"choice": "res://scenes/core/choice_module.tscn",
	"calendar": "res://scenes/core/calendar_module.tscn",
	"home": "res://scenes/home/home_module.tscn",
	"work": "res://scenes/home/work_module.tscn",
	"travel": "res://scenes/core/travel_module.tscn",
	"venue": "res://scenes/venues/venue_module.tscn",
	"boxes": "res://scenes/boxes/boxes_module.tscn",
	"placeholder": "res://scenes/placeholders/placeholder_module.tscn",
}

var current_route_id: String = ""
var last_module_id: String = ""
var last_module_result: Dictionary = {}


func has_route(route_id: String) -> bool:
	return ROUTES.has(route_id)


func get_route_path(route_id: String) -> String:
	return str(ROUTES.get(route_id, ""))


func go_to(route_id: String) -> bool:
	var scene_path := get_route_path(route_id)
	if scene_path.is_empty():
		push_error("SceneRouter does not know route: %s" % route_id)
		return false
	if not ResourceLoader.exists(scene_path):
		push_error("SceneRouter route points to a missing scene: %s" % scene_path)
		return false

	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("SceneRouter could not open route %s" % route_id)
		return false

	current_route_id = route_id
	GameState.current_route_id = route_id
	route_changed.emit(route_id)
	return true


## Standard handoff used by GameModule. Persistent effects should already have
## been written to GameState before this is called. The result is kept only as a
## short-lived description of what happened in the module.
func finish_module(
	module_id: String,
	result: Dictionary = {},
	next_route_id: String = ""
) -> void:
	last_module_id = module_id
	last_module_result = result.duplicate(true)
	module_completed.emit(module_id, last_module_result)

	if not next_route_id.is_empty():
		go_to(next_route_id)


## Continue uses the route saved in GameState. It returns false instead of
## guessing if an old or invalid save points somewhere that no longer exists.
func resume_saved_route() -> bool:
	return go_to(GameState.current_route_id)
