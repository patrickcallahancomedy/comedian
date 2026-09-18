# COMEDIAN — Module Contract

Every major playable chunk follows the same simple rule:

```text
GameState
  ↓
SceneRouter
  ↓
GameModule
  ↓
finish_module(result)
  ↓
SceneRouter
  ↓
Next Module
```

## Core rule: no orphan minigames

Every playable module must connect to the simulation.

A module must do at least one of these:

- READ one or more states from GameState and use them to change gameplay.
- WRITE one or more states/history facts back to GameState because of what happened.
- Usually it should do both.

A minigame that is fun but has no effect on Darren's life is not finished.

Examples:

- Driving can read intoxication, energy, stress, time pressure, and car condition.
- Driving can write time passed, stress, money spent, car condition, lateness, or incident history.
- BOXES can read energy, stress, work ethic, BOXES skill, and Troy relationship.
- BOXES can write money, energy, BOXES experience, Troy relationship, shift history, and job consequences.
- Stage can read stage presence, timing, joke familiarity, intoxication, crowd-reading, and current material.
- Stage can write joke history, stage minutes, reputation, relationships, confidence, and booking consequences.

## Every module script should declare its state contract

Near the top of each module script, keep a short human-readable block like:

```gdscript
# STATE READS:
# energy, stress, intoxication, car_condition

# STATE WRITES:
# energy, stress, money, time

# HISTORY:
# drives_completed, crashes, arrived_late

# RESULT:
# success, travel_minutes, incident
```

This is documentation for humans first. It should stay simple enough that Patrick can open the script and immediately understand why the module matters.

## What Patrick needs to keep

A module scene should keep:

1. its root node,
2. the script attached to that root,
3. its `module_id`,
4. its routing handoff.

Everything visual underneath the root can be replaced, rearranged, or rebuilt in Godot.

## Permanent state vs. result

Permanent changes belong in `GameState` before the module finishes.

Examples:

```gdscript
GameState.money += 50
GameState.mark_milestone("first_paid_gig")
GameState.promote_tested_bit_to_reliable_joke(0)
```

Then the module reports a small readable result:

```gdscript
finish_module({
    "pay": 50,
    "crowd_result": 72,
})
```

The result is a handoff/debug summary. It is not a second save system.

## State definitions

The canonical list of simulation states lives in:

`res://data/state_definitions.gd`

When a new module needs a state that does not exist yet, add/approve that state there rather than inventing a private permanent stat inside the module.

Temporary local values are fine. Permanent facts about Darren, his material, relationships, venues, work, car, or career belong in the shared simulation model.

## Why this exists

BOXES, the car game, Home, Travel, Stage, venues, story scenes, and future minigames can all look completely different while still affecting the same Darren.

The player should be able to spend time doing almost anything, and the game should remember enough for that choice to matter later.

A future finished module can replace a placeholder without rebuilding the router, save architecture, or simulation rules.
