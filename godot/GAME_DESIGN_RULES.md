# COMEDIAN — GAME DESIGN RULES

This file contains locked design constraints for COMEDIAN.
These are not suggestions. Do not casually reinterpret them while building new features.

## 1. The game is made of microgames

COMEDIAN is not a life simulator with minigames added on top.

The life simulation is created by a chain of tiny playable interactions.

Typical playable interaction length:
- about 10 seconds
- usually under 1 minute
- end before the mechanic gets stale

A module should:
1. read only the state it needs
2. give the player one small playable problem
3. return a simple result
4. let the simulation interpret that result
5. move on quickly

The player should feel:
"I played a bunch of little things and somehow that became a story."

## 2. One microgame = one primary verb

Every microgame should be describable immediately with a one- or two-word command.

Examples:
- DRIVE
- SIGN UP
- PERFORM
- GET DRESSED
- SORT BOXES
- WRITE
- AVOID TROY

If the player action needs a long explanation or contains an "and," the game is probably too big and should be split.

One simple action may still read or change many states. The state system creates depth underneath the action; the player should not be asked to perform several unrelated actions at once.

## 3. Home is the decompression / control center

Most of the game should move quickly from one microgame to the next.

Home is where the pace can slow down.

Home is where the player can:
- reflect on what happened
- look at jokes / notebook
- see messages
- understand consequences
- check money, schedule, relationships, opportunities
- make broader decisions about what Darren does next

Rhythm:

PLAY -> PLAY -> PLAY -> PLAY -> HOME -> UNDERSTAND WHAT HAPPENED -> GO BACK OUT

## 4. Small world. Small mechanics. Deep consequences. Heavy reuse.

This is a solo game being built by Patrick with ChatGPT.

Do not solve problems with GTA-scale scope.

Prefer:
- a few strong venues
- a few important recurring NPCs
- small reusable maps
- small reusable minigames
- repeatable systems whose context changes
- persistent consequences that make repeated content feel different

Do not add large systems when a tiny mechanic plus state can create the same feeling.

## 5. The simulation must stay underneath the fun

Do not turn the game into visible RPG math.

States matter because they alter what the player physically experiences.

Examples:
- tiredness can make Darren's eyes close, steering drift, timing worsen
- intoxication can alter perception, memory, reaction, judgment
- arriving late can remove time to socialize or prepare
- relationships can change who helps, ignores, or books Darren later

Avoid:
"TIREDNESS +8"
when the game can instead make the player feel tired.

The important long-term feeling is delayed recognition:
"I did this five minigames ago and now it is affecting me."

## 6. Comedy authenticity is a core mechanic

COMEDIAN must be funny and must feel like actual stand-up comedy culture.

Narrative, jokes, social interactions, awkwardness, hierarchy, bombing, hanging out, writing, hosting, bookers, comics, and room dynamics are not flavor added after systems work.

They are part of the game itself.

Patrick's real comedy experience is the authority for:
- how comics talk
- what happens at open mics
- what social interactions feel true
- what is funny
- what is embarrassing
- what a comedy night feels like
- how material develops

Build systems around that knowledge. Do not replace it with generic game-design assumptions.

## 7. Authored destination, simulated journey

The game can have authored major destinations, but the path between them should emerge from play and remembered state.

A player may:
- progress quickly
- stay an open-micer
- keep working at BOXES
- quit too early
- become a strong writer but weak performer
- become social but unreliable
- barely pursue comedy
- create strange personal stories through repeated choices and minigames

Do not force every run through the same clean career ladder.

## 8. Modules create facts; the simulation creates meaning

A module should report concrete facts.

Example:

DRIVE RESULT
- arrived 8 minutes before signup
- missed 1 turn
- used gas
- Darren was exhausted

The simulation decides what those facts mean next:
- how much pre-show time remains
- whether signup is still possible
- whether Darren is more stressed
- whether later driving feels worse

Do not make every module responsible for the whole narrative tree.

## 9. Locked DRIVE design direction

DRIVE has one verb: drive.

Main view:
- close top-down road view
- automatic forward motion
- LEFT / RIGHT decisions at intersections
- immediately understandable
- no separate phone/dialogue/relationship mechanic inside DRIVE

Minimap:
- tiny town / corn-maze-like street network
- Darren's tiny moving car
- destination
- visible blue route
- roughly 6-8 turns
- player glances between the close road and the whole route

Wrong turns:
- visibly leave the route
- create extra driving
- quietly cost time
- no giant RPG penalty message

State should affect DRIVE itself:
- tiredness: eyelids closing, micro-sleeps, drift
- car condition: travel/handling can worsen
- intoxication can affect DRIVE later if that state is present

The route itself is the timer.
The player should usually discover the important consequence after arriving, not through a score screen.

## 10. Preserve fun before adding systems

If a tiny game is already fun, do not "improve" it by making it complicated.

Add consequences underneath it.

The player-facing mechanic should usually stay simpler than the systems behind it.

## 11. Production split

Patrick owns:
- comedy truth
- writing
- jokes
- character interactions
- visual taste
- art / Photoshop / Illustrator work
- whether something feels fun or authentic

ChatGPT owns:
- architecture
- plumbing
- state handoffs
- save/load
- routing
- reusable module infrastructure
- implementation support
- keeping systems understandable and editable

Short version:

I own plumbing; you own rooms.
