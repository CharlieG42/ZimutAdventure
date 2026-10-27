extends SceneTree

var rock_gen_script: GDScript = load("res://scripts/world/rock_generator.gd")
var veg_gen_script: GDScript = load("res://scripts/world/vegetation_generator.gd")

func _init() -> void:
	var landscape_script: GDScript = load("res://scripts/world/landscape_manager.gd")
	var landscape: Node3D = landscape_script.new() as Node3D
	root.add_child(landscape)
	await create_timer(0.5).timeout

	var errors: Array[String] = []

	if landscape.get_child_count() < 2:
		errors.append("Landscape should have terrain + props children, got %d" % landscape.get_child_count())

	var terrain := landscape.get_node_or_null("Terrain") as MeshInstance3D
	if terrain == null:
		errors.append("Terrain node missing")
	else:
		var mesh := terrain.mesh as ArrayMesh
		if mesh == null or mesh.get_surface_count() == 0:
			errors.append("Terrain mesh invalid")
		else:
			var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			if verts.size() == 0:
				errors.append("Terrain has no vertices")
			else:
				var min_y := INF
				var max_y := -INF
				for v in verts:
					min_y = min(min_y, v.y)
					max_y = max(max_y, v.y)
				print("Terrain vertices: %d, height range: %.2f .. %.2f" % [verts.size(), min_y, max_y])

	var props := landscape.get_node_or_null("Props") as Node3D
	if props == null:
		errors.append("Props node missing")
	else:
		var total_instances := 0
		for child in props.get_children():
			var mmi := child as MultiMeshInstance3D
			if mmi == null or mmi.multimesh == null:
				errors.append("Invalid MultiMeshInstance3D in Props")
				continue
			total_instances += mmi.multimesh.instance_count
			print("Prop group: %d instances, mesh surfaces: %d" % [mmi.multimesh.instance_count, (mmi.multimesh.mesh as ArrayMesh).get_surface_count()])
		print("Total prop instances: %d" % total_instances)
		var expected: int = landscape.hoodoo_count + landscape.butte_count + landscape.boulder_count + landscape.pine_count + landscape.shrub_count + landscape.grass_count
		if total_instances != expected:
			errors.append("Expected %d prop instances, got %d" % [expected, total_instances])

	var h: float = landscape.terrain_height_at(0.0, 0.0)
	print("terrain_height_at(0,0) = %.2f" % h)
	if h < -90.0:
		errors.append("terrain_height_at returned out-of-bounds sentinel inside terrain")

	var rock_mesh: ArrayMesh = rock_gen_script.generate(rock_gen_script.RockType.HOODOO, RandomNumberGenerator.new())
	if rock_mesh.get_surface_count() == 0:
		errors.append("RockGenerator produced empty mesh")
	var pine_mesh: ArrayMesh = veg_gen_script.generate(veg_gen_script.PlantType.PINE, RandomNumberGenerator.new())
	if pine_mesh.get_surface_count() < 2:
		errors.append("Pine should have trunk + foliage surfaces")

	var exit_code := 0
	if errors.is_empty():
		print("TEST_LANDSCAPE: PASS")
	else:
		exit_code = 1
		for e in errors:
			printerr("TEST_LANDSCAPE FAIL: " + e)
	quit(exit_code)
