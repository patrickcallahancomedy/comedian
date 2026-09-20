# DRIVE v0.11 — connected roads

Road-only geometry pass based on the mobile markup.

Route:
1. Smaller neighborhood turn grid
2. Literal widening road connector
3. Four-lane highway
4. Physical right-lane fork into a literal connector
5. City turn grid
6. Road widens to add a second curb/parking lane
7. Two-lane final street; park from the right lane

Important architecture change:
Connector behavior is driven by distance traveled through actual road chunks.
There is no timer-based transition screen. Width, car scale, lane count, and road
center position change over the connector distance.

The highway exit still has a logical crossing point for rules/testing, but the
visible geometry now physically splits: three lanes continue and the right lane
peels into the connector. Missing it keeps the player on the highway until the
next physical fork.

Environment art remains intentionally absent.
