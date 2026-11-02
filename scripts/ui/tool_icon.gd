class_name ToolIcon
extends Control
## Icône dessinée en code d'un outil (hache, serpette, arc), sans fichier image.

var tool_id: String = ""

const WOOD := Color(0.62, 0.4, 0.2)
const METAL := Color(0.85, 0.88, 0.92)
const DARK := Color(0.1, 0.06, 0.04, 0.9)

func _draw() -> void:
	var c := size * 0.5
	var u := minf(size.x, size.y) / 76.0
	match tool_id:
		"tool_stone_axe":
			_line(c + Vector2(-16, 20) * u, c + Vector2(14, -18) * u, WOOD, 6.0 * u)
			var head := PackedVector2Array([c + Vector2(4, -26) * u, c + Vector2(24, -8) * u, c + Vector2(14, -2) * u, c + Vector2(-2, -14) * u])
			draw_colored_polygon(_grow(head, c, 1.15), DARK)
			draw_colored_polygon(head, METAL)
		"tool_sickle":
			_line(c + Vector2(-18, 22) * u, c + Vector2(-4, 4) * u, WOOD, 6.0 * u)
			draw_arc(c + Vector2(4, -4) * u, 20.0 * u, deg_to_rad(110.0), deg_to_rad(330.0), 20, DARK, 9.0 * u, true)
			draw_arc(c + Vector2(4, -4) * u, 20.0 * u, deg_to_rad(110.0), deg_to_rad(330.0), 20, METAL, 5.0 * u, true)
		"tool_hoe":
			_line(c + Vector2(-14, 24) * u, c + Vector2(12, -20) * u, WOOD, 6.0 * u)
			var blade := PackedVector2Array([c + Vector2(4, -22) * u, c + Vector2(26, -10) * u, c + Vector2(22, -2) * u, c + Vector2(8, -10) * u])
			draw_colored_polygon(_grow(blade, c, 1.15), DARK)
			draw_colored_polygon(blade, METAL)
		"tool_watering_can":
			var water := Color(0.45, 0.7, 0.95)
			draw_colored_polygon(_grow(PackedVector2Array([c + Vector2(-16, -6) * u, c + Vector2(10, -6) * u, c + Vector2(8, 20) * u, c + Vector2(-14, 20) * u]), c, 1.1), DARK)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-16, -6) * u, c + Vector2(10, -6) * u, c + Vector2(8, 20) * u, c + Vector2(-14, 20) * u]), METAL)
			_line(c + Vector2(10, 2) * u, c + Vector2(26, -14) * u, METAL, 5.0 * u)
			draw_arc(c + Vector2(-16, 6) * u, 10.0 * u, deg_to_rad(90.0), deg_to_rad(270.0), 12, DARK, 5.0 * u, true)
			draw_circle(c + Vector2(28, -6) * u, 2.5 * u, water)
			draw_circle(c + Vector2(24, 2) * u, 2.5 * u, water)
		"tool_fishing_rod":
			_line(c + Vector2(-20, 22) * u, c + Vector2(20, -22) * u, WOOD, 5.0 * u)
			draw_line(c + Vector2(20, -22) * u, c + Vector2(24, 8) * u, Color(1, 1, 1, 0.85), 1.5 * u)
			draw_circle(c + Vector2(24, 12) * u, 3.0 * u, Color(0.9, 0.2, 0.15))
		"tool_hunting_bow":
			draw_arc(c + Vector2(-8, 0) * u, 26.0 * u, deg_to_rad(-62.0), deg_to_rad(62.0), 20, DARK, 8.0 * u, true)
			draw_arc(c + Vector2(-8, 0) * u, 26.0 * u, deg_to_rad(-62.0), deg_to_rad(62.0), 20, WOOD, 5.0 * u, true)
			var top := c + Vector2(-8 + 26.0 * cos(deg_to_rad(62.0)), -26.0 * sin(deg_to_rad(62.0))) * u
			var bottom := c + Vector2(-8 + 26.0 * cos(deg_to_rad(62.0)), 26.0 * sin(deg_to_rad(62.0))) * u
			draw_line(top, bottom, Color(1, 1, 1, 0.8), 1.5 * u)
			_line(c + Vector2(-14, 0) * u, c + Vector2(24, 0) * u, Color(0.8, 0.7, 0.5), 3.0 * u)
			draw_colored_polygon(PackedVector2Array([c + Vector2(30, 0) * u, c + Vector2(21, -5) * u, c + Vector2(21, 5) * u]), METAL)

func _line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	draw_line(a, b, DARK, width + 3.0)
	draw_line(a, b, color, width)

func _grow(points: PackedVector2Array, center: Vector2, factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(center + (point - center) * factor)
	return out
