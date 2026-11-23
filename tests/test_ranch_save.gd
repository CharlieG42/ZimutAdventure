extends SceneTree
## Nécessite un affichage (la sauvegarde est coupée en mode headless) : lancé sous xvfb.
## Sauvegarde du ranch : niveau de l'enclos, bêtes en enclos, niveau de l'abri, succès d'élevage.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _world() -> Node:
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	paused = false
	return world

func _initialize() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		print("TEST_RANCH_SAVE: SKIP (headless : sauvegarde désactivée)")
		quit(0)
		return
	SaveSlots.active_slot = 3
	var dir := SaveSlots.slot_dir(3)
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	var inventory := root.get_node("Inventory")
	var progression := root.get_node("Progression")
	progression.call("clear_for_test", true)
	progression.call("add_xp", 100000)
	inventory.call("clear_for_test")
	var world = await _world()
	var player := world.get_node("Player") as CharacterBody3D
	player.add_to_group("player")
	var spawner := world.get_node("Structures")
	var origin: Vector3 = player.global_position + Vector3(14, 0, 14)
	spawner.call("place", "building_pen", origin, 0.0)
	spawner.call("place", "building_shelter", player.global_position + Vector3(-14, 0, -14), 0.0)
	inventory.call("add_item", "item_wood", 40)
	inventory.call("add_item", "item_stone", 10)
	inventory.call("add_item", "item_pelt", 4)
	var pen: Node3D = get_nodes_in_group("pens")[0]
	pen.call("upgrade")
	var shelter: Node3D = null
	for node in get_nodes_in_group("structures"):
		if node.get("kind") == "shelter":
			shelter = node
	shelter.call("upgrade")
	var cow = null
	for animal in world.get_node("Livestock").call("get_animals"):
		if bool(animal.get("is_livestock")):
			cow = animal
			break
	_check(cow != null, "un animal d'élevage généré par le monde")
	cow.global_position = origin + Vector3(1, 1, 0)
	await process_frame
	cow.tame()
	_check(cow.penned and pen.get("level") == 2 and shelter.get("level") == 2, "avant sauvegarde : enclos 2, abri 2, vache en enclos")
	spawner.call("save_now")
	if world.get_node("Livestock").has_method("save_now"):
		world.get_node("Livestock").call("save_now")
	var pen_pos := pen.global_position
	world.free()
	await process_frame
	await process_frame

	var world2 = await _world()
	for i in 20:
		await process_frame
	var pens := get_nodes_in_group("pens")
	_check(pens.size() == 1, "un enclos restauré (%d)" % pens.size())
	if pens.size() == 1:
		_check(pens[0].get("level") == 2 and pens[0].call("capacity") == 10, "niveau 2 et capacité 10 restaurés")
		_check(pens[0].global_position.distance_to(pen_pos) < 0.5, "même position")
		var tamed_cows := 0
		for animal in get_nodes_in_group("tamed"):
			if bool(animal.get("is_livestock")) and bool(animal.get("penned")) and pens[0].call("contains", animal.global_position):
				tamed_cows += 1
		_check(tamed_cows == 1, "la bête apprivoisée est toujours dans l'enclos (%d)" % tamed_cows)
	var shelters := 0
	for node in get_nodes_in_group("structures"):
		if node.get("kind") == "shelter":
			shelters += 1
			_check(node.get("level") == 2, "abri niveau 2 restauré")
	_check(shelters == 1, "un abri restauré")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	print("TEST_RANCH_SAVE: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
