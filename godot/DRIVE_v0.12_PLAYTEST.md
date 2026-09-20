# DRIVE v0.12 — single world road network

This is the architecture correction after v0.11.

The playable drive no longer loads or hands off between neighborhood/highway/city
road stages. The scene uses one world-space road network and one controller.

Physical route:
- neighborhood street graph
- the neighborhood exit node is the same coordinate as the widening connector
- that connector is physically attached to the four-lane highway
- the fourth highway lane physically peels away at the fork
- the exit branch is the same world geometry as the connector into the city
- the connector ends at the exact city entry node
- the city is another connected turn graph
- the final city road widens on its right edge to create a parking lane
- parking spots live on that same continuing street

Camera zoom and control rules follow the road under the car. They are metadata /
behavior changes, not scene or stage transitions.

v0.11 files remain in source as reference; the scene now uses connected_drive.gd
and drive_road_network.gd.
