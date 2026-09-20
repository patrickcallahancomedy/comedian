# DRIVE v0.9 — continuous-road playtest

Built from the tested v0.8 branch.

## Player-facing flow

Neighborhood road -> invisible gate -> connector animation -> eight-lane highway ->
right-most-lane gate -> connector animation -> close city/venue approach -> one
parking space directly in front of the venue.

The three gameplay profiles still exist internally for readable code and tuning,
but there is no hard visual state cut between them.

## Changes

- Neighborhood speed reduced to 62% of base speed.
- Neighborhood-to-highway connector widens the road and shrinks the car.
- Highway expanded to 8 lanes and nearly fills the phone width.
- Highway exit is now the right-most lane itself; no triangle/ramp graphic.
- Missing the exit keeps the player on the highway for another gate opportunity.
- Highway-to-city connector grows the car and fades lane markings away.
- Final city section is a single broad automatic approach, not another grid.
- Venue facade and one curbside parking target appear at the end of the road.
- Mobile steering labels use < and > to avoid missing-glyph boxes on iOS.
- Existing car PNG remains an external editable asset; no embedded/generated art.

## Deliberately not final

The environment shapes are still procedural placeholders. v0.9 is meant to prove
the scale/transition language before final neighborhood, highway, city, and venue art.
