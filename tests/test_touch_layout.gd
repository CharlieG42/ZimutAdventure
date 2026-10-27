extends SceneTree

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
	var camera_joystick := hud.get_node_or_null("CameraJoystick") as Control
	var touch_look := hud.get_node_or_null("TouchLook") as Control
	if joystick == null:
		errors.append("VirtualJoystick missing at HUD root")
	if camera_joystick == null:
		errors.append("CameraJoystick missing at HUD root")
	if touch_look == null:
		errors.append("TouchLook missing at HUD root")
	if joystick == null or camera_joystick == null or touch_look == null:
		for e in errors: printerr("TEST_TOUCH_LAYOUT FAIL: " + e)
		quit(1)

	for joy in [joystick, camera_joystick]:
		if joy.get_parent() != hud:
			errors.append("%s parent should be HUD root, got %s" % [joy.name, joy.get_parent().name])
	if touch_look.get_parent() != hud:
		errors.append("touch_look parent should be HUD root")

	var children := hud.get_children()
	var joy_idx := -1
	var cam_idx := -1
	var look_idx := -1
	for i in range(children.size()):
		if children[i] == joystick: joy_idx = i
		if children[i] == camera_joystick: cam_idx = i
		if children[i] == touch_look: look_idx = i
	if look_idx < 0 or joy_idx < 0 or cam_idx < 0:
		errors.append("could not find joystick/camera_joystick/touch_look indices")
	elif look_idx > joy_idx or look_idx > cam_idx:
		errors.append("TouchLook (idx %d) must come BEFORE both joysticks (idx %d, %d)" % [look_idx, joy_idx, cam_idx])

	for joy in [joystick, camera_joystick]:
		if joy.size.x < 200.0 or joy.size.y < 200.0:
			errors.append("%s too small: %s (expected >= 200x200)" % [joy.name, joy.size])
		if joy.mouse_filter != Control.MOUSE_FILTER_STOP:
			errors.append("%s mouse_filter should be STOP, got %d" % [joy.name, joy.mouse_filter])
	if touch_look.size.x < 100.0:
		errors.append("touch_look should be full-screen, got %s" % touch_look.size)

	var joy_pos := joystick.global_position
	var joy_end := joy_pos + joystick.size
	if joy_pos.x > 400.0 or joy_end.y < 300.0:
		errors.append("move joystick should be anchored bottom-left, got rect %s..%s" % [joy_pos, joy_end])

	var cam_pos := camera_joystick.global_position
	var cam_end := cam_pos + camera_joystick.size
	if cam_pos.x < touch_look.size.x - 400.0 or cam_end.y < 300.0:
		errors.append("camera joystick should be anchored bottom-right, got rect %s..%s (screen %s)" % [cam_pos, cam_end, touch_look.size])

	var safe_area := hud.get_node_or_null("SafeArea") as Control
	if safe_area != null and safe_area.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		errors.append("SafeArea should be MOUSE_FILTER_IGNORE so it doesn't block touches, got %d" % safe_area.mouse_filter)

	var joy := joystick as Node
	var look := touch_look as Node

	joy.set("_touch_index", 0)
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

	var cam_joy := camera_joystick as Node
	var cam_received: Array[Vector2] = []
	cam_joy.connect("moved", func(v): cam_received.append(v))
	cam_joy.call("_update_knob", Vector2(cam_joy.get("size").x * 0.5 - 45.0, cam_joy.get("size").y * 0.5))
	if cam_received.is_empty() or cam_received[-1].x >= 0.0:
		errors.append("camera joystick should emit -x on leftward drag, got %s" % (cam_received[-1] if not cam_received.is_empty() else "nothing"))

	if errors.is_empty():
		print("TEST_TOUCH_LAYOUT: PASS (look idx=%d, move joy idx=%d, cam joy idx=%d, sizes %s/%s)" % [look_idx, joy_idx, cam_idx, joystick.size, camera_joystick.size])
		quit(0)
	else:
		for e in errors: printerr("TEST_TOUCH_LAYOUT FAIL: " + e)
		quit(1)
