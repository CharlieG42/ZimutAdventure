extends SceneTree

var joystick_script: GDScript = load("res://scripts/ui/virtual_joystick.gd")
var look_script: GDScript = load("res://scripts/ui/touch_look.gd")
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

		var received: Array[Vector2] = []
		joystick.moved.connect(func(v): received.append(v))

		joystick._touch_index = 0
		joystick._update_knob(joystick._center + Vector2(45.0, 0.0))
		if received.is_empty():
			errors.append("joystick should emit moved on drag")
		else:
			var v := received[-1]
			if v.x <= 0.0 or v.y != 0.0:
				errors.append("joystick right-drag should give +x, got %s" % v)
			if abs(v.x - 0.5) > 0.001:
				errors.append("45px of 90px reach should give 0.5, got %.3f" % v.x)

		joystick._release()
		if received.is_empty() or received[-1] != Vector2.ZERO:
			errors.append("joystick release should emit zero vector")
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

		player.apply_touch_look(Vector2(0.5, 0.0))
		if abs(player.rotation.y) < 0.001:
			errors.append("apply_touch_look should rotate the player")

		player.free()

	var hud_scene := load("res://scenes/ui/hud.tscn") as PackedScene
	if hud_scene == null:
		errors.append("hud.tscn missing")
	else:
		var hud := hud_scene.instantiate()
		root.add_child(hud)
		await process_frame
		if hud == null:
			errors.append("hud.tscn should instantiate")
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
