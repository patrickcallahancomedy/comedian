# COMEDIAN — How Patrick Can Safely Edit Skeleton Alpha

This file is the practical handoff guide. The architecture is supposed to stay understandable enough that you can build directly in Godot without needing generated code every time.

## The main rule

If you are changing how something **looks**, edit the `.tscn` scene in Godot first.

If you are changing what persistent information the game remembers, look in `systems/game_state.gd`.

If you are changing where a scene goes next, look at the scene's exported **Next Route ID** or `systems/scene_router.gd`.

## Replacing placeholder art

Open the relevant `.tscn` in Godot. In most Skeleton Alpha scenes, the root node owns the architecture and the visual children underneath it are replaceable.

For example, in `stage_module.tscn`:

```text
StageModule        <- KEEP root + script
└── Background     <- safe to rebuild
    ├── StageArt   <- safe to replace with your art
    └── Layout     <- safe to restyle/reposition
```

Do not remove the root script or rename nodes that its script explicitly references unless you also update those references.

## Replacing a placeholder career card with a real module

Example: you build a real Regional Comic module.

1. Create the new scene somewhere obvious, such as `scenes/venues/regional_phase.tscn`.
2. Give the root a small module script based on `GameModule`.
3. When the module is done, call `finish_module(result)` with its `next_route_id` set appropriately.
4. In `systems/scene_router.gd`, change only the `regional_comic` route path from the generic career event scene to your new scene.
5. Leave the routes before and after it alone.

Nothing else in the game should need to know that the placeholder was replaced.

## Editing the full career order

Open:

`data/skeleton_flow.gd`

Every temporary career card has a readable entry with fields such as:

- title
- description
- milestone
- required_milestone
- career_phase
- job_status
- reputation_floor
- gig_id
- next_route

This file is temporary scaffolding. As real gameplay replaces an event, the route can point to the finished module instead.

## Adding or editing a comedy gig

Open `data/gigs/` in Godot.

Each booking is a normal `.tres` Resource. You can edit fields in the Inspector:

- gig title
- venue
- city
- set length
- pay
- travel cost
- energy cost
- reputation requirement
- completion milestone
- route after the performance

To add a brand-new gig, duplicate an existing `.tres`, give it a new `gig_id`, and add one line for it to `data/gig_database.gd`.

## Editing Stage gameplay

Visual scene:

`scenes/stage/stage_module.tscn`

Logic:

`scripts/stage/stage_module.gd`

The current crowd score is intentionally primitive. You can eventually replace that internal gameplay while preserving these handoff responsibilities:

1. Read the active booking.
2. Let the player perform.
3. Update material/career consequences in GameState.
4. Mark the booking milestone.
5. Return a result and route onward.

## Editing BOXES

Continue editing the existing files exactly as before:

- `scenes/boxes/boxes_module.tscn`
- `scripts/boxes/boxes_module.gd`

The larger game loads that real scene inside the Work shell. Do not rebuild BOXES inside Work.

The Work wrapper lives at:

`scenes/home/work_module.tscn`

Its job is only to launch BOXES, collect the result, and route the larger game.

## Testing one part without replaying everything

Run the project and choose:

`DEVELOPER JUMP MENU`

You can jump directly to:

- opening story
- BOXES
- first mic
- calendar
- regional gig
- feature gig
- first headline
- hometown special
- ending

The jump menu seeds enough temporary state for those modules to open safely.

## Save data

The game writes a readable JSON save through `systems/save_manager.gd`.

Persistent values come from `systems/game_state.gd`. If a new system needs to survive closing the game, add it there and add it to both `to_save_data()` and `load_save_data()`.

Do not make separate save files inside gameplay modules.

## Before a big visual edit

Commit the current working scene first. Then edit in Godot. Once your manual layout is committed, treat that scene as authoritative and make future code changes around it rather than regenerating the entire `.tscn`.

## What not to do

- Do not embed PNGs as encoded strings.
- Do not generate visual layouts entirely from code when they should be movable in Godot.
- Do not hard-code every venue into Stage logic.
- Do not let individual modules own permanent copies of money, career level, relationships, or joke material.
- Do not scatter scene file paths throughout scripts; add a route to SceneRouter instead.
- Do not turn one script into the whole game.

The desired workflow is: plumbing stays boring and stable; art, writing, and gameplay get replaced one module at a time.
