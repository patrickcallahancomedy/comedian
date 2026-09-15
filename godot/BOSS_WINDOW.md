# Boss window interaction

`BossWindow` is the visual layer for Troy's supervisor-window visit.

## Scene tree

- `WarningGlow` — simple amber window glow.
- `TroySilhouette` — Patrick's real `Troy silhoutte.png` warning asset.
- `Troy` — the normal Troy character art.
- `AngryTint` — red reaction overlay.
- `PressureController` — gameplay glue for quota/thought pressure. This is intentionally separate from the visual sequence for now.

The image positions live directly in `boss_window.tscn`, so they can be moved and resized in the Godot editor. `boss_window.gd` no longer generates a silhouette with a shader and no longer calculates Troy's position in code.

## Visual flow

1. `IDLE` — empty window.
2. `LIGHT` — the window glows as the first warning.
3. `APPROACH` — the separate Troy silhouette fades in.
4. `WATCHING` — the silhouette fades out and Troy fades in.
5. `ANGRY` — optional reaction when gameplay tells the window Troy is unhappy.
6. `LEAVING` — Troy and the glow fade away.

`boss_window.gd` only owns that visual sequence. It does not decide whether Darren is behind quota and it does not decide what happens to an idea.

The current `boss_pressure_controller.gd` still owns the BOXES-specific pressure rules: showing the second thought and checking quota pace while Troy watches. That can be folded into `boxes_module.gd` as a separate cleanup step once the new visual scene is positioned the way Patrick wants.
