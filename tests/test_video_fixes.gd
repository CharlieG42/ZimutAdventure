extends SceneTree
## Corrections issues d'une vidéo de test : l'enclos se déplace avec ses bêtes,
## les animaux n'entrent pas dans l'abri, le cavalier est assis derrière le garrot.

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
	var scene := load("res://scenes/world/domestic_animal.tscn") as PackedScene

	# --- Enclos déplaçable, bêtes comprises --------------------------------------------------
	var origin: Vector3 = player.global_position + Vector3(14, 0, 14)
	_check(spawner.call("place", "building_pen", origin, 0.0) == "", "enclos posé")
	var pen: Node3D = get_nodes_in_group("pens")[0]
	_check(spawner.call("movable_for", pen) == pen, "l'enclos est déplaçable")
	var cow = scene.instantiate()
	cow.species = "cow"
	cow.position = origin + Vector3(1, 1, 0)
	world.add_child(cow)
	await process_frame
	cow.tame()
	_check(cow.penned, "la vache est en enclos")
	var local_before: Vector3 = pen.to_local(cow.global_position)
	_check(spawner.call("begin_move", pen), "enclos soulevé")
	var target := origin + Vector3(30, 0, 5)
	spawner.call("update_move", target, player.global_position)
	var err: String = spawner.call("confirm_move")
	_check(err == "", "enclos reposé (%s)" % err)
	await physics_frame
	_check(Vector2(pen.global_position.x - target.x, pen.global_position.z - target.z).length() < 1.0, "enclos au nouvel endroit")
	_check(cow.global_position.distance_to(pen.to_global(local_before)) < 1.0, "la vache a suivi l'enclos")
	_check(pen.call("get_occupants").has(cow), "la vache est toujours dans l'enclos")

	# --- Abri interdit aux animaux ----------------------------------------------------------------
	var spot := player.global_position + Vector3(-14, 0, -14)
	_check(spawner.call("place", "building_shelter", spot, 0.0) == "", "abri posé")
	var shelter: Node3D = null
	for node in get_nodes_in_group("structures"):
		if node.get("kind") == "shelter":
			shelter = node
	_check(shelter.find_child("AnimalBlock", true, false) != null, "volume interdit aux animaux présent")
	var horse = scene.instantiate()
	horse.species = "horse"
	horse.position = shelter.to_global(Vector3(0, 0.6, 4.5))
	world.add_child(horse)
	await process_frame
	horse.tame()
	horse.set("_center", shelter.to_global(Vector3(0, 0, 0.5)))
	for i in 420:
		horse.set("_target", shelter.to_global(Vector3(0, 0, 0.0)))
		horse.set("_mode_left", 5.0)
		await physics_frame
	_check(not shelter.call("contains_point", horse.global_position), "le cheval n'est pas entré dans l'abri")
	# Le joueur, lui, passe par la porte.
	_check(shelter.find_child("AnimalBlock", true, false).get("collision_layer") == 128, "bloc sur la couche des animaux uniquement")
	_check(player.collision_mask & 128 == 0, "le joueur ignore ce bloc")

	# --- Descente de cheval : jamais à l'intérieur d'un abri ------------------------------------------
	horse.global_position = shelter.to_global(Vector3(2.3, 0.6, 3.0))
	player.global_position = shelter.to_global(Vector3(1.6, 0.0, 1.0))
	horse.mount(player)
	horse.dismount(player)
	_check(not shelter.call("contains_point", horse.global_position), "le cheval descendu est hors de l'abri")

	print("TEST_VIDEO_FIXES: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
