extends SceneTree
## Une bête en enclos choisit ses buts dans la clôture et, si elle se coince sur la barrière,
## elle est remise à l'intérieur. Bottes : les pieds restent visibles.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	await process_frame
	var progression := root.get_node("Progression")
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	paused = false
	var player := world.get_node("Player") as CharacterBody3D
	player.add_to_group("player")
	var spawner := world.get_node("Structures")
	spawner.call("disable_saving_for_test")
	world.get_node("Livestock").call("disable_saving_for_test")
	progression.call("clear_for_test", true)
	progression.call("add_xp", 100000)
	for existing in get_nodes_in_group("domestic"):
		existing.remove_from_group("tamed")
		existing.queue_free()
	await process_frame
	var origin: Vector3 = player.global_position + Vector3(14, 0, 14)
	spawner.call("place", "building_pen", origin, 0.0)
	var pen: Node3D = get_nodes_in_group("pens")[0]
	var cow = (load("res://scenes/world/domestic_animal.tscn") as PackedScene).instantiate()
	cow.species = "cow"
	cow.position = origin + Vector3(1, 1, 0)
	world.add_child(cow)
	await process_frame
	cow.tame()
	_check(cow.penned, "vache en enclos")
	var limit: float = float(pen.call("half")) - 1.0
	var inside := true
	for i in 40:
		cow.call("_start_walk")
		var local: Vector3 = pen.to_local(cow.get("_target"))
		inside = inside and absf(local.x) <= limit and absf(local.z) <= limit
	_check(inside, "ses buts de promenade restent dans la clôture")
	# Coincée sur la barrière du fond.
	cow.global_position = pen.to_global(Vector3(1.0, 1.0, -float(pen.call("half"))))
	for i in 240:
		await physics_frame
	var after: Vector3 = pen.to_local(cow.global_position)
	_check(absf(after.z) < float(pen.call("half")) - 0.5 and absf(after.x) < float(pen.call("half")) - 0.5, "remise à l'intérieur (%.1f, %.1f)" % [after.x, after.z])
	_check(cow.penned, "toujours en enclos")

	# Bottes : chaussures gardées sous la tige.
	var hero := Node3D.new()
	hero.set_script(load("res://scripts/player/glb_hero.gd"))
	hero.set("profile", CharacterProfile.default_for("female"))
	root.add_child(hero)
	if bool(hero.call("load_model")):
		hero.call("set_gear", ["gear_hide_boots"])
		var shoes := hero.find_child("Shoes", true, false) as MeshInstance3D
		var boots := hero.find_child("High_Boots", true, false) as MeshInstance3D
		_check(boots != null and boots.visible, "bottes visibles")
		_check(shoes != null and shoes.visible, "pieds visibles sous les bottes")
		var boot_mat := boots.get_surface_override_material(0) as StandardMaterial3D
		_check(boot_mat != null and boot_mat.albedo_color.v < 0.3, "bottes foncées, lisibles sur le sable")
	print("TEST_PEN_FENCE: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
