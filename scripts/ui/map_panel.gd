class_name MapPanel
extends Control
## Carte du canyon : topographie du terrain (courbes de niveau simplifiées),
## ressources (pierre/bois/rochers cassables) et position + cap du joueur.

const MAP_SCALE := 0.55
const COLORS := {
	"ground": Color(0.78, 0.62, 0.42),
	"ground_dark": Color(0.66, 0.5, 0.32),
	"stone": Color(0.45, 0.45, 0.5),
	"wood": Color(0.55, 0.35, 0.15),
	"rock": Color(0.35, 0.33, 0.3),
	"player": Color(0.2, 0.55, 1.0),
	"north": Color(0.9, 0.9, 0.9),
}

var _landscape: Node3D
var _player: Node3D
var _terrain_image: ImageTexture
var _terrain_ready: bool = false

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	queue_redraw()

func close() -> void:
	visible = false

func set_context(landscape: Node3D, player: Node3D) -> void:
	_landscape = landscape
	_player = player

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_terrain_ready = false
		queue_redraw()

func _draw() -> void:
	if _terrain_ready == false:
		_build_terrain_texture()
	var size := get_rect().size
	if size.x <= 1.0 or size.y <= 1.0:
		return
	
	draw_texture_rect(_terrain_image, Rect2(Vector2.ZERO, size), false)
	var to_map := _world_to_map_transform(size)
	_draw_resources(to_map)
	_draw_player(to_map)
	_draw_compass_rose(size)

## Échantillonne terrain_height_at sur une grille et colore par altitude.
func _build_terrain_texture() -> void:
	if _landscape == null or not _landscape.has_method("terrain_height_at"):
		var fallback := Image.create(8, 8, false, Image.FORMAT_RGB8)
		fallback.fill(COLORS["ground"])
		_terrain_image = ImageTexture.create_from_image(fallback)
		return
	var resolution := 160
	var img := Image.create(resolution, resolution, false, Image.FORMAT_RGB8)
	var terrain_size: float = _landscape.get("terrain_size")
	if terrain_size <= 0.0:
		terrain_size = 400.0
	for py in resolution:
		for px in resolution:
			var wx := (float(px) / float(resolution) - 0.5) * terrain_size
			var wz := (float(py) / float(resolution) - 0.5) * terrain_size
			var h: float = _landscape.call("terrain_height_at", wx, wz)
			var shade := clampf((h + 10.0) / 40.0, 0.0, 1.0)
			var color: Color = COLORS["ground_dark"].lerp(COLORS["ground"], shade)
			if h < -5.0:
				color = color.darkened(0.35)
			img.set_pixel(px, py, color)
	_terrain_image = ImageTexture.create_from_image(img)
	_terrain_ready = true

func _world_to_map_transform(map_size: Vector2) -> Transform2D:
	var terrain_size: float = 400.0
	if _landscape != null and _landscape.get("terrain_size") != null:
		terrain_size = float(_landscape.get("terrain_size"))
	var scale := minf(map_size.x, map_size.y) / terrain_size
	return Transform2D(Vector2(scale, 0.0), Vector2(0.0, scale), Vector2(map_size.x, map_size.y) * 0.5)

func _draw_resources(to_map: Transform2D) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	for group in ["collectible", "breakable", "wood", "stone"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D and is_instance_valid(node):
				var pos2 := to_map * Vector2((node as Node3D).global_position.x, (node as Node3D).global_position.z)
				var color: Color = COLORS["rock"]
				if group == "wood":
					color = COLORS["wood"]
				elif group == "stone" or group == "collectible":
					color = COLORS["stone"]
				draw_circle(pos2, 3.0, color)

func _draw_player(to_map: Transform2D) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var pos2 := to_map * Vector2(_player.global_position.x, _player.global_position.z)
	draw_circle(pos2, 6.0, COLORS["player"])
	var heading := 0.0
	if _player.has_method("get_heading_degrees"):
		heading = deg_to_rad(float(_player.call("get_heading_degrees")))
	var dir := Vector2(sin(heading), -cos(heading))
	draw_line(pos2, pos2 + dir * 18.0, COLORS["player"], 2.0, true)

func _draw_compass_rose(size: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var pos := Vector2(size.x - 8.0, 8.0)
	draw_string(font, pos, "N", HORIZONTAL_ALIGNMENT_RIGHT, -1, 22, COLORS["north"])
