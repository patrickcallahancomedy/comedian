class_name GameModule
extends Control

## Base contract for every major playable module in Skeleton Alpha.
##
## Patrick can replace the visual children of a module scene freely. Keep the
## root node and this handoff intact so the rest of the game can still route it.

signal module_finished(module_id: String, result: Dictionary)

@export_category("Module Handoff")
@export var module_id: String = ""
@export var next_route_id: String = ""


## Call once when this module is finished. Write permanent consequences to
## GameState first; result is a readable summary for routing/debugging.
func finish_module(result: Dictionary = {}) -> void:
	if module_id.is_empty():
		push_warning("A GameModule finished without a module_id.")

	var clean_result := result.duplicate(true)
	module_finished.emit(module_id, clean_result)
	SceneRouter.finish_module(module_id, clean_result, next_route_id)
