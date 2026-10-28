extends SceneTree

var interaction_manager_script: GDScript = load("res://scripts/autoload/interaction_manager.gd")

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	var im := interaction_manager_script.new() as Node
	root.add_child(im)
	await process_frame

	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	if player_scene == null:
		printerr("TEST_VIEW_MODES FAIL: player.tscn missing")
		quit(1)
	var player := player_scene.instantiate() as CharacterBody3D
	root.add_child(player)
	await process_frame

	var visuals := player.get_node_or_null("Visuals") as Node3D
	if visuals == null:
		errors.append("player should have a Visuals node for the drawn character")
	else:
		for part in ["LegL", "LegR", "Torso", "Head", "Torso/Backpack", "Torso/ArmL", "Torso/ArmR"]:
			var mesh := visuals.get_node_or_null(part) as MeshInstance3D
			if mesh == null:
				errors.append("character visuals missing %s" % part)
			elif mesh.mesh == null:
				errors.append("character %s should have a mesh" % part)
		if visuals.get_node_or_null("Head/HatBrim") == null or visuals.get_node_or_null("Head/HatTop") == null:
			errors.append("character should have a hat (HatBrim + HatTop)")
		if visuals.visible:
			errors.append("character visuals should be hidden in first person")

	var camera := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if camera == null:
		errors.append("player camera missing")
	else:
		if camera.position != Vector3.ZERO:
			errors.append("first person camera should be at pivot origin, got %s" % camera.position)

	if player.call("is_first_person") != true:
		errors.append("player should start in first person")

	var view_events: Array[bool] = []
	player.connect("view_changed", func(is_fp): view_events.append(is_fp))

	player.call("toggle_view")
	if player.call("is_first_person") != false:
		errors.append("toggle_view should switch to third person")
	if visuals != null and not visuals.visible:
		errors.append("character visuals should be visible in third person")
	if camera != null and camera.position.z < 1.0:
		errors.append("third person camera should be behind the player, got z=%f" % camera.position.z)

	var yaw_before := player.rotation.y
	player.call("apply_camera_joystick", Vector2(1.0, 0.0), 0.1)
	if abs(player.rotation.y - yaw_before) < 0.001:
		errors.append("camera look should rotate the player so the camera follows behind")

	player.call("toggle_view")
	if player.call("is_first_person") != true:
		errors.append("toggle_view again should switch back to first person")
	if visuals != null and visuals.visible:
		errors.append("character visuals should be hidden again in first person")
	if camera != null and camera.position != Vector3.ZERO:
		errors.append("first person camera should return to pivot origin, got %s" % camera.position)

	if view_events.size() != 2 or view_events[0] != false or view_events[1] != true:
		errors.append("view_changed signal should emit [false, true], got %s" % view_events)

	player.free()
	im.free()

	var exit_code := 0
	if errors.is_empty():
		print("TEST_VIEW_MODES: PASS")
	else:
		exit_code = 1
		for e in errors:
			printerr("TEST_VIEW_MODES FAIL: " + e)
	quit(exit_code)
