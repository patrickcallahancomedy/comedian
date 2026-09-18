extends Node

## SaveManager is the only system that reads or writes the save file.
## GameState owns the actual game data; this file only serializes it as readable JSON.

signal save_completed
signal load_completed
signal save_failed(message: String)
signal load_failed(message: String)

const SAVE_PATH := "user://comedian_save.json"


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Reset the persistent state and enter the opening route. The title screen can
## call this directly later without knowing how GameState or routing works.
func start_new_game() -> bool:
	GameState.reset_new_game()
	delete_save()
	return SceneRouter.go_to("story_intro")


## Load the save first, then ask SceneRouter to return to its stored route.
func continue_game() -> bool:
	if not load_game():
		return false
	return SceneRouter.resume_saved_route()


func save_game() -> bool:
	# Minigame Lab runs the real modules against temporary GameState. Modules are
	# allowed to call SaveManager normally; lab mode simply absorbs those writes
	# so development tests can never overwrite the player's actual Continue save.
	var lab := get_node_or_null("/root/MinigameLab")
	if lab != null and bool(lab.get("active")):
		return true

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		var message := "Could not open save file for writing."
		push_error(message)
		save_failed.emit(message)
		return false

	file.store_string(JSON.stringify(GameState.to_save_data(), "\t"))
	file.close()
	save_completed.emit()
	return true


func load_game() -> bool:
	if not has_save():
		var no_save_message := "No COMEDIAN save file exists yet."
		load_failed.emit(no_save_message)
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		var open_message := "Could not open save file for reading."
		push_error(open_message)
		load_failed.emit(open_message)
		return false

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_error := json.parse(json_text)
	if parse_error != OK or typeof(json.data) != TYPE_DICTIONARY:
		var parse_message := "Save file is not valid COMEDIAN save data."
		push_error(parse_message)
		load_failed.emit(parse_message)
		return false

	GameState.load_save_data(json.data)
	load_completed.emit()
	return true


## Used by New Game or debugging. This intentionally removes only COMEDIAN's
## single save file and does not touch imported assets or project files.
func delete_save() -> bool:
	if not has_save():
		return true

	var absolute_path := ProjectSettings.globalize_path(SAVE_PATH)
	var error := DirAccess.remove_absolute(absolute_path)
	if error != OK:
		push_error("Could not delete COMEDIAN save file.")
		return false
	return true
