extends SceneTree
## Props GLB externes : chargement des variantes, maillages valides (au sol, taille
## réelle en mètres), intégration dans le paysage (compteurs identiques) et ruines.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	# Chaque prop déclaré doit se charger intégralement en variantes valides.
	for prop_id in GlbPropLibrary.PROPS:
		var paths: Array = GlbPropLibrary.get_paths(prop_id)
		var meshes: Array = GlbPropLibrary.get_variant_meshes(prop_id)
		if meshes.size() != paths.size():
			errors.append("prop %s : %d/%d variantes chargées" % [prop_id, meshes.size(), paths.size()])
		for mesh in meshes:
			var m := mesh as Mesh
			if m == null or m.get_surface_count() < 1:
				errors.append("prop %s : maillage sans surface" % prop_id)
				continue
			var aabb := m.get_aabb()
			if aabb.size.length() < 0.2:
				errors.append("prop %s : maillage trop petit %s" % [prop_id, str(aabb.size)])
			if aabb.position.y < -0.01:
				errors.append("prop %s : origine sous le sol (y=%f)" % [prop_id, aabb.position.y])
			var total_verts := 0
			for si in range(m.get_surface_count()):
				var verts: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
				if verts != null:
					total_verts += verts.size()
			if total_verts < 20:
				errors.append("prop %s : trop peu de sommets (%d)" % [prop_id, total_verts])

	# Les ruines composées doivent avoir une empreinte de plusieurs mètres.
	var ruin_meshes: Array = GlbPropLibrary.get_variant_meshes("ruin")
	if ruin_meshes.size() >= 1:
		var aabb := (ruin_meshes[0] as Mesh).get_aabb()
		if aabb.size.x < 5.0 or aabb.size.y < 4.0:
			errors.append("ruine trop petite : %s" % str(aabb.size))
	var ruin_scene := GlbPropLibrary.instantiate_scene("ruin")
	if ruin_scene == null or _count_meshes(ruin_scene) < 4:
		errors.append("scène ruine invalide (maillages=%d)" % (0 if ruin_scene == null else _count_meshes(ruin_scene)))

	# Intégration paysage : mêmes compteurs d'instances, mais répartis sur les variantes GLB.
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var landscape := world.get_node("Landscape")
	var expected := 40 + 12 + 150 + 220 + 180 + 400 + 70 + 110 + 160
	if landscape.prop_placements.size() != expected:
		errors.append("placements %d != %d attendu" % [landscape.prop_placements.size(), expected])
	var props := landscape.get_node("Props")
	var group_count := 0
	for c in props.get_children():
		if c is MultiMeshInstance3D:
			group_count += 1
	# 9 groupes procéduraux ; avec les variantes GLB (boulder x10, pine x9, ...) bien plus.
	if group_count <= 9:
		errors.append("les variantes GLB ne semblent pas utilisées (%d groupes MultiMesh)" % group_count)

	# Chaque site a une collision (ruine GLB : boîte par maillage ; repli procédural : cylindres).
	for site in world.get_tree().get_nodes_in_group("sites"):
		if _count_static_bodies(site) < 1:
			errors.append("site sans collision : %s" % site.name)

	if errors.is_empty():
		print("TEST_GLB_PROPS: PASS (%d groupes MultiMesh)" % group_count)
		quit(0)
	else:
		for e in errors:
			printerr("TEST_GLB_PROPS FAIL: ", e)
		quit(1)

func _count_meshes(node: Node) -> int:
	var n := 1 if node is MeshInstance3D else 0
	for c in node.get_children():
		n += _count_meshes(c)
	return n

func _count_static_bodies(node: Node) -> int:
	var n := 1 if node is StaticBody3D else 0
	for c in node.get_children():
		n += _count_static_bodies(c)
	return n
