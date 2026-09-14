# Story system

The opening story is intentionally built like a simple reusable UI component, not a scripted cutscene.

- `data/story/*.tres` = story content and asset choices
- `scenes/story/story_card.tscn` = reusable layout
- `scripts/story/story_card.gd` = responsive sizing only
- `scenes/story/story_sequence.tscn` + `story_sequence.gd` = progression/input

The first test contains one card: **THIS IS DARREN** on a plain background using the existing transparent Darren asset.

Do not put story-specific coordinates into the sequence script. Do not embed images in code. Add later story beats as additional `.tres` resources and reuse the same card.
