# COMEDIAN — Human-Editable Project Rules

This file is a hard constraint for the Skeleton Alpha build.

The project must stay understandable and editable by Patrick directly in Godot. A system is not considered finished if it only works technically but becomes difficult to inspect, move, replace, or extend by hand.

## 1. Normal Godot files only

- Art stays as normal files in `assets/` such as PNGs.
- Scenes stay as `.tscn` files.
- Logic stays as `.gd` files.
- Game data should use readable Godot resources, JSON, or small dictionaries when appropriate.
- Do not embed images as base64 or encoded text.
- Do not hide major game content inside generated blobs or giant strings.

## 2. Visual work belongs in scenes

If Patrick should be able to move, resize, replace, or restyle something, it should normally exist as a visible node in the Godot Scene tree.

Good:

```text
Venue
├── Background
├── Stage
│   ├── Darren
│   └── Microphone
├── Crowd
└── HUD
```

Avoid creating visual layouts entirely through code unless there is a strong reason.

## 3. Descriptive node names

Use names that explain what the node is.

Good:
- `TroySilhouette`
- `QuotaHUD`
- `WriteIdeaButton`
- `StageSpotlight`

Avoid:
- `Control7`
- `TextureRect3`
- `Thing`

## 4. Small scripts with one clear job

Do not build giant all-purpose scripts.

Examples:
- `game_state.gd` owns persistent game state.
- `scene_router.gd` owns scene/module transitions.
- `save_manager.gd` owns saving and loading.
- A module script owns only that module's gameplay.

If a file becomes difficult to scan or contains several unrelated systems, split it before adding more.

## 5. Prefer Inspector-editable values

Values Patrick may reasonably want to tune should use exported variables when practical.

Examples:
- timing
- payouts
- energy cost
- reputation requirements
- set length
- difficulty values

Do not bury ordinary tuning values deep inside unrelated code.

## 6. Do not hard-code art into gameplay logic

Gameplay code may reference named nodes and resources, but replacing a visual asset should not require rewriting the game system.

Patrick should usually be able to replace a PNG, reposition a node, or rebuild the visuals beneath an existing root without changing the architecture.

## 7. Scene files edited by Patrick become authoritative

Once Patrick manually positions or edits a scene in Godot, do not replace the entire `.tscn` with a generated rewrite just to make another change.

Make the smallest safe edit possible and preserve his layout work.

## 8. Obvious module boundaries

Every major playable module should have a clear root scene and script.

Example:

```text
scenes/boxes/boxes_module.tscn
scripts/boxes/boxes_module.gd
```

A module should receive state, run its gameplay, and report a result. Persistent career data should live outside the module.

## 9. One obvious source of persistent truth

Long-term player information belongs in `GameState`, not copied across several scenes.

Examples:
- day/week
- money
- career level
- reputation
- relationships
- premises/jokes
- discovered venues
- completed milestones

Modules may temporarily work with this data but should not become competing save systems.

## 10. No mystery transitions

Scene changes should go through one understandable routing system instead of being scattered across many scripts.

Patrick should be able to look in one place and understand where the game can go next.

## 11. Comments explain why

Comment unusual behavior, architecture decisions, and handoff points.

Avoid bloating files with comments that simply restate obvious code.

Especially document:
- why a state transition happens
- what a module is expected to return
- what Patrick can safely replace
- what must remain intact for the architecture to work

## 12. Placeholder visuals are intentionally replaceable

Skeleton Alpha placeholders should be simple Godot scenes, not disposable hacks.

A placeholder scene should make it obvious:
- what the future module is
- what data it receives
- what result it returns
- which visual children Patrick can delete and replace

## 13. Preserve working checkpoints

Before large architecture changes, keep a known-good commit.

Prefer small commits with names that describe one system. Do not combine unrelated architecture, art, and gameplay changes into one giant commit when avoidable.

## 14. Patrick must be able to continue without ChatGPT

Before considering a new architecture system complete, ask:

> Could Patrick open this in Godot tomorrow, understand the Scene tree, identify the relevant script, and safely begin replacing the placeholder with his own work?

If the answer is no, simplify it.

## Skeleton Alpha rule

During the architecture sprint, working and understandable beats polished.

The goal is a complete playable spine from New Game to ending, built from boring, readable systems that can later be replaced with real art, writing, and gameplay without rebuilding the foundation.
