extends Node

## GameState is the one place for information that must survive between modules.
##
## Put long-term facts here: day, money, career progress, relationships, venues,
## bookings, and comedy material.
##
## Do NOT put scene transitions here. SceneRouter will decide where the player
## goes next. Individual modules should report what happened, then update this
## state through small, obvious methods.

signal state_reset
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
# Material moves through these lists over Darren's career:
# Thought -> Premise -> Tested Bit -> Reliable Joke -> Burned Material

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


## Add a premise safely. BOXES and future writing modules can use this instead
## of owning their own permanent premise lists.
func add_premise(text: String) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty() or premises.has(clean_text):
		return
	premises.append(clean_text)


## Reset only persistent game information. Visual scenes are responsible for
## resetting their own temporary UI/gameplay state when they load.
func reset_new_game() -> void:
	week = 1
	day_index = 0
	money = 0
	energy = 100

	career_phase = CareerPhase.BEFORE_COMEDY
	reputation = 0
	job_status = JobStatus.EMPLOYED_AT_BOXES

	relationships = {
		"ray": 0,
		"nate": 0,
		"troy": 0,
		"home": 0,
	}

	discovered_venues.clear()
	bookings.clear()
	milestones.clear()

	thoughts.clear()
	premises.clear()
	tested_bits.clear()
	reliable_jokes.clear()
	burned_material.clear()

	state_reset.emit()
