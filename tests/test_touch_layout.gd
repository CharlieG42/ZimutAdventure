extends SceneTree

var joystick_script: GDScript = load("res://scripts/ui/virtual_joystick.gd")
var look_script: GDScript = load("res://scripts/ui/touch_look.gd")

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	var hud_scene := load("res://scenes/ui/hud.tscn") as PackedScene
	if hud_scene == null:
		printerr("TEST_TOUCH_LAYOUT FAIL: hud.tscn missing")
		quit(1)
	var hud := hud_scene.instantiate() as CanvasLayer
	root.add_child(hud)
	await process_frame

	var joystick := hud.get_node_or_null("VirtualJoystick") as Control
	var touch_look := hud.get_node_or_null("TouchLook") as Control
	if joystick == null:
		errors.append("VirtualJoystick missing at HUD root")
	if touch_look == null:
		errors.append("TouchLook missing at HUD root")
	if joystick == null or touch_look == null:
		for e in errors: printerr("TEST_TOUCH_LAYOUT FAIL: " + e)
		quit(1)

	if joystick.get_parent() != hud:
		errors.append("joystick parent should be HUD root, got %s" % joystick.get_parent().name)
	if touch_look.get_parent() != hud:
		errors.append("touch_look parent should be HUD root")
	if joystick.get_parent() != touch_look.get_parent():
		errors.append("joystick and touch_look must be siblings (same parent) for z-order")

	var children := hud.get_children()
	var joy_idx := -1
	var look_idx := -1
	for i in range(children.size()):
		if children[i] == joystick: joy_idx = i
		if children[i] == touch_look: look_idx = i
	if look_idx < 0 or joy_idx < 0:
		errors.append("could not find joystick/touch_look indices")
	elif look_idx > joy_idx:
		errors.append("TouchLook (idx %d) must come BEFORE VirtualJoystick (idx %d) so joystick draws on top" % [look_idx, joy_idx])

	if joystick.size.x < 200.0 or joystick.size.y < 200.0:
		errors.append("joystick control too small: %s (expected >= 200x200)" % joystick.size)
	if touch_look.size.x < 100.0:
		errors.append("touch_look should be full-screen, got %s" % touch_look.size)

	var safe_area := hud.get_node_or_null("SafeArea") as Control
	if safe_area != null and safe_area.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		errors.append("SafeArea should be MOUSE_FILTER_IGNORE so it doesn't block touches, got %d" % safe_area.mouse_filter)

	var joy := joystick as Node
	var look := touch_look as Node

	joy.set("_touch_index", 0)
	joy.call("_update_knob", Vector2(joy.get("size").x * 0.5 + 45.0, joy.get("size").y * 0.5))
	var received: Array[Vector2] = []
	joy.connect("moved", func(v): received.append(v))
	joy.call("_update_knob", Vector2(joy.get("size").x * 0.5 + 45.0, joy.get("size").y * 0.5))
	if received.is_empty() or received[-1].x <= 0.0:
		errors.append("joystick should emit +x on rightward drag, got %s" % (received[-1] if not received.is_empty() else "nothing"))

	look.set("_touch_index", 0)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.relative = Vector2(100.0, 50.0)
	var look_deltas: Array[Vector2] = []
	look.connect("look_delta", func(d): look_deltas.append(d))
	look.call("_gui_input", drag)
	if look_deltas.is_empty() or look_deltas[-1].x <= 0.0:
		errors.append("touch_look should emit +x delta on rightward drag, got %s" % (look_deltas[-1] if not look_deltas.is_empty() else "nothing"))

	if errors.is_empty():
		print("TEST_TOUCH_LAYOUT: PASS (joystick idx=%d, touch_look idx=%d, joy size=%s, look size=%s)" % [joy_idx, look_idx, joystick.size, touch_look.size])
		quit(0)
	else:
		for e in errors: printerr("TEST_TOUCH_LAYOUT FAIL: " + e)
		quit(1)
