class_name StoryCard
extends Control

## Reusable full-screen story component.
## Keep it simple: plain background, big type, one dominant external asset.

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

var _headline_scale := 1.0
var _foreground_height_ratio := 0.62

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

	_headline_scale = slide.headline_scale
	_foreground_height_ratio = slide.foreground_height_ratio

	character.texture = _load_foreground(slide.foreground_path)
	character_frame.visible = character.texture != null

	body.text = slide.body
	body.visible = not slide.body.strip_edges().is_empty()

	continue_hint.visible = slide.show_continue_hint
	_apply_responsive_layout()

func _load_foreground(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null

	var resource := load(path)
	if resource is Texture2D:
		return resource

	push_warning("Story foreground is not a Texture2D: %s" % path)
	return null

func _apply_responsive_layout() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return

	var short_side := minf(size.x, size.y)
	var side_margin := clampf(size.x * 0.075, 24.0, 72.0)
	var top_margin := clampf(size.y * 0.045, 26.0, 72.0)
	var bottom_margin := clampf(size.y * 0.055, 30.0, 84.0)

	safe_area.add_theme_constant_override("margin_left", roundi(side_margin))
	safe_area.add_theme_constant_override("margin_right", roundi(side_margin))
	safe_area.add_theme_constant_override("margin_top", roundi(top_margin))
	safe_area.add_theme_constant_override("margin_bottom", roundi(bottom_margin))
	content.add_theme_constant_override("separation", roundi(clampf(size.y * 0.014, 10.0, 22.0)))

	character_frame.custom_minimum_size = Vector2(
		0.0,
		clampf(size.y * _foreground_height_ratio, 180.0, size.y * 0.72)
	)

	headline.add_theme_font_size_override(
		"font_size",
		roundi(clampf(short_side * 0.15 * _headline_scale, 34.0, 112.0))
	)
	body.add_theme_font_size_override(
		"font_size",
		roundi(clampf(short_side * 0.052, 20.0, 38.0))
	)
	continue_hint.add_theme_font_size_override(
		"font_size",
		roundi(clampf(short_side * 0.03, 12.0, 20.0))
	)
