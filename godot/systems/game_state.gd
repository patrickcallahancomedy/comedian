extends Node

## GameState is the one place for information that must survive between modules.
##
## Put long-term facts here: day, money, career progress, relationships, venues,
## bookings, comedy material, and current life conditions.
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

const SAVE_VERSION := 3

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
var stress: int = 20
var current_intoxication: int = 0

# Car state is persistent because the same car will eventually be used for work,
# mics, road gigs, errands, and the drive home.
var car_condition: int = 75
var gas: int = 60

# Temporary context shared by modules during one outing/night. Example:
# the car module writes arrival_minutes_before_signup and the signup/pre-show
# modules consume it. This is saveable so quitting mid-night is safe.
var night_context: Dictionary = {}

# Small counters for things that happened repeatedly. Keep named counters here
# instead of inventing hidden one-off variables inside individual minigames.
var history: Dictionary = {}

# SceneRouter updates this whenever it successfully changes modules. SaveManager
# stores it so Continue can return Darren to the correct place.
var current_route_id: String = "story_intro"

# -----------------------------------------------------------------------------
# CAREER / WORK
# -----------------------------------------------------------------------------

var career_phase: int = CareerPhase.BEFORE_COMEDY
var reputation: int = 0
var job_status: int = JobStatus.EMPLOYED_AT_BOXES

# The active booking is a stable ID pointing at a normal .tres file in data/gigs.
# An empty value means Darren is not currently travelling to / inside a gig.
var current_gig_id: String = ""

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

var thoughts: Array[String] = []
var premises: Array[String] = []
var tested_bits: Array[String] = []
var reliable_jokes: Array[String] = []
var burned_material: Array[String] = []


func get_day_name() -> String:
	return DAY_NAMES[day_index]


func advance_day() -> void:
	day_index += 1
	if day_index >= DAY_NAMES.size():
		day_index = 0
		week += 1
	day_advanced.emit(get_day_name(), week)


func set_career_phase(new_phase: int) -> void:
	if new_phase == career_phase:
		return
	if new_phase < CareerPhase.BEFORE_COMEDY or new_phase > CareerPhase.COMPLETE:
		push_warning("GameState received an invalid career phase: %s" % new_phase)
		return
	career_phase = new_phase
	career_phase_changed.emit(career_phase)


func get_career_phase_name() -> String:
	return CareerPhase.keys()[career_phase].replace("_", " ").capitalize()


func set_job_status(new_status: int) -> void:
	if new_status < JobStatus.EMPLOYED_AT_BOXES or new_status > JobStatus.LEFT_BOXES:
		push_warning("GameState received an invalid job status: %s" % new_status)
		return
	job_status = new_status


func add_money(amount: int) -> void:
	money += amount


func change_energy(amount: int) -> void:
	energy = clampi(energy + amount, 0, 100)


func change_stress(amount: int) -> void:
	stress = clampi(stress + amount, 0, 100)


func change_intoxication(amount: int) -> void:
	current_intoxication = clampi(current_intoxication + amount, 0, 100)


func change_car_condition(amount: int) -> void:
	car_condition = clampi(car_condition + amount, 0, 100)


func change_gas(amount: int) -> void:
	gas = clampi(gas + amount, 0, 100)


func add_reputation(amount: int) -> void:
	reputation = maxi(0, reputation + amount)


func change_relationship(relationship_id: String, amount: int) -> void:
	if relationship_id.is_empty():
		return
	relationships[relationship_id] = clampi(
		int(relationships.get(relationship_id, 0)) + amount,
		-100,
		100
	)


func increment_history(history_id: String, amount: int = 1) -> void:
	if history_id.is_empty():
		return
	history[history_id] = int(history.get(history_id, 0)) + amount


func mark_milestone(milestone_id: String) -> void:
	if milestone_id.is_empty():
		return
	milestones[milestone_id] = true


func has_milestone(milestone_id: String) -> bool:
	return bool(milestones.get(milestone_id, false))


func discover_venue(venue_id: String) -> void:
	if venue_id.is_empty() or discovered_venues.has(venue_id):
		return
	discovered_venues.append(venue_id)


func start_gig(gig_id: String) -> void:
	current_gig_id = gig_id


func clear_current_gig() -> void:
	current_gig_id = ""


# -----------------------------------------------------------------------------
# MATERIAL PIPELINE HELPERS
# -----------------------------------------------------------------------------

func add_thought(text: String) -> bool:
	return _add_unique_material(thoughts, text)


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

func to_save_data() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"week": week,
		"day_index": day_index,
		"money": money,
		"energy": energy,
		"stress": stress,
		"current_intoxication": current_intoxication,
		"car_condition": car_condition,
		"gas": gas,
		"night_context": night_context.duplicate(true),
		"history": history.duplicate(true),
		"current_route_id": current_route_id,
		"career_phase": career_phase,
		"reputation": reputation,
		"job_status": job_status,
		"current_gig_id": current_gig_id,
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
	stress = clampi(int(data.get("stress", 20)), 0, 100)
	current_intoxication = clampi(int(data.get("current_intoxication", 0)), 0, 100)
	car_condition = clampi(int(data.get("car_condition", 75)), 0, 100)
	gas = clampi(int(data.get("gas", 60)), 0, 100)
	current_route_id = str(data.get("current_route_id", "story_intro"))

	var loaded_night_context = data.get("night_context", {})
	night_context = (
		loaded_night_context.duplicate(true)
		if typeof(loaded_night_context) == TYPE_DICTIONARY
		else {}
	)

	var loaded_history = data.get("history", {})
	history = (
		loaded_history.duplicate(true)
		if typeof(loaded_history) == TYPE_DICTIONARY
		else {}
	)

	career_phase = clampi(
		int(data.get("career_phase", CareerPhase.BEFORE_COMEDY)),
		CareerPhase.BEFORE_COMEDY,
		CareerPhase.COMPLETE
	)
	reputation = maxi(0, int(data.get("reputation", 0)))
	job_status = clampi(
		int(data.get("job_status", JobStatus.EMPLOYED_AT_BOXES)),
		JobStatus.EMPLOYED_AT_BOXES,
		JobStatus.LEFT_BOXES
	)
	current_gig_id = str(data.get("current_gig_id", ""))

	var loaded_relationships = data.get("relationships", {})
	if typeof(loaded_relationships) == TYPE_DICTIONARY:
		relationships = _default_relationships()
		for relationship_id in loaded_relationships.keys():
			relationships[relationship_id] = int(loaded_relationships[relationship_id])
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


func reset_new_game() -> void:
	week = 1
	day_index = 0
	money = 0
	energy = 100
	stress = 20
	current_intoxication = 0
	car_condition = 75
	gas = 60
	night_context.clear()
	history.clear()
	current_route_id = "story_intro"

	career_phase = CareerPhase.BEFORE_COMEDY
	reputation = 0
	job_status = JobStatus.EMPLOYED_AT_BOXES
	current_gig_id = ""
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
