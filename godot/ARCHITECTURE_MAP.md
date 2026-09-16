# COMEDIAN — Skeleton Alpha Architecture Map

The project is intentionally split into boring, obvious pieces so Patrick can open it in Godot, understand where something lives, and replace placeholder work without rebuilding the whole game.

## Core flow

```text
GameState
   ↓
SceneRouter
   ↓
Module Scene
   ↓
module result + permanent GameState changes
   ↓
SceneRouter
   ↓
next module
```

`SaveManager` serializes GameState as readable JSON. It does not own gameplay state.

## Main systems

### `systems/game_state.gd`
Persistent truth:
- day/week
- money/energy
- job status
- career phase
- reputation
- relationships
- current booking
- discovered venues
- milestones
- comedy material

### `systems/scene_router.gd`
One route table for the game. If a placeholder is replaced with a finished scene, usually only its route path needs to change here.

### `systems/save_manager.gd`
New Game / Continue persistence. Saves to readable JSON in Godot's user data folder.

## Module contract

Base script:

` scripts/core/game_module.gd `

A major module has:
- `module_id`
- `next_route_id`
- `finish_module(result)`

Patrick can replace the visual children while keeping the root handoff intact.

## Data

### `data/skeleton_flow.gd`
Temporary career-spine cards. This is scaffolding, not final narrative content.

### `data/gig_data.gd`
Human-editable booking Resource definition.

### `data/gigs/*.tres`
Individual gigs editable in the Godot Inspector: venue, city, set length, pay, travel cost, energy, reputation requirement, milestone, and destination route.

### `data/gig_database.gd`
Small lookup table from a stable gig ID to its `.tres` file.

## Major scenes

```text
scenes/core/main_menu.tscn
scenes/story/story_sequence.tscn
scenes/home/work_module.tscn
scenes/boxes/boxes_module.tscn
scenes/core/career_event_module.tscn
scenes/core/return_choice.tscn
scenes/core/calendar_module.tscn
scenes/home/home_module.tscn
scenes/core/travel_module.tscn
scenes/venues/venue_module.tscn
scenes/stage/stage_module.tscn
scenes/core/ending_module.tscn
scenes/core/developer_jump_menu.tscn
```

## Full route

```text
MAIN MENU
  ↓
OPENING STORY
  ↓
WORK wrapper → real BOXES
  ↓
LUNCH / MIC DISCOVERY
  ↓
HOME STORY BEAT
  ↓
FIRST MIC SETUP
  ↓
VENUE → STAGE
  ↓
AFTER FIRST MIC
  ↓
RETURN CHOICE
  ├─ NOT YET → one week later → RETURN CHOICE
  └─ GO BACK
       ↓
COMEDIAN TITLE REVEAL
       ↓
CALENDAR
       ↓ choose COMEDY
OPEN-MICER PLACEHOLDER
  ↓
LOCAL REGULAR
  ↓
FIRST PAID GIG → VENUE → STAGE
  ↓
REGIONAL COMIC
  ↓
ROAD GIG → TRAVEL → VENUE → STAGE
  ↓
WORK VS COMEDY PRESSURE
  ↓
LEAVE BOXES
  ↓
WORKING COMIC
  ↓
FEATURE → TRAVEL → VENUE → STAGE
  ↓
FIRST HEADLINE → VENUE → STAGE
  ↓
BUILD THE 45 / HOUR
  ↓
HOMETOWN SPECIAL → VENUE → STAGE
  ↓
ENDING / EPILOGUE
```

## The material pipeline

```text
Thought → Premise → Tested Bit → Reliable Joke → Burned Material
```

Every notebook/writing/stage system should use the GameState pipeline rather than keeping its own permanent material database.

## What is safe to edit visually

If it is art/layout, prefer the `.tscn` scene. Backgrounds, portraits, stage art, crowd art, buttons, panels, and placeholder labels should remain real Scene-tree nodes whenever practical.

The existing BOXES scene remains authoritative. The Work module loads it; it does not recreate it.

## What to keep when replacing a placeholder

Keep:
- the root module node/script
- its `module_id`
- its required handoff nodes or update the script paths if you rename them
- its route in/out behavior

Replace freely:
- placeholder artwork
- layout
- copy
- internal gameplay
- animations
- sound

## Debugging

Persistent value wrong → `GameState`

Wrong destination → `SceneRouter`

Save/Continue wrong → `SaveManager`

One activity wrong → that module's scene + script

Visual placement wrong → open the `.tscn` and edit it in Godot

Need to reach a late-game scene quickly → Developer Jump Menu

## Automated architecture checks

`tests/skeleton_state_test.gd` checks route files, full career-flow links, gig resources, return-choice routing, material progression, multiple save/load checkpoints, and randomized GameState mutations.

The BOXES deterministic fuzz test and virtual first-time player continue to test the real warehouse module.

See `HUMAN_EDITABLE_RULES.md`, `HOW_TO_EDIT.md`, and `SKELETON_ALPHA.md` before large architecture changes.
