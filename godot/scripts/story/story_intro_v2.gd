extends Control

const DARREN_TEXTURE = preload("res://assets/character/darren front.png")
const NOTEBOOK_TEXTURE = preload("res://assets/boxes/notebook_open.png")

@onready var content: Control = $Content
@onready var chapter_label: Label = $Content/ChapterLabel
@onready var hero_image: TextureRect = $Content/HeroImage
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
    {"chapter":"MONDAY", "title":"This is BOXES.", "body":"This is where Darren works.", "image":""},
    {"chapter":"THE NOTEBOOK", "title":"Ideas have started showing up at work.", "body":"If Darren writes one down before it disappears, it becomes a premise.", "image":"notebook"},
    {"chapter":"THE BOSS", "title":"His boss, Troy, has started noticing.", "body":"", "image":""},
    {"chapter":"THE SHIFT", "title":"Keep the line moving.", "body":"Save the funny thoughts if you can.", "image":""},
    {"chapter":"MONDAY", "title":"Clock in.", "body":"", "image":""}
]

func _ready() -> void:
    continue_button.pressed.connect(_on_continue_pressed)
    _apply_page()

func _apply_page() -> void:
    var data: Dictionary = pages[page]
    chapter_label.text = data["chapter"]
    title_label.text = data["title"]
    body_label.text = data["body"]
    continue_button.text = "CLOCK IN" if page == pages.size() - 1 else "CONTINUE"

    var image_key: String = data["image"]
    hero_image.visible = not image_key.is_empty()
    if image_key == "darren":
        hero_image.texture = DARREN_TEXTURE
    elif image_key == "notebook":
        hero_image.texture = NOTEBOOK_TEXTURE

    if hero_image.visible:
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
