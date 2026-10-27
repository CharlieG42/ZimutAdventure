extends SceneTree

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var packed := load("res://scenes/world/canyon_playground.tscn") as PackedScene
	if packed == null:
		printerr("TEST_SCENE FAIL: cannot load canyon_playground.tscn")
		quit(1)
	var scene := packed.instantiate()
	if scene == null:
		printerr("TEST_SCENE FAIL: cannot instantiate")
		quit(1)
	root.add_child(scene)
	for i in range(10):
		await process_frame

	var player := scene.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		errors.append("Player node missing")
	else:
		print("player position: ", player.global_position)
		var cam := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
		if cam == null:
			errors.append("Player camera missing")

	var landscape := scene.get_node_or_null("Landscape") as Node3D
	if landscape == null:
		errors.append("Landscape node missing")
	else:
		var props := landscape.get_node_or_null("Props")
		if props == null:
			errors.append("Props missing")
		else:
			print("props children: ", props.get_child_count())

	var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		errors.append("Sun missing")

	var env := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env == null or env.environment == null:
		errors.append("WorldEnvironment missing")

	var exit_code := 0
	if errors.is_empty():
		print("TEST_SCENE: PASS")
	else:
		exit_code = 1
		for e in errors:
			printerr("TEST_SCENE FAIL: " + e)
	quit(exit_code)
