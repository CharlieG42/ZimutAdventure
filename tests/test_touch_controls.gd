extends SceneTree

var interaction_manager_script: GDScript = load("res://scripts/autoload/interaction_manager.gd")

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	var im := interaction_manager_script.new() as Node
	root.add_child(im)
	await process_frame

	var joystick_scene := load("res://scenes/ui/virtual_joystick.tscn") as PackedScene
	if joystick_scene == null:
		errors.append("virtual_joystick.tscn missing")
	else:
		var joystick := joystick_scene.instantiate() as Control
		root.add_child(joystick)
		await process_frame

		var base := joystick.get_node_or_null("Base") as Control
		var knob := joystick.get_node_or_null("Knob") as Control
		if base == null or knob == null:
			errors.append("joystick must have Base and Knob children")
		elif not base.visible:
			errors.append("joystick base should be always visible (always_visible=true)")
		if joystick.visible == false:
			errors.append("joystick control should be visible on every platform (always-on joysticks)")
		if base != null:
			var tex := base.get("texture") as Texture2D
			if tex == null:
				errors.append("joystick base must have a texture")
			elif tex is PlaceholderTexture2D:
				errors.append("joystick base texture must be a real image, not a PlaceholderTexture2D (renders as nothing in exported APK)")
			var ktex := (knob as Control).get("texture") as Texture2D
			if ktex == null:
				errors.append("joystick knob must have a texture")
			elif ktex is PlaceholderTexture2D:
				errors.append("joystick knob texture must be a real image, not a PlaceholderTexture2D")

		var received: Array[Vector2] = []
		joystick.moved.connect(func(v): received.append(v))

		joystick.set("_touch_index", 0)
		joystick.call("_update_knob", joystick.get("size") * 0.5 + Vector2(45.0, 0.0))
		if received.is_empty():
			errors.append("joystick should emit moved on drag")
		else:
			var v := received[-1]
			if v.x <= 0.0 or v.y != 0.0:
				errors.append("joystick right-drag should give +x, got %s" % v)
			var expected := 45.0 / 80.0
			if abs(v.x - expected) > 0.001:
				errors.append("45px of 80px reach should give %.3f, got %.3f" % [expected, v.x])

		joystick.call("_update_knob", joystick.get("size") * 0.5 + Vector2(400.0, 0.0))
		if received.is_empty() or received[-1].length() > 1.001:
			errors.append("joystick vector should be clamped to 1, got %s" % (received[-1] if not received.is_empty() else "nothing"))

		joystick._release()
		if received.is_empty() or received[-1] != Vector2.ZERO:
			errors.append("joystick release should emit zero vector")
		if knob != null and knob.position != joystick.get("size") * 0.5 - knob.get("size") * 0.5:
			errors.append("knob should return to center on release")
		if base != null and not base.visible:
			errors.append("base should stay visible after release")
		joystick.free()

	var look_scene := load("res://scenes/ui/touch_look.tscn") as PackedScene
	if look_scene == null:
		errors.append("touch_look.tscn missing")
	else:
		var look := look_scene.instantiate() as Control
		root.add_child(look)
		await process_frame
		var look_deltas: Array[Vector2] = []
		look.look_delta.connect(func(d): look_deltas.append(d))
		look._touch_index = 0
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.relative = Vector2(100.0, 0.0)
		look._gui_input(drag)
		if look_deltas.is_empty():
			errors.append("touch look should emit look_delta on drag while touching")
		elif look_deltas[-1].x <= 0.0:
			errors.append("look delta should scale the drag relative, got %s" % look_deltas[-1])
		look.free()

	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	if player_scene == null:
		errors.append("player.tscn missing")
	else:
		var player := player_scene.instantiate() as CharacterBody3D
		root.add_child(player)
		await process_frame
		player.set_joystick_vector(Vector2(2.0, 0.0))
		if player._joystick_vector.length() > 1.0:
			errors.append("joystick vector should be clamped to 1, got %f" % player._joystick_vector.length())

		var yaw_before := player.rotation.y
		player.apply_touch_look(Vector2(0.5, 0.0))
		if abs(player.rotation.y - yaw_before) < 0.001:
			errors.append("apply_touch_look should rotate the player")

		var yaw_before_cam := player.rotation.y
		player.call("apply_camera_joystick", Vector2(1.0, 0.0), 0.1)
		if abs(player.rotation.y - yaw_before_cam) < 0.001:
			errors.append("apply_camera_joystick should rotate the player")

		player.free()

	var hud_scene := load("res://scenes/ui/hud.tscn") as PackedScene
	if hud_scene == null:
		errors.append("hud.tscn missing")
	else:
		var hud := hud_scene.instantiate()
		root.add_child(hud)
		await process_frame
		if hud.get_node_or_null("VirtualJoystick") == null:
			errors.append("HUD missing move VirtualJoystick")
		if hud.get_node_or_null("CameraJoystick") == null:
			errors.append("HUD missing camera CameraJoystick")
		if hud.get_node_or_null("TouchLook") == null:
			errors.append("HUD missing TouchLook")
		if hud.get_node_or_null("SafeArea/VBox/BottomBar/ViewButton") == null:
			errors.append("HUD missing ViewButton")
		var base_child := hud.get_node_or_null("VirtualJoystick/Base") as Control
		var knob_child := hud.get_node_or_null("VirtualJoystick/Knob") as Control
		if base_child != null and base_child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			errors.append("joystick Base must ignore mouse (mouse_filter=2) so touches reach the joystick parent, got %d" % base_child.mouse_filter)
		if knob_child != null and knob_child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			errors.append("joystick Knob must ignore mouse (mouse_filter=2) so touches reach the joystick parent, got %d" % knob_child.mouse_filter)
		hud.free()

	im.free()

	var exit_code := 0
	if errors.is_empty():
		print("TEST_TOUCH: PASS")
	else:
		exit_code = 1
		for e in errors:
			printerr("TEST_TOUCH FAIL: " + e)
	quit(exit_code)
