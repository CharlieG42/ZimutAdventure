class_name MapPanel
extends Control
## Carte du canyon : relief ombré (altitude + éclairage rasant), ressources (pierre,
## bois, rochers cassables), animaux et position + cap du joueur.
## Le Nord est en haut (axe -Z du monde), comme la boussole du HUD.

const RESOLUTION := 160
const REFRESH_PERIOD := 0.2
const COLORS := {
	"backdrop": Color(0.05, 0.03, 0.02, 0.72),
	"frame": Color(0.88, 0.64, 0.36, 1.0),
	"low": Color(0.55, 0.36, 0.22),
	"mid": Color(0.78, 0.6, 0.4),
	"high": Color(0.93, 0.8, 0.6),
	"stone": Color(0.82, 0.86, 0.95),
	"wood": Color(0.62, 0.38, 0.16),
	"rock": Color(0.3, 0.28, 0.27),
	"animal": Color(1.0, 0.95, 0.7),
	"fire": Color(1.0, 0.55, 0.15),
	"camp": Color(0.55, 0.85, 0.5),
	"player": Color(0.25, 0.6, 1.0),
	"north": Color(0.95, 0.55, 0.35),
	"text": Color(0.97, 0.94, 0.88),
}

var _landscape: Node3D
var _player: Node3D
var _terrain_image: ImageTexture
var _terrain_ready: bool = false
var _close_button: Button
var _elapsed: float = 0.0

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_close_button = Button.new()
	_close_button.text = tr("ACTION_CLOSE")
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.custom_minimum_size = Vector2(150, 56)
	_close_button.pressed.connect(close)
	add_child(_close_button)
	_layout_close_button()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	if not _terrain_ready:
		_build_terrain_texture()
	queue_redraw()

func close() -> void:
	visible = false

func set_context(landscape: Node3D, player: Node3D) -> void:
	_landscape = landscape
	_player = player
	_terrain_ready = false

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed >= REFRESH_PERIOD:
		_elapsed = 0.0
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_close_button()
		queue_redraw()

## Sous l'horloge du HUD (coin haut droit), pour ne pas la recouvrir.
func _layout_close_button() -> void:
	if _close_button != null:
		_close_button.position = Vector2(size.x - _close_button.custom_minimum_size.x - 16.0, 72.0)

# --- Terrain ---------------------------------------------------------------------

func _terrain_size() -> float:
	if _landscape != null and _landscape.get("terrain_size") != null:
		return maxf(1.0, float(_landscape.get("terrain_size")))
	return 400.0

func _build_terrain_texture() -> void:
	_terrain_image = MapPanel.build_terrain_texture(_landscape, RESOLUTION)
	_terrain_ready = _landscape != null and _landscape.has_method("terrain_height_at")

## Échantillonne terrain_height_at, colore par altitude et ajoute un ombrage de relief
## (lumière venant du nord-ouest) pour que les falaises et le lit du canyon se lisent.
## Partagée avec la mini-carte du HUD.
static func build_terrain_texture(landscape: Node3D, resolution: int) -> ImageTexture:
	var img := Image.create(resolution, resolution, false, Image.FORMAT_RGB8)
	if landscape == null or not landscape.has_method("terrain_height_at"):
		img.fill(COLORS["mid"])
		return ImageTexture.create_from_image(img)
	var terrain_size := 400.0
	if landscape.get("terrain_size") != null:
		terrain_size = maxf(1.0, float(landscape.get("terrain_size")))
	var heights := PackedFloat32Array()
	heights.resize(resolution * resolution)
	for py in resolution:
		for px in resolution:
			var wx := (float(px) / float(resolution - 1) - 0.5) * terrain_size
			var wz := (float(py) / float(resolution - 1) - 0.5) * terrain_size
			heights[py * resolution + px] = landscape.call("terrain_height_at", wx, wz)
	var cell := terrain_size / float(resolution - 1)
	for py in resolution:
		for px in resolution:
			var h := heights[py * resolution + px]
			var left := heights[py * resolution + maxi(px - 1, 0)]
			var right := heights[py * resolution + mini(px + 1, resolution - 1)]
			var up := heights[maxi(py - 1, 0) * resolution + px]
			var down := heights[mini(py + 1, resolution - 1) * resolution + px]
			var dx := (right - left) / (2.0 * cell)
			var dz := (down - up) / (2.0 * cell)
			var light := clampf(0.78 + (dx + dz) * 1.4, 0.45, 1.25)
			var t := clampf((h + 12.0) / 42.0, 0.0, 1.0)
			var color: Color = COLORS["low"].lerp(COLORS["mid"], minf(t * 2.0, 1.0))
			color = color.lerp(COLORS["high"], clampf(t * 2.0 - 1.0, 0.0, 1.0))
			img.set_pixel(px, py, Color(color.r * light, color.g * light, color.b * light))
	return ImageTexture.create_from_image(img)

# --- Dessin ----------------------------------------------------------------------

## Zone carrée de la carte, centrée, avec la place du titre en haut.
func _map_rect() -> Rect2:
	# 84 px en haut (titre, légende compacte) et 92 px en bas (barre Journal/Carte/Vue du HUD).
	var side := maxf(120.0, minf(size.x - 48.0, size.y - 176.0))
	return Rect2(Vector2((size.x - side) * 0.5, 84.0), Vector2(side, side))

func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	if _terrain_image == null:
		_build_terrain_texture()
	draw_rect(Rect2(Vector2.ZERO, size), COLORS["backdrop"])
	var font := ThemeDB.fallback_font

	var rect := _map_rect()
	draw_texture_rect(_terrain_image, rect, false)
	draw_rect(rect, COLORS["frame"], false, 3.0)
	var to_map := _world_to_map_transform(rect)
	_draw_resources(to_map, rect)
	_draw_player(to_map, rect)
	var north_pos := Vector2(rect.end.x - 30.0, rect.position.y + 32.0)
	draw_string_outline(font, north_pos, "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 28, 6, Color(0.08, 0.05, 0.03, 0.95))
	draw_string(font, north_pos, "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 28, COLORS["north"])
	_draw_legend(rect, font)

func _world_to_map_transform(rect: Rect2) -> Transform2D:
	var scale := rect.size.x / _terrain_size()
	return Transform2D(Vector2(scale, 0.0), Vector2(0.0, scale), rect.get_center())

func _draw_resources(to_map: Transform2D, rect: Rect2) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for group in ["breakable", "wood", "stone", "animals", "campfire", "structures"]:
		for node in tree.get_nodes_in_group(group):
			if not (node is Node3D) or not is_instance_valid(node):
				continue
			var position := to_map * Vector2((node as Node3D).global_position.x, (node as Node3D).global_position.z)
			if not rect.has_point(position):
				continue
			_draw_marker(group, position)

## Formes distinctes (pas seulement des couleurs) pour rester lisible en plein soleil.
func _draw_marker(kind: String, pos: Vector2) -> void:
	var outline := Color(0.08, 0.05, 0.03, 0.9)
	match kind:
		"stone":
			draw_circle(pos, 5.0, outline)
			draw_circle(pos, 3.5, COLORS["stone"])
		"wood":
			draw_rect(Rect2(pos - Vector2(5, 5), Vector2(10, 10)), outline)
			draw_rect(Rect2(pos - Vector2(3.5, 3.5), Vector2(7, 7)), COLORS["wood"])
		"breakable":
			var outer := PackedVector2Array([pos + Vector2(0, -7), pos + Vector2(7, 0), pos + Vector2(0, 7), pos + Vector2(-7, 0)])
			var inner := PackedVector2Array([pos + Vector2(0, -5), pos + Vector2(5, 0), pos + Vector2(0, 5), pos + Vector2(-5, 0)])
			draw_colored_polygon(outer, outline)
			draw_colored_polygon(inner, COLORS["rock"].lightened(0.25))
		"animals":
			draw_circle(pos, 4.5, outline)
			draw_circle(pos, 3.0, COLORS["animal"])
		"campfire":
			# Flamme : triangle pointe en haut.
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -10), pos + Vector2(8, 7), pos + Vector2(-8, 7)]), outline)
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -7), pos + Vector2(5, 5), pos + Vector2(-5, 5)]), COLORS["fire"])
		"structures":
			# Maison : carré surmonté d'un toit.
			draw_colored_polygon(PackedVector2Array([pos + Vector2(-9, -1), pos + Vector2(0, -10), pos + Vector2(9, -1), pos + Vector2(9, 8), pos + Vector2(-9, 8)]), outline)
			draw_colored_polygon(PackedVector2Array([pos + Vector2(-6, 0), pos + Vector2(0, -6), pos + Vector2(6, 0), pos + Vector2(6, 5), pos + Vector2(-6, 5)]), COLORS["camp"])

func _draw_player(to_map: Transform2D, rect: Rect2) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var pos := to_map * Vector2(_player.global_position.x, _player.global_position.z)
	pos = pos.clamp(rect.position + Vector2(8, 8), rect.end - Vector2(8, 8))
	var heading := 0.0
	if _player.has_method("get_heading_degrees"):
		heading = deg_to_rad(float(_player.call("get_heading_degrees")))
	var dir := Vector2(sin(heading), -cos(heading))
	var side := Vector2(-dir.y, dir.x)
	var arrow := PackedVector2Array([pos + dir * 14.0, pos - dir * 9.0 + side * 8.0, pos - dir * 4.0, pos - dir * 9.0 - side * 8.0])
	var shadow := PackedVector2Array()
	for point in arrow:
		shadow.append(pos + (point - pos) * 1.35)
	draw_colored_polygon(shadow, Color(1, 1, 1, 0.95))
	draw_colored_polygon(arrow, COLORS["player"])

func _draw_legend(rect: Rect2, font: Font) -> void:
	var entries := [
		["player", "MAP_LEGEND_YOU"], ["stone", "MAP_LEGEND_STONE"], ["wood", "MAP_LEGEND_WOOD"],
		["breakable", "MAP_LEGEND_ROCK"], ["animals", "MAP_LEGEND_ANIMAL"],
		["campfire", "MAP_LEGEND_FIRE"], ["structures", "MAP_LEGEND_CAMP"],
	]
	if rect.position.x < 200.0:
		# Écran étroit : titre et légende en ligne, sous la barre du haut.
		draw_string(font, Vector2(24.0, 150.0), tr("MAP_TITLE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, COLORS["text"])
		return
	# Colonne de gauche, sous le cap et l'objectif du HUD, au-dessus du stick.
	var x := 28.0
	var y := 160.0
	draw_string(font, Vector2(x, y), tr("MAP_TITLE"), HORIZONTAL_ALIGNMENT_LEFT, rect.position.x - 48.0, 26, COLORS["text"])
	y += 22.0
	draw_line(Vector2(x, y), Vector2(rect.position.x - 24.0, y), Color(COLORS["frame"], 0.6), 2.0)
	y += 34.0
	for entry in entries:
		_draw_legend_icon(entry[0], Vector2(x + 10.0, y - 7.0))
		draw_string(font, Vector2(x + 34.0, y), tr(entry[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, COLORS["text"])
		y += 34.0

func _draw_legend_icon(kind: String, pos: Vector2) -> void:
	if kind == "player":
		var arrow := PackedVector2Array([pos + Vector2(0, -9), pos + Vector2(7, 7), pos + Vector2(0, 3), pos + Vector2(-7, 7)])
		draw_colored_polygon(arrow, COLORS["player"])
	else:
		_draw_marker(kind, pos)
