# COMEDIAN — Skeleton Alpha

This document is the living status board for the ugly-but-complete version of the game.

## Goal

A player can begin at the title screen, play the existing opening/BOXES module, move through the entire comedy career, perform the hometown special, and reach an ending. Placeholder screens are acceptable. Dead architecture is not.

## Status key

- **PLAYABLE** — real interaction exists and the module can be played now.
- **STRUCTURAL** — working reusable architecture exists, but the final gameplay/art is not built.
- **PLACEHOLDER** — connected route card standing in for a future scene/module.

## Current modules

| Module | Status | Main files |
| --- | --- | --- |
| Main menu / New Game / Continue | STRUCTURAL | `scenes/core/main_menu.tscn` |
| Opening storybook | PLAYABLE | `scenes/story/story_sequence.tscn` |
| BOXES | PLAYABLE | `scenes/boxes/boxes_module.tscn` |
| Work wrapper | STRUCTURAL | `scenes/home/work_module.tscn` |
| Career event cards | PLACEHOLDER | `scenes/core/career_event_module.tscn` |
| Choice / conversation | STRUCTURAL | `scenes/core/choice_module.tscn` |
| Calendar | STRUCTURAL | `scenes/core/calendar_module.tscn` |
| Home | STRUCTURAL | `scenes/home/home_module.tscn` |
| Travel | STRUCTURAL | `scenes/core/travel_module.tscn` |
| Venue | STRUCTURAL | `scenes/venues/venue_module.tscn` |
| Stage | STRUCTURAL | `scenes/stage/stage_module.tscn` |
| Ending / epilogue | PLACEHOLDER | `scenes/core/ending_module.tscn` |
| Developer jump menu | STRUCTURAL | `scenes/core/developer_jump_menu.tscn` |

## Full Skeleton Alpha route

```text
TITLE
  -> OPENING STORY
  -> BOXES
  -> LUNCH / DISCOVER MIC
  -> HOME
  -> FIRST MIC SETUP
  -> VENUE
  -> STAGE: FIRST MIC
  -> AFTER FIRST MIC
  -> RETURN TO COMEDY CHOICE
       -> NOT YET -> ONE WEEK LATER -> choice again
       -> GO BACK
  -> COMEDIAN TITLE REVEAL
  -> OPEN-MICER PHASE
  -> LOCAL REGULAR
  -> FIRST PAID GIG
  -> REGIONAL COMIC
  -> TRAVEL
  -> REGIONAL GIG
  -> WORK VS COMEDY PRESSURE
  -> LEAVE BOXES
  -> WORKING COMIC
  -> FEATURE WEEKEND
  -> FIRST HEADLINE
  -> BUILD THE 45 / HOUR
  -> HOMETOWN SPECIAL
  -> ENDING / EPILOGUE
```

The career event cards above are deliberately compressed. As real modules are built, replace one card at a time without changing the routes around it.

## Persistent systems

`GameState` owns persistent player data. `SaveManager` writes/loads it as readable JSON. `SceneRouter` owns route IDs. `GigData` `.tres` resources describe bookings. `SkeletonFlow` describes temporary career milestone cards.

## Material pipeline

```text
Thought -> Premise -> Tested Bit -> Reliable Joke -> Burned Material
```

Every future writing, notebook, stage, and set-building module should use the same GameState lists rather than creating permanent material storage of its own.

## Career phases

```text
Before Comedy
First Mic
Open-Micer
Local Regular
Regional Comic
Working Comic
Headliner
Special
Complete
```

## Skeleton rules

1. Keep scenes visually editable in Godot.
2. Keep art as ordinary asset files.
3. Do not replace Patrick's manually positioned `.tscn` scenes with generated rewrites.
4. Put long-term state in GameState, not individual modules.
5. Route scene changes through SceneRouter.
6. Make tuning values Inspector-editable when practical.
7. Do not polish a placeholder merely because it is ugly. Replace it only when working on that real part of the game.

## Automated checks

`tests/skeleton_state_test.gd` verifies route files, career-flow links, gig resources, material progression, save/load, and randomized GameState mutations.

The existing BOXES fuzz test and virtual first-time player remain active. GitHub Actions runs the structural/state test plus BOXES tests on `skeleton-alpha`.

## Definition of Skeleton Alpha complete

Skeleton Alpha is structurally complete when New Game can reach the ending, Continue can restore persistent career state, every major future module has a stable handoff, and Patrick can replace placeholder visuals/gameplay without needing to rebuild the game's plumbing.
