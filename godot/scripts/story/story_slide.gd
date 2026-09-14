class_name StorySlide
extends Resource

## Story content only. Layout belongs in StoryCard.

@export_group("Copy")
@export_multiline var headline: String = ""
@export_multiline var body: String = ""

@export_group("Visuals")
@export var background_color: Color = Color("96837C")
@export var background_texture: Texture2D
@export_range(0.0, 0.8, 0.05) var background_dim: float = 0.0
@export var character_texture: Texture2D

@export_group("Presentation")
@export var show_continue_hint: bool = true
