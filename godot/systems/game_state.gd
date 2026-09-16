extends Node

## GameState is the one place for information that must survive between modules.
##
## Put long-term facts here: day, money, career progress, relationships, venues,
## bookings, and comedy material.
##
## Do NOT put scene transitions here. SceneRouter decides where the player goes
## next. Individual modules report what happened and update this state through
## small, obvious methods.

signal state_reset
signal state_loaded
signal day_advanced(day_name: String, week: int)
signal career_phase_changed(new_phase: int)

enum CareerPhase {
	BEFORE_COMEDY,
	FIRST_MIC,
	OPEN_MICER,
	LOCAL_REGULAR,
	REGIONAL_COMIC,
	WORKING_COMIC,
	HEADLINER,
	SPECIAL,
	COMPLETE,
}

enum JobStatus {
	EMPLOYED_AT_BOXES,
	LEAVING_BOXES,
	LEFT_BOXES,
}

const SAVE_VERSION := 1

const DAY_NAMES: Array[String] = [
	"Monday",
	"Tuesday",
	"Wednesday",
	"Thursday",
	"Friday",
	"Saturday",
	"Sunday",
]

# -----------------------------------------------------------------------------
# TIME / BASIC LIFE STATE
# -----------------------------------------------------------------------------

var week: int = 1
var day_index: int = 0
var money: int = 0
var energy: int = 100

# SceneRouter updates this whenever it successfully changes modules. SaveManager
# stores it so Continue can eventually return Darren to the correct place.
var current_route_id: String = "story_intro"

# -----------------------------------------------------------------------------
# CAREER / WORK
# -----------------------------------------------------------------------------

var career_phase: int = CareerPhase.BEFORE_COMEDY
var reputation: int = 0
var job_status: int = JobStatus.EMPLOYED_AT_BOXES

# Named relationship values stay simple for now. More characters can be added
# here without changing the rest of the game architecture.
var relationships: Dictionary = {
	"ray": 0,
	"nate": 0,
	"troy": 0,
	"home": 0,
}

# -----------------------------------------------------------------------------
# WORLD / PROGRESSION
# -----------------------------------------------------------------------------

var discovered_venues: Array[String] = []
var bookings: Array[Dictionary] = []

# Milestones replace dozens of one-off booleans. Example IDs:
# "mic_discovered", "first_mic_complete", "left_boxes", "first_headline".
var milestones: Dictionary = {}

# -----------------------------------------------------------------------------
# COMEDY MATERIAL
# -----------------------------------------------------------------------------
# The entire game uses one readable pipeline:
# Thought -> Premise -> Tested Bit -> Reliable Joke -> Burned Material
#
# Modules should move material through these lists instead of inventing their
# own permanent joke storage.

var thoughts: Array[String] = []
var premises: Array[String] = []
var tested_bits: Array[String] = []
var reliable_jokes: Array[String] = []
var burned_material: Array[String] = []


## Return the human-readable current day.
func get_day_name() -> String:
	return DAY_NAMES[day_index]


## Move the calendar forward by one day. Calendar-specific consequences belong
## in the Calendar system, not here.
func advance_day() -> void:
	day_index += 1
	if day_index >= DAY_NAMES.size():
		day_index = 0
		week += 1

	day_advanced.emit(get_day_name(), week)


## Change Darren's broad comedy-career phase.
func set_career_phase(new_phase: int) -> void:
	if new_phase == career_phase:
		return
	if new_phase < CareerPhase.BEFORE_COMEDY or new_phase > CareerPhase.COMPLETE:
		push_warning("GameState received an invalid career phase: %s" % new_phase)
		return

	career_phase = new_phase
	career_phase_changed.emit(career_phase)


## Mark a named story/career milestone as completed.
func mark_milestone(milestone_id: String) -> void:
	if milestone_id.is_empty():
		return
	milestones[milestone_id] = true


func has_milestone(milestone_id: String) -> bool:
	return milestones.get(milestone_id, false)


## Add a venue once. The string should be a stable ID such as "tuesday_mic".
func discover_venue(venue_id: String) -> void:
	if venue_id.is_empty() or discovered_venues.has(venue_id):
		return
	discovered_venues.append(venue_id)


# -----------------------------------------------------------------------------
# MATERIAL PIPELINE HELPERS
# -----------------------------------------------------------------------------

func add_thought(text: String) -> bool:
	return _add_unique_material(thoughts, text)


## BOXES and future writing modules can add a premise directly when the thought
## stage happens inside their own gameplay.
func add_premise(text: String) -> bool:
	return _add_unique_material(premises, text)


func promote_thought_to_premise(index: int) -> bool:
	return _move_material(thoughts, premises, index)


func promote_premise_to_tested_bit(index: int) -> bool:
	return _move_material(premises, tested_bits, index)


func promote_tested_bit_to_reliable_joke(index: int) -> bool:
	return _move_material(tested_bits, reliable_jokes, index)


func burn_reliable_joke(index: int) -> bool:
	return _move_material(reliable_jokes, burned_material, index)


func _add_unique_material(target: Array[String], text: String) -> bool:
	var clean_text := text.strip_edges()
	if clean_text.is_empty() or target.has(clean_text):
		return false
	target.append(clean_text)
	return true


func _move_material(source: Array[String], destination: Array[String], index: int) -> bool:
	if index < 0 or index >= source.size():
		return false

	var material_text := source[index]
	source.remove_at(index)
	if not destination.has(material_text):
		destination.append(material_text)
	return true


# -----------------------------------------------------------------------------
# SAVE DATA
# -----------------------------------------------------------------------------
# SaveManager handles files. GameState only translates its readable variables
# to and from a Dictionary.

func to_save_data() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"week": week,
		"day_index": day_index,
		"money": money,
		"energy": energy,
		"current_route_id": current_route_id,
		"career_phase": career_phase,
		"reputation": reputation,
		"job_status": job_status,
		"relationships": relationships.duplicate(true),
		"discovered_venues": discovered_venues.duplicate(),
		"bookings": bookings.duplicate(true),
		"milestones": milestones.duplicate(true),
		"thoughts": thoughts.duplicate(),
		"premises": premises.duplicate(),
		"tested_bits": tested_bits.duplicate(),
		"reliable_jokes": reliable_jokes.duplicate(),
		"burned_material": burned_material.duplicate(),
	}


func load_save_data(data: Dictionary) -> void:
	week = maxi(1, int(data.get("week", 1)))
	day_index = clampi(int(data.get("day_index", 0)), 0, DAY_NAMES.size() - 1)
	money = int(data.get("money", 0))
	energy = clampi(int(data.get("energy", 100)), 0, 100)
	current_route_id = str(data.get("current_route_id", "story_intro"))

	career_phase = clampi(
		int(data.get("career_phase", CareerPhase.BEFORE_COMEDY)),
		CareerPhase.BEFORE_COMEDY,
		CareerPhase.COMPLETE
	)
	reputation = int(data.get("reputation", 0))
	job_status = clampi(
		int(data.get("job_status", JobStatus.EMPLOYED_AT_BOXES)),
		JobStatus.EMPLOYED_AT_BOXES,
		JobStatus.LEFT_BOXES
	)

	var loaded_relationships = data.get("relationships", {})
	if typeof(loaded_relationships) == TYPE_DICTIONARY:
		relationships = loaded_relationships.duplicate(true)
	else:
		relationships = _default_relationships()

	var loaded_milestones = data.get("milestones", {})
	milestones = (
		loaded_milestones.duplicate(true)
		if typeof(loaded_milestones) == TYPE_DICTIONARY
		else {}
	)

	discovered_venues = _read_string_array(data.get("discovered_venues", []))
	bookings = _read_dictionary_array(data.get("bookings", []))

	thoughts = _read_string_array(data.get("thoughts", []))
	premises = _read_string_array(data.get("premises", []))
	tested_bits = _read_string_array(data.get("tested_bits", []))
	reliable_jokes = _read_string_array(data.get("reliable_jokes", []))
	burned_material = _read_string_array(data.get("burned_material", []))

	state_loaded.emit()


func _read_string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return output

	for item in value:
		if typeof(item) == TYPE_STRING:
			output.append(item)
	return output


func _read_dictionary_array(value: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return output

	for item in value:
		if typeof(item) == TYPE_DICTIONARY:
			output.append(item.duplicate(true))
	return output


func _default_relationships() -> Dictionary:
	return {
		"ray": 0,
		"nate": 0,
		"troy": 0,
		"home": 0,
	}


## Reset only persistent game information. Visual scenes are responsible for
## resetting their own temporary UI/gameplay state when they load.
func reset_new_game() -> void:
	week = 1
	day_index = 0
	money = 0
	energy = 100
	current_route_id = "story_intro"

	career_phase = CareerPhase.BEFORE_COMEDY
	reputation = 0
	job_status = JobStatus.EMPLOYED_AT_BOXES
	relationships = _default_relationships()

	discovered_venues.clear()
	bookings.clear()
	milestones.clear()

	thoughts.clear()
	premises.clear()
	tested_bits.clear()
	reliable_jokes.clear()
	burned_material.clear()

	state_reset.emit()
