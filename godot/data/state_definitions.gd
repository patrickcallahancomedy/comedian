# COMEDIAN State Bible v0.1
#
# This file is intentionally boring and human-editable.
# It only defines candidate game states and starting values.
# No gameplay logic should live here yet.
#
# Review this list freely: rename, add, delete, or change defaults.

class_name StateDefinitions
extends RefCounted


# -----------------------------------------------------------------------------
# CORE PLAYER STATE
# Most skill/condition values use a 0-100 scale unless noted otherwise.
# -----------------------------------------------------------------------------

const DEFAULTS := {
	# LIFE / DAY-TO-DAY
	"money": 500,                  # Cash on hand. Not a 0-100 stat.
	"energy": 75,                 # 0 = exhausted, 100 = fully rested.
	"stress": 20,                 # 0 = calm, 100 = overwhelmed.
	"available_time_blocks": 4,   # Usable chunks of time left today. Not 0-100.
	"sleep_quality": 60,          # How well Darren has been sleeping lately.
	"physical_health": 70,        # General physical condition.
	"fitness": 35,                # Strength/cardio/general fitness habit.
	"nutrition": 50,              # How consistently Darren is eating decently.

	# ALCOHOL / CURRENT CONDITION
	"current_intoxication": 0,    # 0 = sober, 100 = incapacitated.
	"drinking_habit": 10,         # How embedded drinking is in Darren's routine.
	"alcohol_tolerance": 20,      # Higher = takes more alcohol to feel impaired.

	# CAR / TRAVEL
	"car_condition": 75,          # 0 = barely running, 100 = excellent condition.
	"gas": 60,                    # Current fuel level.
	
	# PERSONAL / LIFE SKILLS
	"work_ethic": 55,             # Willingness to show up and do the work.
	"reliability": 60,            # How consistently Darren follows through.
	"organization_skill": 30,     # Planning, scheduling, keeping things together.
	"pressure_handling": 40,      # Ability to function when stakes/stress are high.
	"resilience": 50,             # Ability to recover after failure, bombs, setbacks.
	"social_skill": 40,           # General ability to connect with people.
	"comedy_drive": 25,           # How strongly comedy currently pulls Darren.

	# BOXES / DAY JOB
	"boxes_skill": 20,            # Ability at the warehouse job itself.
	"job_satisfaction": 35,       # 0 = hates the job, 100 = genuinely loves it.

	# COMEDY FUNDAMENTALS
	"writing_skill": 10,          # Ability to create jokes/material.
	"editing_skill": 5,           # Ability to cut weak wording/sections.
	"material_expansion": 5,      # Ability to build tags, act-outs, callbacks, length.
	"stage_presence": 5,          # Comfort and command while physically onstage.
	"delivery_skill": 5,          # Ability to sell written material verbally.
	"timing_skill": 5,            # Pauses, pacing, rhythm, laugh spacing.
	"joke_memory": 20,            # Ability to remember planned material onstage.
	"crowd_reading": 5,           # Ability to understand what the room needs.
	"crowd_work": 0,              # Ability to interact directly with audience members.
	"improv_skill": 5,            # Ability to create/respond in the moment.
	"hosting_skill": 0,           # Ability to host a comedy show well.

	# COMEDY BUSINESS / CAREER SUPPORT SKILLS
	"networking_skill": 20,       # Ability to build useful comedy relationships.
	"social_media_skill": 10,     # Ability to use social platforms effectively.
	"video_skill": 10,            # Ability to shoot/edit useful comedy content.
	"promotion_skill": 10,        # Ability to market shows/content.
	"ticket_sales_skill": 5,      # Ability to personally draw paying audience.
	"show_running_skill": 0,      # Ability to organize and run a live comedy show.

	# ACT / STYLE AXES
	# These describe the act rather than whether it is "good."
	"act_darkness": 25,           # 0 = very clean/light, 100 = extremely dark.
	"act_scriptedness": 60,       # 0 = very loose/improvised, 100 = tightly scripted.
	"act_storytelling": 25,       # 0 = short/punchy, 100 = long-form storytelling.
}


# -----------------------------------------------------------------------------
# EXPANDABLE RECORDS
# These are kept separate because there can eventually be many people, venues,
# jokes, cars, jobs, etc. They are templates only for now.
# -----------------------------------------------------------------------------

const RELATIONSHIP_DEFAULT := 0   # Intended range: -100 to 100.

const JOKE_DEFAULTS := {
	"strength": 0,
	"familiarity": 0,
	"length_seconds": 0,
	"times_performed": 0,
	"rooms_tested": 0,
	"laughs": 0,
	"bombs": 0,
}

const VENUE_DEFAULTS := {
	"familiarity": 0,
	"reputation": 0,
	"times_performed": 0,
}

# One-night context is not a permanent skill. Modules write/read this record
# during a comedy night, then the next day can clear it.
const NIGHT_CONTEXT_DEFAULTS := {
	"arrival_minutes_before_signup": 0,
	"drive_delay_minutes": 0,
	"drive_collisions": 0,
	"drive_missed_turns": 0,
	"picked_up_nate": false,
}
