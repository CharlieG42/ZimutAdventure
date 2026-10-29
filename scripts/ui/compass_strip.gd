class_name CompassStrip
extends Control
## Ruban de boussole : les points cardinaux défilent quand le joueur tourne.
## Le Nord est l'axe -Z du monde ; le cap augmente dans le sens horaire.
## Cœur de la mécanique d'orientation du GDD (« Zimut » = azimut).

const CARDINAL_KEYS: Array[String] = [
	"HUD_DIR_N", "HUD_DIR_NE", "HUD_DIR_E", "HUD_DIR_SE",
	"HUD_DIR_S", "HUD_DIR_SW", "HUD_DIR_W", "HUD_DIR_NW",
]

## Largeur angulaire visible (en degrés) dans le ruban.
@export var visible_span_deg: float = 140.0
@export var text_color: Color = Color(0.97, 0.94, 0.88, 1.0)
@export var north_color: Color = Color(0.95, 0.55, 0.35, 1.0)
@export var accent_color: Color = Color(0.88, 0.64, 0.36, 1.0)
@export var background_color: Color = Color(0.09, 0.06, 0.035, 0.5)

var heading: float = 0.0:
	set(value):
		var wrapped := fposmod(value, 360.0)
		if absf(wrapped - heading) < 0.05:
			return
		heading = wrapped
		queue_redraw()

var _names: Array[String] = []
var _background: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background = StyleBoxFlat.new()
	_background.bg_color = background_color
	_background.set_corner_radius_all(14)
	_background.border_color = Color(accent_color, 0.35)
	_background.set_border_width_all(2)
	_background.anti_aliasing = true
	_refresh_names()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_names()
		queue_redraw()

## Nom court (localisé) du point cardinal le plus proche d'un cap.
static func cardinal_key(heading_deg: float) -> String:
	var index := int(roundf(fposmod(heading_deg, 360.0) / 45.0)) % 8
	return CARDINAL_KEYS[index]

func _refresh_names() -> void:
	_names.clear()
	for key in CARDINAL_KEYS:
		_names.append(tr(key))

func _draw() -> void:
	if _background == null:
		return
	draw_style_box(_background, Rect2(Vector2.ZERO, size))
	var font := get_theme_default_font()
	var pixels_per_degree := size.x / visible_span_deg
	var half_span := visible_span_deg * 0.5
	var first := int(floorf((heading - half_span) / 5.0)) * 5
	var last := int(ceilf((heading + half_span) / 5.0)) * 5
	var mid_x := size.x * 0.5
	var baseline := size.y * 0.5 + 8.0

	for angle in range(first, last + 1, 5):
		var x := (float(angle) - heading) * pixels_per_degree + mid_x
		if x < 10.0 or x > size.x - 10.0:
			continue
		var distance := absf(x - mid_x) / (size.x * 0.5)
		var fade := 1.0 - smoothstep(0.65, 1.0, distance)
		var wrapped := posmod(angle, 360)
		if wrapped % 45 == 0:
			var index := wrapped / 45
			var is_main := index % 2 == 0
			var label := _names[index] if index < _names.size() else ""
			var font_size := 26 if is_main else 18
			var color := (north_color if index == 0 else text_color)
			color.a = fade
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var pos := Vector2(x - width * 0.5, baseline)
			draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(0.1, 0.06, 0.03, 0.9 * fade))
			draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		elif wrapped % 15 == 0:
			var tick_color := Color(text_color, 0.7 * fade)
			draw_line(Vector2(x, size.y - 16.0), Vector2(x, size.y - 8.0), tick_color, 2.0)
		else:
			var tick_color := Color(text_color, 0.35 * fade)
			draw_line(Vector2(x, size.y - 13.0), Vector2(x, size.y - 8.0), tick_color, 1.5)

	# Repère central (cap actuel).
	draw_colored_polygon(PackedVector2Array([
		Vector2(mid_x - 8.0, 2.0), Vector2(mid_x + 8.0, 2.0), Vector2(mid_x, 13.0),
	]), accent_color)
