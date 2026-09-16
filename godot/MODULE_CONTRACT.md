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

## What Patrick needs to keep

A module scene should keep:

1. its root node,
2. the script attached to that root,
3. its `module_id`,
4. its `next_route_id` while Skeleton Alpha is using a fixed route.

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

## Why this exists

BOXES, Home, Travel, Stage, venues, story scenes, and temporary placeholders can all look completely different while still connecting to the same game spine.

A future finished module can replace a placeholder without rebuilding the router or save architecture.
