# Boss window interaction

`BossWindow` is a reusable Godot component layered between the warehouse background and gameplay.

Flow:
1. Idle: window is empty.
2. Warning: Troy begins to creep into the window as a telegraph.
3. Watching: Troy is centered and actively watching.
4. Leaving: Troy exits and the window returns to normal.

The first notebook thought is safe and teaches the notebook. After that first thought is resolved, conveyor pressure starts and Troy begins his watch cycle. The second thought is intentionally triggered when Troy reaches the WATCHING state.

Sorting boxes is still safe while Troy watches. Attempting to actually write/save the idea while he is watching gets Darren caught; in the current vertical slice the idea is lost and a boss-catch counter increments. This leaves room for a later job-security/firing system without hard-coding it into this component.

Troy remains a normal external image asset. The scene uses a runtime shader to key the white background and render him as a clipped silhouette inside the existing warehouse window. No image data is embedded in code.
