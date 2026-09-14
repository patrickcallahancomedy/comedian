class_name StoryCard
extends Control

## Reusable full-screen story component.
## Keep this scene boring on purpose: background, big type, big asset, optional body.

@onready var background_color: ColorRect = $BackgroundColor
@onready var background_image: TextureRect = $BackgroundImage
@onready var background_dim: ColorRect = $BackgroundDim
@onready var safe_area: MarginContainer = $SafeArea
@onready var content: VBoxContainer = $SafeArea/Content
@onready var headline: Label = $SafeArea/Content/Headline
@onready var character_frame: Control = $SafeArea/Content/CharacterFrame
@onready var character: TextureRect = $SafeArea/Content/CharacterFrame/Character
@onready var body: Label = $SafeArea/Content/Body
@onready var continue_hint: Label = $ContinueHint

func _ready() -> void:
	resized.connect(_apply_responsive_layout)
	_apply_responsive_layout()

func present(slide: StorySlide) -> void:
	background_color.color = slide.background_color
	background_image.texture = slide.background_texture
	background_image.visible = slide.background_texture != null
	background_dim.color = Color(0.0, 0.0, 0.0, slide.background_dim)
	background_dim.visible = slide.background_dim > 0.0

	headline.text = slide.headline
	headline.visible = not slide.headline.strip_edges().is_empty()
	character.texture = slide.character_texture
	character_frame.visible = slide.character_texture != null
	body.text = slide.body
	body.visible = not slide.body.strip_edges().is_empty()
	continue_hint.visible = slide.show_continue_hint
	_apply_responsive_layout()

func _apply_responsive_layout() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return

	var short_side := minf(size.x, size.y)
	var side_margin := clampf(size.x * 0.075, 24.0, 72.0)
	var top_margin := clampf(size.y * 0.055, 30.0, 84.0)
	var bottom_margin := clampf(size.y * 0.055, 30.0, 84.0)

	safe_area.add_theme_constant_override("margin_left", roundi(side_margin))
	safe_area.add_theme_constant_override("margin_right", roundi(side_margin))
	safe_area.add_theme_constant_override("margin_top", roundi(top_margin))
	safe_area.add_theme_constant_override("margin_bottom", roundi(bottom_margin))
	content.add_theme_constant_override("separation", roundi(clampf(size.y * 0.014, 10.0, 22.0)))

	headline.add_theme_font_size_override("font_size", roundi(clampf(short_side * 0.15, 54.0, 112.0)))
	body.add_theme_font_size_override("font_size", roundi(clampf(short_side * 0.052, 20.0, 38.0)))
	continue_hint.add_theme_font_size_override("font_size", roundi(clampf(short_side * 0.03, 12.0, 20.0)))
