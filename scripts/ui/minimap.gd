class_name MiniMap
extends Control
## Mini-carte toujours visible : relief ombré centré sur le joueur, Nord en haut,
## flèche du joueur orientée selon son cap, repères de ressources/animaux/feu/camp.
## Un appui sur la mini-carte ouvre la carte plein écran (signal `pressed`).

signal pressed

const SIZE_PX := 170.0
## Rayon du monde affiché (mètres) : les repères proches restent lisibles.
const VIEW_RADIUS := 55.0
const REFRESH_PERIOD := 0.12
const FRAME := Color(0.88, 0.64, 0.36, 1.0)
const OUTLINE := Color(0.08, 0.05, 0.03, 0.9)
const GROUPS := ["breakable", "wood", "stone", "animals", "campfire", "structures"]

var _landscape: Node3D
var _player: Node3D
var _texture: ImageTexture
var _elapsed: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(SIZE_PX, SIZE_PX)
	size = Vector2(SIZE_PX, SIZE_PX)

func _gui_input(event: InputEvent) -> void:
	var is_press: bool = false
	if event is InputEventMouseButton:
		is_press = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		is_press = event.pressed
	if is_press:
		accept_event()
		pressed.emit()

func set_context(landscape: Node3D, player: Node3D) -> void:
	_landscape = landscape
	_player = player
	_texture = null
	queue_redraw()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= REFRESH_PERIOD:
		_elapsed = 0.0
		queue_redraw()

func _terrain_size() -> float:
	if _landscape != null and _landscape.get("terrain_size") != null:
		return maxf(1.0, float(_landscape.get("terrain_size")))
	return 400.0

## Conversion monde (x, z) -> pixel dans le widget, joueur au centre.
func world_to_local(world_x: float, world_z: float) -> Vector2:
	var center := Vector2(SIZE_PX, SIZE_PX) * 0.5
	var px_per_m := SIZE_PX * 0.5 / VIEW_RADIUS
	var origin := Vector2.ZERO
	if _player != null and is_instance_valid(_player):
		origin = Vector2(_player.global_position.x, _player.global_position.z)
	return center + (Vector2(world_x, world_z) - origin) * px_per_m

func _ensure_texture() -> void:
	if _texture != null or _landscape == null:
		return
	_texture = MapPanel.build_terrain_texture(_landscape, 128)

func _draw() -> void:
	var center := Vector2(SIZE_PX, SIZE_PX) * 0.5
	var radius := SIZE_PX * 0.5
	draw_circle(center, radius + 4.0, OUTLINE)
	_ensure_texture()
	if _texture != null and _player != null and is_instance_valid(_player):
		_draw_terrain(center, radius)
	else:
		draw_circle(center, radius, Color(0.62, 0.42, 0.26))
	_draw_markers(center, radius)
	_draw_player(center)
	draw_arc(center, radius, 0.0, TAU, 64, FRAME, 4.0, true)
	draw_arc(center, radius + 3.0, 0.0, TAU, 64, OUTLINE, 2.0, true)
	var font := ThemeDB.fallback_font
	var north := center + Vector2(0.0, -radius + 24.0)
	draw_string_outline(font, north + Vector2(-10, 0), "N", HORIZONTAL_ALIGNMENT_CENTER, 20.0, 20, 6, OUTLINE)
	draw_string(font, north + Vector2(-10, 0), "N", HORIZONTAL_ALIGNMENT_CENTER, 20.0, 20, Color(0.95, 0.55, 0.35))

## Découpe la texture du terrain autour du joueur, en bandes pour rester dans le disque.
func _draw_terrain(center: Vector2, radius: float) -> void:
	var terrain := _terrain_size()
	var tex_size := Vector2(_texture.get_size())
	var px_per_m := tex_size.x / terrain
	var origin := Vector2(_player.global_position.x, _player.global_position.z)
	var strips := 48
	for i in strips:
		var y0 := -radius + 2.0 * radius * float(i) / float(strips)
		var y1 := -radius + 2.0 * radius * float(i + 1) / float(strips)
		var ym := (y0 + y1) * 0.5
		var half := sqrt(maxf(radius * radius - ym * ym, 0.0))
		if half < 1.0:
			continue
		var dst := Rect2(center + Vector2(-half, y0), Vector2(half * 2.0, y1 - y0))
		var meters_per_px := VIEW_RADIUS / radius
		var world_a := origin + Vector2(-half, y0) * meters_per_px
		var world_b := origin + Vector2(half, y1) * meters_per_px
		var src_a := (world_a / terrain + Vector2(0.5, 0.5)) * tex_size
		var src_b := (world_b / terrain + Vector2(0.5, 0.5)) * tex_size
		draw_texture_rect_region(_texture, dst, Rect2(src_a, src_b - src_a))

func _draw_markers(center: Vector2, radius: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for group in GROUPS:
		for node in tree.get_nodes_in_group(group):
			if not (node is Node3D) or not is_instance_valid(node):
				continue
			var pos := world_to_local((node as Node3D).global_position.x, (node as Node3D).global_position.z)
			if pos.distance_to(center) > radius - 7.0:
				continue
			_draw_marker(group, pos)

func _draw_marker(kind: String, pos: Vector2) -> void:
	match kind:
		"stone":
			draw_circle(pos, 4.5, OUTLINE)
			draw_circle(pos, 3.0, Color(0.82, 0.86, 0.95))
		"wood":
			draw_rect(Rect2(pos - Vector2(4.5, 4.5), Vector2(9, 9)), OUTLINE)
			draw_rect(Rect2(pos - Vector2(3, 3), Vector2(6, 6)), Color(0.62, 0.38, 0.16))
		"breakable":
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -6), pos + Vector2(6, 0), pos + Vector2(0, 6), pos + Vector2(-6, 0)]), OUTLINE)
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -4), pos + Vector2(4, 0), pos + Vector2(0, 4), pos + Vector2(-4, 0)]), Color(0.55, 0.52, 0.5))
		"animals":
			draw_circle(pos, 4.0, OUTLINE)
			draw_circle(pos, 2.6, Color(1.0, 0.95, 0.7))
		"campfire":
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -8), pos + Vector2(6, 5), pos + Vector2(-6, 5)]), OUTLINE)
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -5), pos + Vector2(3.5, 3.5), pos + Vector2(-3.5, 3.5)]), Color(1.0, 0.55, 0.15))
		"structures":
			draw_colored_polygon(PackedVector2Array([pos + Vector2(-7, -1), pos + Vector2(0, -8), pos + Vector2(7, -1), pos + Vector2(7, 6), pos + Vector2(-7, 6)]), OUTLINE)
			draw_colored_polygon(PackedVector2Array([pos + Vector2(-4.5, 0), pos + Vector2(0, -4.5), pos + Vector2(4.5, 0), pos + Vector2(4.5, 4), pos + Vector2(-4.5, 4)]), Color(0.55, 0.85, 0.5))

func _draw_player(center: Vector2) -> void:
	var heading := 0.0
	if _player != null and is_instance_valid(_player) and _player.has_method("get_heading_degrees"):
		heading = deg_to_rad(float(_player.call("get_heading_degrees")))
	var dir := Vector2(sin(heading), -cos(heading))
	var side := Vector2(-dir.y, dir.x)
	var arrow := PackedVector2Array([center + dir * 13.0, center - dir * 8.0 + side * 8.0, center - dir * 3.0, center - dir * 8.0 - side * 8.0])
	var halo := PackedVector2Array()
	for point in arrow:
		halo.append(center + (point - center) * 1.4)
	draw_colored_polygon(halo, Color(1, 1, 1, 0.95))
	draw_colored_polygon(arrow, Color(0.25, 0.6, 1.0))
