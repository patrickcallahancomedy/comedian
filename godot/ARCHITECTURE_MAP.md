# COMEDIAN — Skeleton Alpha Architecture Map

This document explains the project structure in plain language so Patrick can open the project in Godot and know where to work.

The architecture goal is simple:

> A complete game from New Game to Ending, built from readable Godot scenes and scripts that Patrick can replace and extend by hand.

## Core flow

```text
Player starts game
    ↓
GameState stores persistent information
    ↓
SceneRouter chooses the next module
    ↓
A module runs
    ↓
Module returns a small result
    ↓
GameState applies the result
    ↓
SceneRouter moves to the next module
```

Modules should not permanently own career data. They report what happened, then the central state keeps it.

## Main systems

### GameState
Planned location:

```text
scripts/core/game_state.gd
```

Purpose:
- current day/week
- money
- energy
- job status
- comedy career level
- reputation
- relationships
- discovered venues
- bookings
- premises and jokes
- milestone progress

This is the main source of truth for the player's career.

### SceneRouter
Planned location:

```text
scripts/core/scene_router.gd
```

Purpose:
- load the next scene/module
- keep transitions understandable
- prevent scene-change logic from being scattered across the project

If you want to understand where the game goes next, this should be the first place to look.

### SaveManager
Planned location:

```text
scripts/core/save_manager.gd
```

Purpose:
- save GameState
- load GameState
- start a new game
- support Continue

### Module contract

Every major gameplay module should follow the same basic pattern:

```text
GameState → Module → Result → GameState → SceneRouter
```

Example BOXES result:

```text
quota_met = true
premises_saved = 1
troy_catches = 0
energy_change = -5
```

Example gig result:

```text
money_change = 50
reputation_change = 3
material_tested = ["premise_001"]
```

The exact data format will stay small and readable.

## Folder map

```text
godot/
├── assets/          Art, images, audio and other normal external assets
├── data/            Human-readable game data and milestone definitions
├── scenes/          Godot scenes Patrick can open and edit visually
│   ├── boxes/       Existing BOXES gameplay
│   ├── story/       Existing storybook intro and story scenes
│   ├── core/        Main menu, game shell, loading/root scenes
│   ├── placeholders/Temporary Skeleton Alpha modules
│   ├── home/        Home/notebook/rest modules
│   ├── stage/       Stand-up performance systems
│   └── venues/      Venue and gig scenes
├── scripts/         Scripts attached to scenes
│   ├── boxes/
│   ├── story/
│   ├── core/
│   ├── home/
│   ├── stage/
│   └── venues/
├── systems/         Small shared systems that are not visual scenes
└── tests/           Fuzz tests, virtual players and architecture tests
```

## What Patrick should edit visually

If something is visual, prefer editing the `.tscn` scene in Godot.

Examples:
- move a character
- resize a button
- replace a background
- change a venue layout
- place a crowd
- adjust a stage
- style a placeholder screen

Those should normally be visible nodes in the Scene tree.

Do not rebuild visual scenes in code unless there is a strong reason.

## Planned reusable module types

We do not want a separate architecture for every single day of Darren's life.

Instead, Skeleton Alpha will build reusable shells:

```text
StoryModule
ChoiceModule
PlaceholderModule
CalendarModule
HomeModule
WorkModule
TravelModule
VenueModule
StageModule
ResultsModule
EndingModule
```

A specific event can use one of these shells with different data.

For example:

```text
FIRST PAID GIG
    ↓
TravelModule
    ↓
VenueModule
    ↓
StageModule
    ↓
ResultsModule
```

## Full Skeleton Alpha route

The first complete architecture pass should support this path:

```text
NEW GAME
↓
Opening Story
↓
BOXES
↓
Lunch / Mic Discovery
↓
Home
↓
First Mic
↓
Return To Mic
↓
COMEDIAN title / main loop begins
↓
Open-Micer
↓
Local Regular
↓
First Paid Gig
↓
Regional Comic
↓
Work vs Comedy Pressure
↓
Leave BOXES
↓
Working Comic / Feature
↓
First Headline
↓
Build 45
↓
Hometown Special
↓
Ending / Epilogue / Credits
```

During Skeleton Alpha, many of these can be simple placeholder screens with a Continue button.

The important part is that the real state and routing work underneath them.

## Placeholder rule

A placeholder is not a dead-end mockup.

It must:
- load correctly
- receive the expected game state
- clearly say what future module it represents
- have a visible Continue button or choice
- return a real result to the game
- route to the next module
- be easy for Patrick to replace later

## Safe replacement rule

When Patrick replaces a placeholder with real art/gameplay, the surrounding architecture should not need to change.

For example, if this exists:

```text
RegionalGig
├── Background
├── PlaceholderLabel
└── ContinueButton
```

Patrick should be able to replace the visual children with a real venue while keeping the root/module handoff intact.

## Current real modules

Already playable:
- Opening story system
- BOXES gameplay
- Troy pressure sequence
- Notebook premise-saving interaction

These should be plugged into the larger architecture rather than rewritten during the skeleton sprint.

## Skeleton Alpha priority

Do not polish before the complete route works.

Priority order:

```text
1. State
2. Routing
3. Save/load
4. Full route from beginning to ending
5. Module interfaces
6. Developer jump tools
7. Tests
8. Art and polish later
```

If a gray screen successfully moves the game forward and stores the right result, it is doing its job for Skeleton Alpha.

## Where to look when something breaks

If persistent information is wrong:
```text
GameState
```

If the game goes to the wrong scene:
```text
SceneRouter
```

If saving/loading is wrong:
```text
SaveManager
```

If one activity behaves incorrectly:
```text
that module's scene + script
```

If art is misplaced:
```text
open that scene in Godot and edit the nodes visually
```

## Human-editable requirement

This architecture must follow `HUMAN_EDITABLE_RULES.md`.

If a system works but Patrick cannot reasonably inspect or extend it in Godot, simplify it before building more on top of it.
