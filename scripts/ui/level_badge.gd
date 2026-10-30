class_name LevelBadge
extends Control
## Pastille de niveau + fine barre d'XP, toujours visibles sous l'objectif en cours.

const ACCENT := Color(0.88, 0.64, 0.36, 1.0)
const OUTLINE := Color(0.08, 0.05, 0.03, 0.92)

var level: int = 1
var fraction: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var progression := InteractionManager.get_progression()
	if progression != null:
		progression.connect("xp_changed", _on_xp_changed)
		_on_xp_changed(int(progression.call("get_level")), 0, 0)
		set_state(int(progression.call("get_level")), float(progression.call("get_xp_fraction")))

func _on_xp_changed(new_level: int, _xp: int, _needed: int) -> void:
	var progression := InteractionManager.get_progression()
	var fill := float(progression.call("get_xp_fraction")) if progression != null else 0.0
	set_state(new_level, fill)

func set_state(new_level: int, new_fraction: float) -> void:
	level = new_level
	fraction = clampf(new_fraction, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var center := Vector2(18.0, size.y * 0.5)
	draw_circle(center, 18.0, OUTLINE)
	draw_circle(center, 15.5, Color(0.55, 0.36, 0.14))
	draw_arc(center, 15.5, 0.0, TAU, 32, ACCENT, 2.0, true)
	var text := str(level)
	draw_string_outline(font, center + Vector2(-12, 7), text, HORIZONTAL_ALIGNMENT_CENTER, 24.0, 20, 5, OUTLINE)
	draw_string(font, center + Vector2(-12, 7), text, HORIZONTAL_ALIGNMENT_CENTER, 24.0, 20, Color(1, 0.95, 0.85))
	var bar := Rect2(42.0, size.y * 0.5 - 6.0, size.x - 46.0, 12.0)
	draw_rect(bar.grow(2.5), OUTLINE)
	draw_rect(bar, Color(0.1, 0.07, 0.05, 0.7))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), Color(0.98, 0.78, 0.3))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, 3.0)), Color(1.0, 0.92, 0.6))
