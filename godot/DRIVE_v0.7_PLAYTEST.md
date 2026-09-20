# DRIVE v0.7 — playable completion pass

Based on skeleton-alpha cad25e9, on a separate drive-playtest-v0.7 branch.
Open project.godot in Godot and press F6 with scenes/drive/drive_module.tscn open,
or F5 (DRIVE is already this branch's main scene). External assets stay external.
The original car position, road profiles and authored scene geometry are preserved.

## Controls

GO / Space / W / Up starts the trip. LEFT/RIGHT or A/D or arrow keys steer.
In neighborhood/downtown/parking, steering rotates the view and selects the next
street. This preserves the existing queued steering behavior. At a blocked edge,
turn toward an available road and press GO. On main road/highway, steer between
lanes. Follow the blue GPS route; get fully into the right lane for the highway exit.
At parking, DRIVE AGAIN restarts for practice. HEAD INSIDE commits consequences
once and opens the existing venue module. Practice replays do not spend gas.

## Changes

- Trip clock starts on GO, not while reading instructions.
- Actual visible lane position determines highway-exit success and contacts.
- Missed exit adds another section; wrong turns take real extra distance.
- Equally short alternative streets are no longer penalized.
- Highway lane markings, car-sprite traffic, corrected scenery scroll direction.
- Base speed 680 instead of 520: preserves long blocks while reducing dead time.
- Blue route uses the same city data as the road view.
- Low energy produces eyelid closures, gentle lane drift and slower steering.
- One passive Nate notification briefly covers part of the road. No response action.
- Arrival, replay and guarded single state handoff now work.
- Optional world_seed on CityMap reproduces a map for debugging (0 = random).

## Verification actually performed

Godot 4.5.1 Linux, native compatibility renderer. The repository identifies itself
as Godot 4.7; that exact version and the browser export were NOT tested here.

1. Existing car_drive_test.gd: PASS after updating its exit fixture to physically
   place the car in the right lane rather than only setting a lane number.
2. drive_playtest.gd: 100 complete control-driven trips, seeds 1–100. Half use low
   energy; half deliberately take a longer route. All reach parking and return an
   arrival result. 48.97–56.62 simulated seconds across these runs. These are
   scripted drivers reading the GPS graph, not human reaction-time measurements.
3. drive_regression.gd: PASS. Missed-exit recovery; contact debounce; 10,000 random
   input frames across the five profiles; replay reset; gas applied once;
   correct handoff to the venue. Random steering is checked for valid state,
   not guaranteed arrival (players can circle indefinitely).
4. Native rendered scene inspected at 430×764: start, neighborhood, main road,
   highway, downtown, parking, phone notification, arrival. Visual check led to
   replacing traffic blocks with the existing sprite and adding lane markings.
5. git diff --check: PASS.

Reproduce from this directory:

    godot --headless --editor --import --quit
    godot --headless --script res://tests/car_drive_test.gd
    godot --headless --script res://tests/drive_playtest.gd
    godot --headless --script res://tests/drive_regression.gd

The visual test requires a display and writes screenshots under /tmp on Linux:

    godot --script res://tests/drive_visual.gd

## Playability assessment, not a fabricated human fun verdict

The complete trip now has a readable progression: route choice, overtaking,
highway exit, tighter downtown turns, parking. Corrections have visible outcomes,
and a mistake can be recovered without restarting. The closest remaining risk
is the switch between turn steering and lane steering; the neighborhood also
contains long straight stretches. The five existing profiles remain prototypes:
plain scenery, no sound, and no new final art in this pass.

The older idea of a single town with 6–8 turns is not fully represented by the
current five-profile build; this pass preserves the newer implementation rather
than replacing it. Phone interruption and tiredness are implemented but their
subjective annoyance/difficulty require Patrick's playtest. Unbounded wrong turns
can exceed a minute. No human playtester was involved, and no automated result
can certify that this is fun.

Next playtest: drive once rested, once tired, and take one intentional wrong turn.
The useful feedback is where steering surprises you, when you look at GPS, and
whether you'd voluntarily replay. Tune those before adding more systems.
