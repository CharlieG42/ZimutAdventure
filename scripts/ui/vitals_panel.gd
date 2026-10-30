class_name VitalsPanel
extends Control
## Trois jauges verticales toujours visibles sur le côté de l'écran : faim, soif, énergie.
## Chaque jauge a sa couleur, son icône dessinée et son nom, et clignote en rouge
## quand elle est presque vide, pour être identifiable d'un coup d'œil.

const GAUGE_WIDTH := 52.0
const GAUGE_HEIGHT := 150.0
const GAP := 10.0
const LOW_LEVEL := 0.2
const KINDS := ["hunger", "thirst", "energy"]
const LABELS := {"hunger": "VITAL_HUNGER", "thirst": "VITAL_THIRST", "energy": "VITAL_ENERGY"}
const COLORS := {
	"hunger": Color(0.96, 0.58, 0.18),
	"thirst": Color(0.28, 0.66, 1.0),
	"energy": Color(0.62, 0.86, 0.26),
}
const OUTLINE := Color(0.08, 0.05, 0.03, 0.92)
const BACK := Color(0.06, 0.04, 0.03, 0.62)
const ALERT := Color(1.0, 0.25, 0.2)

var values: Dictionary = {"hunger": 1.0, "thirst": 1.0, "energy": 1.0}
var _time: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = panel_size()

static func panel_size() -> Vector2:
	return Vector2(GAUGE_WIDTH * 3.0 + GAP * 2.0, GAUGE_HEIGHT + 62.0)

func set_value(kind: String, value: float) -> void:
	values[kind] = clampf(value, 0.0, 1.0)
	queue_redraw()

func get_value(kind: String) -> float:
	return float(values.get(kind, 0.0))

func is_low(kind: String) -> bool:
	return get_value(kind) <= LOW_LEVEL

func _process(delta: float) -> void:
	_time += delta
	for kind in KINDS:
		if is_low(kind):
			queue_redraw()
			return

func _draw() -> void:
	var font := ThemeDB.fallback_font
	for i in KINDS.size():
		var kind: String = KINDS[i]
		var x := float(i) * (GAUGE_WIDTH + GAP)
		var value := get_value(kind)
		var low := is_low(kind)
		var pulse := 0.5 + 0.5 * sin(_time * 7.0) if low else 0.0
		var color: Color = COLORS[kind].lerp(ALERT, pulse) if low else COLORS[kind]
		# Pastille d'icône.
		var icon_center := Vector2(x + GAUGE_WIDTH * 0.5, 22.0)
		draw_circle(icon_center, 22.0, OUTLINE)
		draw_circle(icon_center, 19.0, color.darkened(0.25))
		_draw_icon(kind, icon_center, Color(1, 1, 1, 0.97))
		# Jauge.
		var tube := Rect2(x + 8.0, 52.0, GAUGE_WIDTH - 16.0, GAUGE_HEIGHT - 6.0)
		draw_rect(tube.grow(3.0), OUTLINE)
		draw_rect(tube, BACK)
		var fill_h := tube.size.y * value
		if fill_h > 0.5:
			var fill := Rect2(tube.position.x, tube.end.y - fill_h, tube.size.x, fill_h)
			draw_rect(fill, color)
			draw_rect(Rect2(fill.position, Vector2(fill.size.x * 0.34, fill.size.y)), color.lightened(0.28))
			draw_rect(Rect2(fill.position, Vector2(fill.size.x, 3.0)), color.lightened(0.5))
		for tick in [0.25, 0.5, 0.75]:
			var ty: float = tube.end.y - tube.size.y * tick
			draw_line(Vector2(tube.position.x, ty), Vector2(tube.position.x + 8.0, ty), Color(1, 1, 1, 0.45), 2.0)
		# Nom + pourcentage.
		var text := tr(LABELS[kind])
		var center_x := x + GAUGE_WIDTH * 0.5
		draw_string_outline(font, Vector2(x - 6.0, tube.end.y + 24.0), text, HORIZONTAL_ALIGNMENT_CENTER, GAUGE_WIDTH + 12.0, 17, 5, OUTLINE)
		draw_string(font, Vector2(x - 6.0, tube.end.y + 24.0), text, HORIZONTAL_ALIGNMENT_CENTER, GAUGE_WIDTH + 12.0, 17, color.lightened(0.35))
		var percent := "%d%%" % int(round(value * 100.0))
		draw_string_outline(font, Vector2(center_x - 26.0, tube.position.y + 22.0), percent, HORIZONTAL_ALIGNMENT_CENTER, 52.0, 18, 5, OUTLINE)
		draw_string(font, Vector2(center_x - 26.0, tube.position.y + 22.0), percent, HORIZONTAL_ALIGNMENT_CENTER, 52.0, 18, Color(1, 1, 1, 0.97))

func _draw_icon(kind: String, c: Vector2, color: Color) -> void:
	match kind:
		"hunger":
			# Cuisse de viande : masse ronde + os.
			draw_circle(c + Vector2(-3, -3), 9.0, color)
			draw_line(c + Vector2(3, 3), c + Vector2(10, 10), color, 4.0)
			draw_circle(c + Vector2(11, 8), 2.6, color)
			draw_circle(c + Vector2(8, 11), 2.6, color)
		"thirst":
			# Goutte d'eau.
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -12), c + Vector2(8, 2), c + Vector2(-8, 2)]), color)
			draw_circle(c + Vector2(0, 4), 8.0, color)
		"energy":
			# Éclair.
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(3, -12), c + Vector2(-7, 2), c + Vector2(-1, 2),
				c + Vector2(-4, 12), c + Vector2(8, -3), c + Vector2(1, -3)]), color)
