extends SceneTree
## Décor : posé sur le sol (pas de flottement), faces tournées vers l'extérieur,
## et collision à la même position que le visuel.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var RockGenerator_: GDScript = load("res://scripts/world/rock_generator.gd")

	# Faces avant : chaque triangle doit regarder du côté de sa normale.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for type in [0, 1, 2]:
		var mesh: ArrayMesh = RockGenerator_.generate(type, rng)
		var arr := mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var bad := 0
		for i in range(0, idx.size(), 3):
			var f := (v[idx[i + 1]] - v[idx[i]]).cross(v[idx[i + 2]] - v[idx[i]])
			var nn := n[idx[i]] + n[idx[i + 1]] + n[idx[i + 2]]
			# Les facettes quasi parallèles à la vue (écailles aux pôles) sont ignorées.
			if f.length() > 0.02 and f.normalized().dot(nn.normalized()) > 0.05:
				bad += 1
		if bad > 0:
			errors.append("rocher type %d : %d triangles à l'envers" % [type, bad])
		# Le boulder doit être un volume fermé (pôle supérieur au-dessus de l'inférieur).
		if type == 2 and mesh.get_aabb().position.y > -0.3:
			errors.append("le boulder doit descendre sous son origine")

	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var landscape := world.get_node("Landscape")
	var checked := 0
	for t in landscape.prop_placements:
		var ground: float = landscape.terrain_height_at(t.origin.x, t.origin.z)
		checked += 1
		if absf(t.origin.y - ground) > 0.01:
			errors.append("décor flottant/enterré : y=%f sol=%f" % [t.origin.y, ground])
			break
	if checked < 900:
		errors.append("trop peu d'instances vérifiées (%d)" % checked)


	# Collision : un joueur qui marche vers un rocher ne le traverse pas.
	var player := world.get_node("Player") as CharacterBody3D
	for which in [0, 40 + 12]:  # un hoodoo, un boulder
		var t: Transform3D = landscape.prop_placements[which]
		var target := t.origin
		var from := target + Vector3(14.0, 0.0, 0.0)
		from.y = landscape.terrain_height_at(from.x, from.z) + 1.5
		player.global_position = from
		player.velocity = Vector3.ZERO
		var d := target - from
		player.rotation.y = atan2(-d.x, -d.z)
		player.set_joystick_vector(Vector2(0, -1))
		var nearest := 999.0
		for i in 150:
			await physics_frame
			nearest = minf(nearest, Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length())
		player.set_joystick_vector(Vector2.ZERO)
		if nearest < 0.5:
			errors.append("le joueur a traversé le décor #%d (distance min %f)" % [which, nearest])

	var col := landscape.get_node_or_null("PropCollision")
	if col == null or col.get_child_count() < 300:
		errors.append("collisions du décor manquantes")

	if errors.is_empty():
		print("TEST_PROPS_PLACEMENT: PASS (%d instances)" % checked)
		quit(0)
	else:
		for e in errors:
			printerr("TEST_PROPS_PLACEMENT FAIL: ", e)
		quit(1)
