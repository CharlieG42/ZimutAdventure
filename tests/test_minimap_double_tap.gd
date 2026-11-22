extends SceneTree
## Sur téléphone, un appui sur la mini-carte arrive en double (toucher + souris émulée) :
## la carte doit rester ouverte, et un appui franc ultérieur la referme.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as CanvasLayer
	root.add_child(hud)
	await process_frame
	await process_frame
	var mm: Control = hud.get_node("Overlay/MiniMap")
	var panel: Control = hud.get_node("MapPanel")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(10, 10)
	var mouse := InputEventMouseButton.new()
	mouse.pressed = true
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = Vector2(10, 10)
	mm.call("_gui_input", touch)
	mm.call("_gui_input", mouse)
	await process_frame
	if not panel.visible:
		errors.append("la carte doit rester ouverte après un appui doublé (toucher + souris)")
	if panel.size.x < 300.0 or panel.size.y < 300.0:
		errors.append("la carte doit occuper l'écran, taille %s" % str(panel.size))
	await create_timer(0.45).timeout
	mm.call("_gui_input", touch)
	await process_frame
	if panel.visible:
		errors.append("un nouvel appui franc doit refermer la carte")
	if errors.is_empty():
		print("TEST_MINIMAP_DOUBLE_TAP: PASS")
		quit(0)
	else:
		for e in errors: printerr("TEST_MINIMAP_DOUBLE_TAP FAIL: " + e)
		quit(1)
