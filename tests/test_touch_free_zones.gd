extends SceneTree
## Le glisser caméra et le stick flottant fonctionnent partout hors boutons :
## aucune zone morte dans les coins, même avec le stick caméra masqué.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var look_scene := load("res://scenes/ui/touch_look.tscn") as PackedScene
	var look := look_scene.instantiate() as Control
	look.size = Vector2(1600.0, 720.0)
	root.add_child(look)
	await process_frame
	look.size = Vector2(1600.0, 720.0)

	var deltas: Array[Vector2] = []
	var moves: Array[Vector2] = []
	look.connect("look_delta", func(d): deltas.append(d))
	look.connect("move_changed", func(v): moves.append(v))

	# Coins bas-droit, haut-droit, haut-gauche : caméra.
	var index := 0
	for corner in [Vector2(1560.0, 700.0), Vector2(1560.0, 20.0), Vector2(30.0, 40.0), Vector2(900.0, 360.0)]:
		deltas.clear()
		index += 1
		var press := InputEventScreenTouch.new()
		press.index = index
		press.pressed = true
		press.position = corner
		look.call("_gui_input", press)
		var drag := InputEventScreenDrag.new()
		drag.index = index
		drag.position = corner
		drag.relative = Vector2(40.0, 10.0)
		look.call("_gui_input", drag)
		if deltas.is_empty():
			errors.append("pas de rotation caméra à %s" % str(corner))
		var release := InputEventScreenTouch.new()
		release.index = index
		release.pressed = false
		release.position = corner
		look.call("_gui_input", release)

	# Bas-gauche : stick flottant, avec la caméra en parallèle au pouce droit.
	var press_move := InputEventScreenTouch.new()
	press_move.index = 10
	press_move.pressed = true
	press_move.position = Vector2(60.0, 650.0)
	look.call("_gui_input", press_move)
	if not look.call("is_moving"):
		errors.append("toucher bas-gauche : le stick flottant devrait démarrer")
	var drag_move := InputEventScreenDrag.new()
	drag_move.index = 10
	drag_move.position = Vector2(160.0, 650.0)
	look.call("_gui_input", drag_move)
	if moves.is_empty() or moves[-1].x <= 0.3:
		errors.append("stick flottant : +x attendu, reçu %s" % (str(moves[-1]) if not moves.is_empty() else "rien"))
	deltas.clear()
	var press_look := InputEventScreenTouch.new()
	press_look.index = 11
	press_look.pressed = true
	press_look.position = Vector2(1300.0, 500.0)
	look.call("_gui_input", press_look)
	var drag_look := InputEventScreenDrag.new()
	drag_look.index = 11
	drag_look.relative = Vector2(-30.0, 0.0)
	look.call("_gui_input", drag_look)
	if deltas.is_empty() or deltas[-1].x >= 0.0:
		errors.append("caméra pendant le déplacement : -x attendu")
	var release_move := InputEventScreenTouch.new()
	release_move.index = 10
	release_move.pressed = false
	look.call("_gui_input", release_move)
	if look.call("is_moving") or moves[-1] != Vector2.ZERO:
		errors.append("le relâchement doit arrêter le déplacement")

	if errors.is_empty():
		print("TEST_TOUCH_FREE_ZONES: PASS")
		quit(0)
	else:
		for e in errors:
			printerr("TEST_TOUCH_FREE_ZONES FAIL: " + e)
		quit(1)
