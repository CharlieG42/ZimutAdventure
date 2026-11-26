class_name MapPanel
extends Control
## Carte du canyon : relief ombré (altitude + éclairage rasant), ressources (pierre,
## bois, rochers cassables), animaux et position + cap du joueur.
## Le Nord est en haut (axe -Z du monde), comme la boussole du HUD.

const RESOLUTION := 160
const REFRESH_PERIOD := 0.2
## Teintes des zones sur la carte : pinède, mesas, berges, eau.
const ZONE_TINTS := [Color(0.42, 0.52, 0.3), Color(0.78, 0.38, 0.22), Color(0.56, 0.64, 0.34), Color(0.3, 0.58, 0.78)]
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
	"marker": Color(1.0, 0.82, 0.2),
	"north": Color(0.95, 0.55, 0.35),
	"text": Color(0.97, 0.94, 0.88),
}

var _landscape: Node3D
var _player: Node3D
var _terrain_image: ImageTexture
var _terrain_ready: bool = false
var _close_button: Button
var _elapsed: float = 0.0
var _travel_button: Button
var _selected_site: String = ""
## Repères du joueur : bouton poser / retirer, repère sélectionné, point touché en attente.
var _marker_button: Button
var _selected_marker: int = -1
var _pending_point: Vector2 = Vector2.INF
## Zoom (1 = monde entier) et point du monde au centre de la carte ; on fait glisser pour
## se déplacer, on zoome avec les boutons + / − (ou la molette).
const ZOOMS := [1.0, 2.0, 3.0]
var zoom_index: int = 0
var _focus: Vector2 = Vector2.ZERO
var _press_at: Vector2 = Vector2.INF
var _dragged: bool = false
const DRAG_THRESHOLD := 14.0
var _zoom_in_button: Button
var _zoom_out_button: Button
var _center_button: Button

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Relief lissé quand on zoome (la texture fait 160 px).
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_close_button = Button.new()
	_close_button.text = tr("ACTION_CLOSE")
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.custom_minimum_size = Vector2(150, 56)
	_close_button.pressed.connect(close)
	add_child(_close_button)
	_travel_button = Button.new()
	_travel_button.focus_mode = Control.FOCUS_NONE
	_travel_button.custom_minimum_size = Vector2(220, 60)
	_travel_button.visible = false
	_travel_button.pressed.connect(_on_travel_pressed)
	add_child(_travel_button)
	_marker_button = Button.new()
	_marker_button.focus_mode = Control.FOCUS_NONE
	_marker_button.custom_minimum_size = Vector2(260, 60)
	_marker_button.visible = false
	_marker_button.pressed.connect(_on_marker_pressed)
	add_child(_marker_button)
	_zoom_in_button = _small_button("+", "MapZoomIn", func(): set_zoom(zoom_index + 1))
	_zoom_out_button = _small_button("−", "MapZoomOut", func(): set_zoom(zoom_index - 1))
	_center_button = _small_button("◎", "MapCenter", center_on_player)
	_layout_close_button()

func _small_button(text: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(64, 64)
	button.add_theme_font_size_override("font_size", 30)
	button.pressed.connect(callback)
	add_child(button)
	return button

func zoom() -> float:
	return float(ZOOMS[zoom_index])

## Change le zoom en gardant le joueur (ou le point actuel) au centre.
func set_zoom(index: int) -> void:
	zoom_index = clampi(index, 0, ZOOMS.size() - 1)
	if zoom_index == 0:
		_focus = Vector2.ZERO
	_clamp_focus()
	_layout_close_button()
	queue_redraw()

func center_on_player() -> void:
	if _player != null and is_instance_valid(_player):
		_focus = Vector2(_player.global_position.x, _player.global_position.z)
	if zoom_index == 0:
		set_zoom(1)
	_clamp_focus()
	queue_redraw()

func focus() -> Vector2:
	return _focus

## Le cadre ne sort jamais du monde.
func _clamp_focus() -> void:
	var half_span := _terrain_size() * 0.5 / zoom()
	var limit := maxf(0.0, _terrain_size() * 0.5 - half_span)
	_focus = _focus.clamp(Vector2(-limit, -limit), Vector2(limit, limit))

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	# Toujours le monde entier à l'ouverture.
	set_zoom(0)
	if not _terrain_ready:
		_build_terrain_texture()
	queue_redraw()

func close() -> void:
	visible = false
	_select_site("")
	_clear_marker_selection()

# --- Repères du joueur -----------------------------------------------------------------------------

func _clear_marker_selection() -> void:
	_selected_marker = -1
	_pending_point = Vector2.INF
	if _marker_button != null:
		_marker_button.visible = false
	queue_redraw()

## Un toucher sur la carte (coordonnées monde) : sélectionne le repère voisin, sinon propose
## d'en poser un à cet endroit. `pick_radius` : rayon de sélection en mètres.
func touch_world_point(world: Vector2, pick_radius: float) -> void:
	var exploration := InteractionManager.get_exploration()
	if exploration == null:
		return
	_selected_marker = int(exploration.call("marker_near", world.x, world.y, pick_radius))
	_pending_point = Vector2.INF
	if _selected_marker >= 0:
		exploration.call("set_tracked", _selected_marker)
		_marker_button.text = tr("MAP_MARKER_REMOVE")
	elif bool(exploration.call("can_add_marker")):
		_pending_point = world
		_marker_button.text = tr("MAP_MARKER_ADD")
	else:
		_show_toast(tr("TOAST_MARKERS_FULL"))
		_marker_button.visible = false
		queue_redraw()
		return
	_marker_button.visible = true
	_marker_button.position = Vector2((size.x - _marker_button.custom_minimum_size.x) * 0.5, size.y - 86.0 - _marker_button.custom_minimum_size.y)
	queue_redraw()

func _on_marker_pressed() -> void:
	var exploration := InteractionManager.get_exploration()
	if exploration == null:
		return
	if _selected_marker >= 0:
		exploration.call("remove_marker", _selected_marker)
		_clear_marker_selection()
	elif _pending_point != Vector2.INF:
		_selected_marker = int(exploration.call("add_marker", _pending_point.x, _pending_point.y))
		_pending_point = Vector2.INF
		_marker_button.text = tr("MAP_MARKER_REMOVE")
		_marker_button.visible = _selected_marker >= 0
		queue_redraw()

## Texte « Azimut 240° · 180 m » d'un point vu depuis le joueur.
func _bearing_text(world: Vector2) -> String:
	if _player == null or not is_instance_valid(_player):
		return ""
	var from := Vector2(_player.global_position.x, _player.global_position.z)
	var exploration := InteractionManager.get_exploration()
	var azimuth := int(roundf(float(exploration.call("bearing", from, world)))) % 360
	return tr("MAP_MARKER_INFO") % [azimuth, int(roundf(from.distance_to(world)))]

func _draw_markers(to_map: Transform2D, rect: Rect2, font: Font) -> void:
	var exploration := InteractionManager.get_exploration()
	if exploration == null:
		return
	var markers: Array = exploration.call("get_markers")
	var tracked := int(exploration.call("get_tracked_index"))
	for i in markers.size():
		var pos: Vector2 = to_map * (markers[i] as Vector2)
		if not rect.has_point(pos):
			continue
		_draw_flag(pos, i == tracked)
		if i == tracked or i == _selected_marker:
			_draw_caption(font, pos, _bearing_text(markers[i]))
	if _pending_point != Vector2.INF:
		var pos := to_map * _pending_point
		draw_arc(pos, 12.0, 0.0, TAU, 20, Color(1, 1, 1, 0.95), 2.5)
		draw_line(pos - Vector2(6, 0), pos + Vector2(6, 0), Color(1, 1, 1, 0.95), 2.0)
		draw_line(pos - Vector2(0, 6), pos + Vector2(0, 6), Color(1, 1, 1, 0.95), 2.0)
		_draw_caption(font, pos, _bearing_text(_pending_point))

## Fanion : une hampe et un triangle, forme réservée aux repères du joueur.
func _draw_flag(pos: Vector2, highlighted: bool) -> void:
	var dark := Color(0.08, 0.05, 0.03, 0.95)
	var fill: Color = COLORS["marker"] if highlighted else COLORS["marker"].darkened(0.3)
	draw_line(pos + Vector2(0, 2), pos + Vector2(0, -22), dark, 5.0)
	draw_colored_polygon(PackedVector2Array([pos + Vector2(-1, -24), pos + Vector2(19, -17), pos + Vector2(-1, -9)]), dark)
	draw_line(pos, pos + Vector2(0, -21), Color(0.97, 0.94, 0.88), 2.0)
	draw_colored_polygon(PackedVector2Array([pos + Vector2(1, -21.5), pos + Vector2(15, -17), pos + Vector2(1, -11.5)]), fill)
	draw_circle(pos, 3.0, dark)

func _draw_caption(font: Font, pos: Vector2, text: String) -> void:
	if text.is_empty():
		return
	var at := pos + Vector2(-90.0, 24.0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 180, 18, 5, Color(0.08, 0.05, 0.03, 0.95))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 180, 18, COLORS["text"])

# --- Sites et voyage rapide ------------------------------------------------------------------

func _select_site(site_id: String) -> void:
	_selected_site = site_id
	if _travel_button == null:
		return
	_travel_button.visible = site_id != ""
	if site_id != "":
		var exploration := InteractionManager.get_exploration()
		var site: Dictionary = exploration.call("get_site", site_id) if exploration != null else {}
		_travel_button.text = tr("MAP_TRAVEL_TO") % tr(String(site.get("name", "")))
		_travel_button.position = Vector2((size.x - _travel_button.custom_minimum_size.x) * 0.5, size.y - 86.0 - _travel_button.custom_minimum_size.y)
	queue_redraw()

func _on_travel_pressed() -> void:
	var exploration := InteractionManager.get_exploration()
	if exploration == null or _selected_site == "":
		return
	var error := String(exploration.call("fast_travel", _selected_site, _player))
	if error != "":
		_show_toast(tr(error))
		return
	close()

func _show_toast(message: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 2.4)

func _gui_input(event: InputEvent) -> void:
	# Molette : zoom.
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		set_zoom(zoom_index + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1))
		accept_event()
		return
	var down := false
	var up := false
	var at := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		down = event.pressed
		up = not event.pressed
		at = event.position
	elif event is InputEventScreenTouch:
		down = event.pressed
		up = not event.pressed
		at = event.position
	elif (event is InputEventScreenDrag or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT)) and _press_at != Vector2.INF:
		if not _dragged and event.position.distance_to(_press_at) > DRAG_THRESHOLD:
			_dragged = true
		if _dragged and zoom_index > 0:
			var scale := _world_to_map_transform(_map_rect()).get_scale().x
			_focus -= event.relative / scale
			_clamp_focus()
			queue_redraw()
		accept_event()
		return
	if down:
		_press_at = at
		_dragged = false
		accept_event()
		return
	if not up or _press_at == Vector2.INF:
		return
	var was_drag := _dragged
	_press_at = Vector2.INF
	_dragged = false
	if was_drag:
		return
	tap_at(at)

## Toucher bref sur la carte : site découvert (voyage) ou repère du joueur.
func tap_at(at: Vector2) -> void:
	var exploration := InteractionManager.get_exploration()
	if exploration == null:
		return
	var to_map := _world_to_map_transform(_map_rect())
	var best := ""
	var best_distance := 36.0
	for site_id in exploration.call("get_discovered_ids"):
		var site: Dictionary = exploration.call("get_site", site_id)
		var pos3: Vector3 = site["pos"]
		var distance := (to_map * Vector2(pos3.x, pos3.z)).distance_to(at)
		if distance < best_distance:
			best_distance = distance
			best = String(site_id)
	_select_site(best)
	if best != "":
		_clear_marker_selection()
		return
	# Ailleurs sur la carte : repères du joueur.
	var rect := _map_rect()
	if not rect.has_point(at):
		_clear_marker_selection()
		return
	var world := to_map.affine_inverse() * at
	touch_world_point(world, 30.0 / to_map.get_scale().x)

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
	# Zoom à droite de la carte, en colonne.
	if _zoom_in_button != null:
		var rect := _map_rect()
		var x := minf(rect.end.x + 12.0, size.x - 76.0)
		_zoom_in_button.position = Vector2(x, rect.position.y + 70.0)
		_zoom_out_button.position = Vector2(x, rect.position.y + 142.0)
		_center_button.position = Vector2(x, rect.position.y + 214.0)
		_zoom_in_button.disabled = zoom_index >= ZOOMS.size() - 1
		_zoom_out_button.disabled = zoom_index <= 0

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
	var zoned := landscape.has_method("zone_weights") and landscape.has_method("is_water")
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
			color = Color(color.r * light, color.g * light, color.b * light)
			if zoned:
				# Zones : pinède verte, mesas rouges, berges herbeuses, eau bleue.
				var wx := (float(px) / float(resolution - 1) - 0.5) * terrain_size
				var wz := (float(py) / float(resolution - 1) - 0.5) * terrain_size
				var weights: Array = landscape.call("zone_weights", wx, wz)
				color = color.lerp(ZONE_TINTS[0] * light, float(weights[1]) * 0.55)
				color = color.lerp(ZONE_TINTS[1] * light, float(weights[2]) * 0.45)
				color = color.lerp(ZONE_TINTS[2] * light, float(weights[3]) * 0.6)
				if bool(landscape.call("is_water", wx, wz)):
					color = ZONE_TINTS[3]
			img.set_pixel(px, py, color)
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
	# Partie visible du monde (tout le monde au zoom 1).
	var terrain := _terrain_size()
	var span := terrain / zoom()
	var tex_size := Vector2(_terrain_image.get_size())
	var src_origin := (_focus - Vector2(span, span) * 0.5 + Vector2(terrain, terrain) * 0.5) / terrain * tex_size
	draw_texture_rect_region(_terrain_image, rect, Rect2(src_origin, tex_size / zoom()))
	draw_rect(rect, COLORS["frame"], false, 3.0)
	var to_map := _world_to_map_transform(rect)
	_draw_resources(to_map, rect)
	_draw_sites(to_map, rect, font)
	_draw_fog(rect)
	_draw_zone_labels(to_map, rect, font)
	_draw_markers(to_map, rect, font)
	_draw_player(to_map, rect)
	var north_pos := Vector2(rect.end.x - 30.0, rect.position.y + 32.0)
	draw_string_outline(font, north_pos, "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 28, 6, Color(0.08, 0.05, 0.03, 0.95))
	draw_string(font, north_pos, "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 28, COLORS["north"])
	_draw_legend(rect, font)

func _world_to_map_transform(rect: Rect2) -> Transform2D:
	var scale := rect.size.x / _terrain_size() * zoom()
	return Transform2D(Vector2(scale, 0.0), Vector2(0.0, scale), rect.get_center() - _focus * scale)

func _draw_resources(to_map: Transform2D, rect: Rect2) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for group in ["breakable", "wood", "stone", "animals", "campfire", "structures", "choppable", "berries", "domestic", "fishing"]:
		for node in tree.get_nodes_in_group(group):
			if not (node is Node3D) or not is_instance_valid(node):
				continue
			var position := to_map * Vector2((node as Node3D).global_position.x, (node as Node3D).global_position.z)
			if not rect.has_point(position):
				continue
			var exploration := InteractionManager.get_exploration()
			if exploration != null and not bool(exploration.call("is_revealed", (node as Node3D).global_position.x, (node as Node3D).global_position.z)):
				continue
			_draw_marker(group, position)

## Cases du monde pas encore explorées : voile sombre, tracé par bandes horizontales.
func _draw_fog(rect: Rect2) -> void:
	var exploration := InteractionManager.get_exploration()
	if exploration == null:
		return
	var grid := int(exploration.get("GRID"))
	var terrain := _terrain_size()
	var to_map := _world_to_map_transform(rect)
	var world_origin := to_map * Vector2(-terrain * 0.5, -terrain * 0.5)
	var cell := terrain / float(grid) * to_map.get_scale().x
	# Voile assez léger pour que la forme du monde (relief, rivière) reste lisible.
	var veil := Color(0.04, 0.03, 0.03, 0.62)
	for cz in grid:
		var run_start := -1
		for cx in grid + 1:
			var hidden := cx < grid and not bool(exploration.call("is_cell_revealed", cx, cz))
			if hidden and run_start < 0:
				run_start = cx
			elif not hidden and run_start >= 0:
				var band := Rect2(world_origin + Vector2(float(run_start) * cell, float(cz) * cell), Vector2(float(cx - run_start) * cell + 1.0, cell + 1.0))
				band = band.intersection(rect)
				if band.has_area():
					draw_rect(band, veil)
				run_start = -1

func _draw_sites(to_map: Transform2D, rect: Rect2, font: Font) -> void:
	var exploration := InteractionManager.get_exploration()
	if exploration == null:
		return
	for site_id in exploration.call("get_discovered_ids"):
		var site: Dictionary = exploration.call("get_site", site_id)
		var pos3: Vector3 = site["pos"]
		var pos := to_map * Vector2(pos3.x, pos3.z)
		if not rect.has_point(pos):
			continue
		_draw_marker("site", pos)
		if String(site_id) == _selected_site:
			draw_arc(pos, 16.0, 0.0, TAU, 24, Color(1, 1, 1, 0.95), 3.0)
			var label := tr(String(site["name"]))
			draw_string_outline(font, pos + Vector2(-60.0, -22.0), label, HORIZONTAL_ALIGNMENT_LEFT, 200, 20, 5, Color(0.08, 0.05, 0.03, 0.95))
			draw_string(font, pos + Vector2(-60.0, -22.0), label, HORIZONTAL_ALIGNMENT_LEFT, 200, 20, COLORS["text"])

## Nom des zones déjà visitées (leur point d'ancrage est sorti du brouillard).
func _draw_zone_labels(to_map: Transform2D, rect: Rect2, font: Font) -> void:
	if _landscape == null or not _landscape.has_method("get_zone_labels"):
		return
	var exploration := InteractionManager.get_exploration()
	for label in _landscape.call("get_zone_labels"):
		var x := float(label["x"])
		var z := float(label["z"])
		if exploration != null and not bool(exploration.call("is_revealed", x, z)):
			continue
		var pos := to_map * Vector2(x, z)
		if not rect.has_point(pos):
			continue
		var text := tr(String(label["name"]))
		var at := pos + Vector2(-110.0, 6.0)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 220, 18, 5, Color(0.08, 0.05, 0.03, 0.9))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 220, 18, Color(0.97, 0.94, 0.88, 0.9))

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
		"choppable":
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -10), pos + Vector2(8, 7), pos + Vector2(-8, 7)]), outline)
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -7), pos + Vector2(5, 5), pos + Vector2(-5, 5)]), Color(0.3, 0.6, 0.25))
		"domestic":
			draw_rect(Rect2(pos - Vector2(5.5, 5.5), Vector2(11, 11)), outline)
			draw_rect(Rect2(pos - Vector2(3.8, 3.8), Vector2(7.6, 7.6)), Color(0.95, 0.75, 0.55))
		"berries":
			draw_circle(pos, 5.0, outline)
			draw_circle(pos, 3.5, Color(0.9, 0.15, 0.25))
		"site":
			# Étoile à quatre branches dorée.
			var star := PackedVector2Array([pos + Vector2(0, -11), pos + Vector2(3, -3), pos + Vector2(11, 0), pos + Vector2(3, 3), pos + Vector2(0, 11), pos + Vector2(-3, 3), pos + Vector2(-11, 0), pos + Vector2(-3, -3)])
			draw_colored_polygon(star, outline)
			var core := PackedVector2Array()
			for point in star:
				core.append(pos + (point - pos) * 0.72)
			draw_colored_polygon(core, Color(1.0, 0.82, 0.25))
		"fishing":
			draw_circle(pos, 7.0, outline)
			draw_circle(pos, 5.2, Color(0.3, 0.6, 0.95))
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
		["site", "MAP_LEGEND_SITE"], ["fishing", "MAP_LEGEND_POND"], ["choppable", "MAP_LEGEND_TREE"], ["berries", "MAP_LEGEND_BERRY"], ["domestic", "MAP_LEGEND_DOMESTIC"],
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
