# DRIVE v0.10 — road-only reset

This branch strips the active driving view back to the minimum needed to judge flow.

Visible during play:
- player car
- road surface / shoulders
- lane markings
- connector widening/narrowing
- steering controls
- road-only minimap / route cue
- final parking-space outline

Removed from the active view:
- houses
- lawns / neighborhood scenery
- city blocks
- venue facade
- roadside props
- decorative transition scenery

Mechanics are inherited from v0.9 so this build isolates whether the road flow itself
works before any art direction is added back.
