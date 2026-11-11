extends SceneTree
## Performance : décor découpé en blocs à portée limitée, modèles d'animaux fusionnés,
## portées d'affichage du décor interactif.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	await process_frame
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 12:
		await process_frame
	var landscape := world.get_node("Landscape")
	var props := landscape.get_node("Props")
	var total := 0
	var ranged := 0
	var unlimited := 0
	var widest := 0.0
	for child in props.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null:
			continue
		total += mmi.multimesh.instance_count
		if mmi.visibility_range_end > 0.0:
			ranged += 1
		else:
			unlimited += 1
		var box := mmi.multimesh.get_aabb()
		widest = maxf(widest, maxf(box.size.x, box.size.z))
	_check(total == landscape.prop_placements.size(), "aucune instance perdue au découpage (%d)" % total)
	_check(ranged > 100, "blocs à portée limitée (%d)" % ranged)
	_check(unlimited > 0, "grands reliefs toujours visibles (%d blocs)" % unlimited)
	_check(widest < 64.0 + 40.0, "un bloc reste local (%.0f m)" % widest)

	# Animaux : maillages fusionnés par pivot.
	var animal: Node3D = null
	for a in world.get_tree().get_nodes_in_group("domestic"):
		animal = a
		break
	_check(animal != null, "un animal domestique présent")
	if animal != null:
		var meshes := animal.find_children("*", "MeshInstance3D", true, false).size()
		_check(meshes <= 16, "animal fusionné : %d maillages (≈30 avant)" % meshes)
		_check(animal.find_child("Baked", true, false) != null, "maillage fusionné présent")

	# Baies : un seul maillage par buisson.
	var bush: Node = null
	for b in world.get_tree().get_nodes_in_group("berries"):
		bush = b
		break
	if bush != null:
		_check(bush.get_node("Berries").get_child_count() == 1, "baies fondues en un maillage")

	# Portées du décor interactif.
	var culler := world.get_node("DistanceCuller")
	culler.call("apply")
	var sample := world.get_node("Livestock").find_children("*", "GeometryInstance3D", true, false)
	_check(not sample.is_empty() and (sample[0] as GeometryInstance3D).visibility_range_end > 0.0, "bétail masqué au loin")
	_check(int(culler.call("apply")) == 0, "portées appliquées une seule fois")

	# Fusion : couleurs et sommets conservés.
	var a := MeshInstance3D.new()
	a.mesh = BoxMesh.new()
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	a.material_override = red
	var b := MeshInstance3D.new()
	b.mesh = BoxMesh.new()
	b.position = Vector3(3, 0, 0)
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color.BLUE
	b.material_override = blue
	var baker = load("res://scripts/world/mesh_baker.gd")
	var merged: ArrayMesh = baker.merge([a, b])
	var arrays := merged.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_check(colors.has(Color.RED) and colors.has(Color.BLUE), "couleurs portées par les sommets")
	_check(merged.get_aabb().size.x > 3.5, "transformations appliquées (largeur %.1f)" % merged.get_aabb().size.x)
	a.free()
	b.free()

	world.queue_free()
	await process_frame
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
