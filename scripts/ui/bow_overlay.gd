extends Control
## Affichage de l'arc par-dessus le jeu : jauge de tension autour du viseur, cadre sur
## la cible verrouillée (nom et distance), nombre de flèches, et marque de coup au but.

const COLOR_IDLE := Color(1.0, 1.0, 1.0, 0.85)
const COLOR_DRAW := Color(0.98, 0.74, 0.32, 1.0)
const COLOR_FULL := Color(0.55, 0.92, 0.45, 1.0)
const COLOR_SHADOW := Color(0.0, 0.0, 0.0, 0.55)
const HIT_TIME := 0.4
const LOW_ARROWS := 3

var _state: Dictionary = {}
var _hit_left: float = 0.0
var _pulse: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func update_state(state: Dictionary) -> void:
	_state = state
	if bool(state.get("equipped", false)) or _hit_left > 0.0:
		queue_redraw()
	elif visible and not _state.is_empty():
		queue_redraw()

## Coup au but : une croix brève autour du viseur.
func flash_hit() -> void:
	_hit_left = HIT_TIME
	queue_redraw()

func _process(delta: float) -> void:
	_pulse += delta
	if _hit_left > 0.0:
		_hit_left = maxf(0.0, _hit_left - delta)
		queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	if _hit_left > 0.0:
		_draw_hit(center)
	if not bool(_state.get("equipped", false)):
		return
	var drawing := bool(_state.get("drawing", false))
	var charge := float(_state.get("charge", 0.0))
	var target := _state.get("target") as Node3D
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		_draw_target(target, drawing, charge)
	if drawing:
		_draw_charge(center, charge)
	_draw_arrow_count(center, int(_state.get("arrows", 0)))

func _draw_charge(center: Vector2, charge: float) -> void:
	var radius := 30.0
	draw_arc(center, radius, 0.0, TAU, 48, COLOR_SHADOW, 6.0, true)
	var color := COLOR_DRAW.lerp(COLOR_FULL, clampf((charge - 0.75) * 4.0, 0.0, 1.0))
	if charge >= 1.0:
		radius += sin(_pulse * 14.0) * 1.5
	draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * maxf(charge, 0.02), 48, color, 4.0, true)

func _draw_target(target: Node3D, drawing: bool, charge: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var point: Vector3 = target.call("get_aim_point") if target.has_method("get_aim_point") else target.global_position
	if camera.is_position_behind(point):
		return
	var screen := camera.unproject_position(point) - global_position
	var distance := camera.global_position.distance_to(point)
	var half := clampf(520.0 / maxf(distance, 1.0), 20.0, 64.0)
	var color := COLOR_IDLE
	if drawing:
		color = COLOR_DRAW.lerp(COLOR_FULL, clampf((charge - 0.75) * 4.0, 0.0, 1.0))
	var arm := half * 0.45
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var tip: Vector2 = screen + corner * half
		for pass_index in 2:
			var c := COLOR_SHADOW if pass_index == 0 else color
			var w := 5.0 if pass_index == 0 else 2.5
			draw_line(tip, tip - Vector2(corner.x * arm, 0.0), c, w, true)
			draw_line(tip, tip - Vector2(0.0, corner.y * arm), c, w, true)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var meters := player.global_position.distance_to(target.global_position) if player != null else distance
	var label := "%d m" % int(roundf(meters))
	if target.has_method("get_display_name"):
		label = "%s · %s" % [String(target.call("get_display_name")), label]
	_draw_text(screen + Vector2(0.0, -half - 10.0), label, color)

## Le nombre de flèches figure déjà sur la barre d'outils : on n'alerte ici que
## lorsqu'il n'en reste presque plus.
func _draw_arrow_count(center: Vector2, arrows: int) -> void:
	if arrows > LOW_ARROWS:
		return
	var color := COLOR_DRAW if arrows > 0 else Color(1.0, 0.45, 0.35, 1.0)
	_draw_text(center + Vector2(0.0, -44.0), tr("HUD_ARROWS") % arrows, color)

func _draw_hit(center: Vector2) -> void:
	var alpha := _hit_left / HIT_TIME
	var grow := 10.0 + (1.0 - alpha) * 8.0
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var dir: Vector2 = corner.normalized()
		draw_line(center + dir * grow, center + dir * (grow + 12.0), Color(0, 0, 0, 0.5 * alpha), 6.0, true)
		draw_line(center + dir * grow, center + dir * (grow + 12.0), Color(1.0, 0.9, 0.5, alpha), 3.0, true)

func _draw_text(at: Vector2, text: String, color: Color) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := 20
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var origin := at - Vector2(text_size.x * 0.5, 0.0)
	draw_string(font, origin + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_SHADOW)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
