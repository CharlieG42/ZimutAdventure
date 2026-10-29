extends Control
## Viseur central : un point discret qui s'élargit en anneau quand un objet
## interactif est visé.

@export var idle_color: Color = Color(1, 1, 1, 0.75)
@export var focus_color: Color = Color(0.95, 0.72, 0.4, 1.0)

var _focused: bool = false
var _amount: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func set_focused(value: bool) -> void:
	if value == _focused:
		return
	_focused = value
	set_process(true)

func _process(delta: float) -> void:
	var target := 1.0 if _focused else 0.0
	_amount = move_toward(_amount, target, delta * 8.0)
	queue_redraw()
	if is_equal_approx(_amount, target):
		set_process(false)

func _draw() -> void:
	var center := size * 0.5
	var color := idle_color.lerp(focus_color, _amount)
	# Contour sombre : lisible sur ciel clair comme sur sol sombre.
	draw_circle(center, 4.5 + 1.5 * _amount, Color(0, 0, 0, 0.45))
	draw_circle(center, 3.0 + 1.0 * _amount, color)
	if _amount > 0.01:
		draw_arc(center, 14.0 + 4.0 * _amount, 0.0, TAU, 40, Color(focus_color, _amount), 2.5, true)
