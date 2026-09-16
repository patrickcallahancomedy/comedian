# BOXES fuzz testing

The fuzz harness loads the real `boxes_module.tscn` scene and drives randomized,
deterministic player behavior through it. It checks gameplay invariants after
every simulated frame and prints a reproducible seed plus recent action trace
if a run fails.

From the repository root:

```bash
godot --headless --path godot --fixed-fps 120 \
  --script res://tests/boxes_fuzz.gd -- --runs=1000 --seed=1
```

Reproduce a reported failure:

```bash
godot --headless --path godot --fixed-fps 120 \
  --script res://tests/boxes_fuzz.gd -- --runs=1 --seed=REPORTED_SEED
```

The GitHub Actions workflow derives its starting seed from the commit SHA. A
rerun of the same commit therefore exercises the same 1,000 playthroughs.

