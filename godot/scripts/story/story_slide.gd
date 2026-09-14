class_name StorySlide
extends Resource

## Story content only. Layout belongs in StoryCard.
## Visuals stay as normal external files under res://assets/.

@export_group("Copy")
@export_multiline var headline: String = ""
@export_multiline var body: String = ""

@export_group("Visuals")
@export var background_color: Color = Color("96837C")
@export var background_texture: Texture2D
@export_range(0.0, 0.8, 0.05) var background_dim: float = 0.0
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp") var foreground_path: String = ""
@export_range(0.25, 0.72, 0.01) var foreground_height_ratio: float = 0.62

@export_group("Presentation")
@export_range(0.45, 1.2, 0.01) var headline_scale: float = 1.0
@export var show_continue_hint: bool = true
