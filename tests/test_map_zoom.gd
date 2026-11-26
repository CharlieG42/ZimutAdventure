extends SceneTree
## Carte : un appui sur la mini-carte ouvre la carte du monde entier ; zoom, centrage sur le
## joueur, déplacement en faisant glisser, un toucher bref reste un toucher (repère).

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	await process_frame
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 15:
		await process_frame
	paused = false
	for c in world.find_children("CharacterCreator", "", true, false):
		c.visible = false
	await process_frame
	var hud := world.get_node("HUD")
	var minimap: Control = hud.get("minimap")
	var map_panel = hud.get("map_panel")
	var touch := InputEventScreenTouch.new()
	touch.position = minimap.get_global_rect().get_center()
	touch.pressed = true
	minimap.call("_gui_input", touch)
	await process_frame
	_check(map_panel.visible, "appui sur la mini-carte : la carte s'ouvre")
	_check(map_panel.zoom() == 1.0 and map_panel.focus() == Vector2.ZERO, "monde entier à l'ouverture")
	(map_panel.find_child("MapZoomIn", true, false) as Button).pressed.emit()
	_check(map_panel.zoom() == 2.0, "bouton + : zoom ×2")
	(map_panel.find_child("MapCenter", true, false) as Button).pressed.emit()
	var player := world.get_node("Player") as Node3D
	var half := 0.5 * float(map_panel.call("_terrain_size")) * 0.5
	var expected := Vector2(player.global_position.x, player.global_position.z).clamp(Vector2(-half, -half), Vector2(half, half))
	_check(map_panel.focus().distance_to(expected) < 1.0, "centrage sur le joueur")
	var to_map: Transform2D = map_panel.call("_world_to_map_transform", map_panel.call("_map_rect"))
	_check((to_map * expected).distance_to((map_panel.call("_map_rect") as Rect2).get_center()) < 1.0, "le joueur est au centre de la carte")
	# Glisser : la vue se déplace, pas de repère posé.
	var before: Vector2 = map_panel.focus()
	var rect: Rect2 = map_panel.call("_map_rect")
	var down := InputEventScreenTouch.new()
	down.position = rect.get_center()
	down.pressed = true
	map_panel.call("_gui_input", down)
	var drag := InputEventScreenDrag.new()
	drag.position = rect.get_center() + Vector2(-60, 0)
	drag.relative = Vector2(-60, 0)
	map_panel.call("_gui_input", drag)
	var release := down.duplicate()
	release.pressed = false
	release.position = drag.position
	map_panel.call("_gui_input", release)
	_check(map_panel.focus().x > before.x or is_equal_approx(map_panel.focus().x, half), "glisser vers la gauche déplace la vue vers l'est")
	_check(map_panel.get("_pending_point") == Vector2.INF, "un glissé ne pose pas de repère")
	# Toucher bref : point en attente de repère.
	map_panel.call("_gui_input", down)
	map_panel.call("_gui_input", release.duplicate())
	var tap_release := down.duplicate()
	tap_release.pressed = false
	map_panel.call("_gui_input", down)
	map_panel.call("_gui_input", tap_release)
	_check(map_panel.get("_pending_point") != Vector2.INF or map_panel.get("_selected_marker") >= 0, "toucher bref : point de repère proposé")
	(map_panel.find_child("MapZoomOut", true, false) as Button).pressed.emit()
	_check(map_panel.zoom() == 1.0 and map_panel.focus() == Vector2.ZERO, "bouton − : retour au monde entier")
	map_panel.close()
	map_panel.open()
	_check(map_panel.zoom() == 1.0, "réouverture : monde entier")
	print("TEST_MAP_ZOOM: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
