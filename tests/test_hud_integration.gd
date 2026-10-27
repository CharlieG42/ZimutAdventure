extends SceneTree

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	var packed := load("res://scenes/world/canyon_playground.tscn") as PackedScene
	if packed == null:
		printerr("TEST_HUD_INTEGRATION FAIL: canyon_playground.tscn missing")
		quit(1)
	var scene := packed.instantiate()
	root.add_child(scene)
	for i in range(10):
		await process_frame

	var hud := scene.get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		errors.append("HUD missing in canyon_playground")
		for e in errors: printerr("TEST_HUD_INTEGRATION FAIL: " + e)
		quit(1)

	var player := scene.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		errors.append("Player missing in canyon_playground")
		for e in errors: printerr("TEST_HUD_INTEGRATION FAIL: " + e)
		quit(1)

	var move_joy := hud.get_node_or_null("VirtualJoystick") as Control
	var cam_joy := hud.get_node_or_null("CameraJoystick") as Control
	var touch_look := hud.get_node_or_null("TouchLook") as Control
	var view_button := hud.get_node_or_null("SafeArea/VBox/BottomBar/ViewButton") as Button
	if move_joy == null or cam_joy == null or touch_look == null or view_button == null:
		errors.append("HUD missing touch controls (move_joy=%s cam_joy=%s touch_look=%s view_button=%s)" % [move_joy != null, cam_joy != null, touch_look != null, view_button != null])
	else:
		if move_joy.global_position.x > 640.0:
			errors.append("move joystick should be on the left half, x=%f" % move_joy.global_position.x)
		if cam_joy.global_position.x < 640.0:
			errors.append("camera joystick should be on the right half, x=%f" % cam_joy.global_position.x)

		var children: Array = hud.get_children()
		var look_idx: int = children.find(touch_look)
		var joy_idx: int = children.find(move_joy)
		var cam_idx: int = children.find(cam_joy)
		if look_idx > joy_idx or look_idx > cam_idx:
			errors.append("TouchLook (idx %d) must be drawn below joysticks (idx %d, %d)" % [look_idx, joy_idx, cam_idx])

		move_joy.call("_update_knob", move_joy.get("size") * 0.5 + Vector2(40.0, 0.0))
		if player._joystick_vector.x <= 0.0:
			errors.append("move joystick drag should reach player.set_joystick_vector, got %s" % player._joystick_vector)
		move_joy.call("_release")

		var yaw_before: float = player.rotation.y
		var pitch_before: float = player.get("_pitch")
		cam_joy.call("_update_knob", cam_joy.get("size") * 0.5 + Vector2(0.0, -40.0))
		await process_frame
		await process_frame
		var pitch_after: float = player.get("_pitch")
		if abs(player.rotation.y - yaw_before) < 0.0001 and abs(pitch_after - pitch_before) < 0.0001:
			errors.append("camera joystick drag should rotate the camera via player.apply_camera_joystick")
		cam_joy.call("_release")

		if player.call("is_first_person") != true:
			errors.append("player should start in first person")
		view_button.emit_signal("pressed")
		if player.call("is_first_person") != false:
			errors.append("ViewButton should toggle player to third person")
		var visuals := player.get_node_or_null("Visuals") as Node3D
		if visuals == null or not visuals.visible:
			errors.append("character visuals should be visible in third person")
		if view_button.text != tr("VIEW_THIRD_PERSON"):
			errors.append("ViewButton text should show third person label, got '%s'" % view_button.text)
		view_button.emit_signal("pressed")
		if player.call("is_first_person") != true:
			errors.append("ViewButton should toggle back to first person")
		if visuals != null and visuals.visible:
			errors.append("character visuals should be hidden in first person")

	if errors.is_empty():
		print("TEST_HUD_INTEGRATION: PASS")
		quit(0)
	else:
		for e in errors: printerr("TEST_HUD_INTEGRATION FAIL: " + e)
		quit(1)
