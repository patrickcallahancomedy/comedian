# DRIVE v0.8 — simplification + visual polish

Based directly on `drive-playtest-v0.7`. This is a subtraction pass, not a rewrite.

## Playable route

1. Neighborhood
2. Highway
3. Downtown / venue arrival

The v0.7 main-road and parking profiles remain in source for rollback/reuse, but are not part of the active v0.8 trip.

## Controls

- Tap START once.
- After departure, the primary touch verb is LEFT / RIGHT.
- On streets, steering chooses the next road and resumes movement automatically.
- On the highway, steering changes lanes.
- Missing the highway exit extends the road and reroutes instead of restarting.

## Intentionally parked for this pass

- Stop-sign pauses
- One-way-street rules
- Fatigue eyelid closures / drift
- Nate phone interruption
- Separate main-road phase
- Separate parking minigame phase

These systems are not being treated as bad ideas. They are removed from the active playtest so the base drive can be judged without extra rules.

## Visual pass

- Smaller, quieter GPS.
- Muted illustrated road/ground palette.
- Road shoulders and clearer lane markings.
- Permanent phase/debug labels hidden.
- Context text limited to START, EXIT, REROUTING, TURN and ARRIVED.
- Mobile controls become two large steering buttons after START.
- No generated or embedded art was added; the existing external car PNG remains an ordinary asset.

## Verification

The branch includes:
- `tests/car_drive_test.gd`
- `tests/drive_playtest.gd`
- `tests/drive_regression.gd`
- `tests/drive_visual.gd`

The branch-specific GitHub workflow runs the first three tests before exporting the web build.
