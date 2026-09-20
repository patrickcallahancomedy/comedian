extends Control

## Passive distractions; never a second phone/dialogue minigame.
## Leave the minimap and buttons usable. State changes what driving feels like.
@export var phone_enabled := true
@onready var city = $"../CityMap"
var closure := 0.0
var phone_visible := false
var elapsed := 0.0
var fatigue := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fatigue = clampf(float(50 - GameState.energy) / 50.0, 0.0, 1.0)

func _process(delta: float) -> void:
	if not city.section_started or city.drive_complete:
		closure = 0.0
		phone_visible = false
		queue_redraw()
		return
	elapsed += delta
	# One passive notification, dismissed automatically. No click required.
	phone_visible = phone_enabled and elapsed >= 12.0 and elapsed < 14.2
	closure = 0.0
	if fatigue > 0.0:
		var phase := fmod(elapsed, lerpf(7.0, 4.8, fatigue))
		var blink_duration := lerpf(0.35, 0.85, fatigue)
		if phase < blink_duration and elapsed > 2.0:
			closure = sin(phase / blink_duration * PI) * fatigue
	queue_redraw()

func _draw() -> void:
	if phone_visible:
		var panel := Rect2(25, 172, size.x - 50, 100)
		draw_style_box(_phone_style(), panel)
		draw_string(ThemeDB.fallback_font, Vector2(42, 199), "NATE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.65, 0.72, 0.76))
		draw_string(ThemeDB.fallback_font, Vector2(42, 228), "You on your way?", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color.WHITE)
		draw_string(ThemeDB.fallback_font, Vector2(42, 252), "Keep driving", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.72, 0.76))
	if closure > 0.0:
		# The close road view shuts; the GPS and touch controls remain visible.
		var height := 240.0 * closure
		draw_rect(Rect2(0, 154, size.x, height), Color(0.03, 0.035, 0.04))
		draw_rect(Rect2(0, 674 - height, size.x, height), Color(0.03, 0.035, 0.04))

func _phone_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.085, 0.10, 0.96)
	style.set_corner_radius_all(12)
	return style
