extends Control

const DARREN_TEXTURE = preload("res://assets/character/darren front.png")
const BOXES_EXTERIOR_TEXTURE = preload("res://assets/story/boxes_exterior_story.jpg")
const NOTEBOOK_TEXTURE = preload("res://assets/boxes/notebook_open.png")

@onready var content: Control = $Content
@onready var chapter_label: Label = $Content/ChapterLabel
@onready var hero_backdrop: Panel = $Content/HeroBackdrop
@onready var hero_image: TextureRect = $Content/HeroImage
@onready var story_card: Panel = $Content/StoryCard
@onready var title_label: Label = $Content/TitleLabel
@onready var body_label: Label = $Content/BodyLabel
@onready var continue_button: Button = $Content/ContinueButton

var page := 0
var transitioning := false

var pages := [
    {"chapter":"BEFORE ANY OF THIS", "title":"This is Darren.", "body":"", "image":"darren"},
    {"chapter":"BEFORE ANY OF THIS", "title":"Darren wasn't a comedian.", "body":"He wasn't really trying to become one, either.", "image":""},
    {"chapter":"BEFORE ANY OF THIS", "title":"His life was mostly routines.", "body":"Obligations. Places he was supposed to be.", "image":""},
    {"chapter":"BEFORE ANY OF THIS", "title":"But Darren noticed things.", "body":"Dumb things. Weird things. Little things that made him laugh when nobody else was paying attention.", "image":""},
    {"chapter":"BEFORE ANY OF THIS", "title":"Most of those thoughts disappeared.", "body":"Lately, a few had started sticking around.", "image":""},
    {"chapter":"MONDAY", "title":"This is BOXES.", "body":"This is where Darren works.", "image":"boxes"},
    {"chapter":"THE NOTEBOOK", "title":"Ideas have started showing up at work.", "body":"If Darren writes one down before it disappears, it becomes a premise.", "image":"notebook"},
    {"chapter":"THE BOSS", "title":"His boss, Troy, has started noticing.", "body":"", "image":""},
    {"chapter":"THE SHIFT", "title":"Keep the line moving.", "body":"Save the funny thoughts if you can.", "image":""},
    {"chapter":"MONDAY", "title":"Clock in.", "body":"", "image":""}
]

func _ready() -> void:
    continue_button.pressed.connect(_on_continue_pressed)
    _apply_page()
    _play_opening_reveal()

func _apply_page() -> void:
    var data: Dictionary = pages[page]
    chapter_label.text = data["chapter"]
    title_label.text = data["title"]
    body_label.text = data["body"]
    continue_button.text = "CLOCK IN" if page == pages.size() - 1 else "CONTINUE"

    var image_key: String = data["image"]
    hero_image.visible = not image_key.is_empty()
    hero_backdrop.visible = page == 0
    story_card.visible = page == 0

    if image_key == "darren":
        hero_image.texture = DARREN_TEXTURE
    elif image_key == "boxes":
        hero_image.texture = BOXES_EXTERIOR_TEXTURE
    elif image_key == "notebook":
        hero_image.texture = NOTEBOOK_TEXTURE

    if page == 0:
        hero_image.position = Vector2(70, 96)
        hero_image.size = Vector2(290, 334)
        title_label.position = Vector2(46, 480)
        title_label.size = Vector2(338, 56)
        body_label.position = Vector2(46, 538)
        body_label.size = Vector2(338, 62)
    elif hero_image.visible:
        hero_image.position = Vector2(72, 92)
        hero_image.size = Vector2(286, 330)
        title_label.position = Vector2(34, 454)
        title_label.size = Vector2(362, 76)
        body_label.position = Vector2(34, 536)
        body_label.size = Vector2(362, 106)
    else:
        title_label.position = Vector2(34, 248)
        title_label.size = Vector2(362, 126)
        body_label.position = Vector2(34, 392)
        body_label.size = Vector2(362, 160)

func _play_opening_reveal() -> void:
    hero_image.modulate.a = 0.0
    hero_image.scale = Vector2(0.96, 0.96)
    story_card.modulate.a = 0.0
    title_label.modulate.a = 0.0
    continue_button.modulate.a = 0.0

    var tween := create_tween()
    tween.set_parallel(true)
    tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_property(hero_image, "modulate:a", 1.0, 0.34)
    tween.tween_property(hero_image, "scale", Vector2.ONE, 0.34)
    tween.tween_property(story_card, "modulate:a", 1.0, 0.28).set_delay(0.12)
    tween.tween_property(title_label, "modulate:a", 1.0, 0.28).set_delay(0.16)
    tween.tween_property(continue_button, "modulate:a", 1.0, 0.22).set_delay(0.30)

func _show_next_page() -> void:
    transitioning = true
    continue_button.disabled = true

    var out_tween := create_tween()
    out_tween.set_parallel(true)
    out_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    out_tween.tween_property(content, "modulate:a", 0.0, 0.12)
    out_tween.tween_property(content, "position:x", -12.0, 0.12)
    await out_tween.finished

    _apply_page()
    content.position.x = 12.0

    var in_tween := create_tween()
    in_tween.set_parallel(true)
    in_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    in_tween.tween_property(content, "modulate:a", 1.0, 0.20)
    in_tween.tween_property(content, "position:x", 0.0, 0.20)
    await in_tween.finished

    continue_button.disabled = false
    transitioning = false

func _on_continue_pressed() -> void:
    if transitioning:
        return
    if page < pages.size() - 1:
        page += 1
        await _show_next_page()
    else:
        get_tree().change_scene_to_file("res://scenes/boxes/boxes_module.tscn")
