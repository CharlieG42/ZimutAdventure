extends SceneTree

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	for path in [
		"res://assets/landscapes/shaders/prop_rock.gdshader",
		"res://assets/landscapes/shaders/prop_foliage.gdshader",
		"res://assets/landscapes/shaders/prop_trunk.gdshader",
	]:
		var shader := load(path) as Shader
		if shader == null:
			errors.append("shader missing: " + path)
		elif shader.code.is_empty():
			errors.append("shader empty: " + path)

	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	var rock_mesh := RockGenerator.generate(RockGenerator.RockType.HOODOO, rng)
	var rock_mat := rock_mesh.surface_get_material(0)
	if not rock_mat is ShaderMaterial:
		errors.append("rock material should be ShaderMaterial, got %s" % rock_mat.get_class())
	else:
		var sm := rock_mat as ShaderMaterial
		if sm.shader == null:
			errors.append("rock material shader is null")
		if sm.get_shader_parameter("albedo") == null:
			errors.append("rock material missing albedo parameter")

	var boulder := RockGenerator.generate(RockGenerator.RockType.BOULDER, rng)
	if not boulder.surface_get_material(0) is ShaderMaterial:
		errors.append("boulder material should be ShaderMaterial")

	var butte := RockGenerator.generate(RockGenerator.RockType.BUTTE, rng)
	if not butte.surface_get_material(0) is ShaderMaterial:
		errors.append("butte material should be ShaderMaterial")

	var pine := VegetationGenerator.generate(VegetationGenerator.PlantType.PINE, rng)
	if pine.get_surface_count() < 2:
		errors.append("pine should have trunk + foliage surfaces")
	else:
		var trunk_mat := pine.surface_get_material(0)
		var fol_mat := pine.surface_get_material(1)
		if not trunk_mat is ShaderMaterial:
			errors.append("pine trunk should be ShaderMaterial")
		elif (trunk_mat as ShaderMaterial).shader == null:
			errors.append("pine trunk shader is null")
		if not fol_mat is ShaderMaterial:
			errors.append("pine foliage should be ShaderMaterial")
		elif (fol_mat as ShaderMaterial).shader == null:
			errors.append("pine foliage shader is null")

	var shrub := VegetationGenerator.generate(VegetationGenerator.PlantType.SHRUB, rng)
	if not shrub.surface_get_material(0) is ShaderMaterial:
		errors.append("shrub material should be ShaderMaterial")

	var grass := VegetationGenerator.generate(VegetationGenerator.PlantType.DRY_GRASS, rng)
	if not grass.surface_get_material(0) is ShaderMaterial:
		errors.append("grass material should be ShaderMaterial")

	var packed := load("res://scenes/world/canyon_playground.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	for i in range(5):
		await process_frame

	var env_node := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node == null or env_node.environment == null:
		errors.append("WorldEnvironment missing")
	else:
		var env := env_node.environment
		if not env.fog_enabled:
			errors.append("environment fog should be enabled for atmosphere")
		if not env.ssao_enabled:
			errors.append("environment SSAO should be enabled for richer shading")
		if env.fog_density <= 0.0:
			errors.append("fog density should be positive")
		if not env.glow_enabled:
			errors.append("environment glow should be enabled")
		if not env.adjustment_enabled:
			errors.append("color adjustment should be enabled for a richer look")

	# Le feuillage et le tronc doivent avoir un balancement au vent.
	var foliage_shader := load("res://assets/landscapes/shaders/prop_foliage.gdshader") as Shader
	if foliage_shader != null and not foliage_shader.code.contains("wind_strength"):
		errors.append("foliage shader should support wind sway (wind_strength)")
	var trunk_shader := load("res://assets/landscapes/shaders/prop_trunk.gdshader") as Shader
	if trunk_shader != null and not trunk_shader.code.contains("wind_strength"):
		errors.append("trunk shader should support wind sway (wind_strength)")
	# Le terrain doit avoir des strates par hauteur et des replats poussiéreux.
	var terrain_shader := load("res://assets/landscapes/shaders/canyon_terrain.gdshader") as Shader
	if terrain_shader != null:
		if not terrain_shader.code.contains("(v_height + warp) * strata_scale"):
			errors.append("terrain shader should use world-height strata")
		if not terrain_shader.code.contains("ledge_dust"):
			errors.append("terrain shader should have ledge dust on flat areas")

	var player := scene.get_node_or_null("Player") as CharacterBody3D
	if player != null:
		var visuals := player.get_node_or_null("Visuals") as Node3D
		if visuals == null:
			errors.append("player Visuals missing")
		else:
			for part in ["LegL", "LegR", "Torso", "Torso/ArmL", "Torso/ArmR", "Torso/Backpack", "Head"]:
				var mesh := visuals.get_node_or_null(part) as MeshInstance3D
				if mesh == null:
					errors.append("character missing part: " + part)
				elif mesh.mesh == null:
					errors.append("character part has no mesh: " + part)
			if visuals.get_node_or_null("Head/HatTop/HatBand") == null:
				errors.append("character hat should have a band (HatTop/HatBand)")
	scene.free()

	if errors.is_empty():
		print("TEST_VISUAL_UPGRADE: PASS")
		quit(0)
	else:
		for e in errors: printerr("TEST_VISUAL_UPGRADE FAIL: " + e)
		quit(1)
