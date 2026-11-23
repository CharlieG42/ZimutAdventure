extends SceneTree
## « Tout collecter » : un clic sur l'enclos récolte lait, œufs et laine de toutes les bêtes prêtes.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	await process_frame
	var inventory := root.get_node("Inventory")
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
	inventory.call("clear_for_test")
	progression.call("clear_for_test", true)
	progression.call("add_xp", 100000)
	for existing in get_nodes_in_group("domestic"):
		existing.remove_from_group("tamed")
		existing.queue_free()
	await process_frame
	var origin: Vector3 = player.global_position + Vector3(14, 0, 14)
	spawner.call("place", "building_pen", origin, 0.0)
	var pen: Node = get_nodes_in_group("pens")[0]
	var scene := load("res://scenes/world/domestic_animal.tscn") as PackedScene
	var herd := {}
	for species in ["cow", "cow", "chicken", "sheep"]:
		var animal = scene.instantiate()
		animal.species = species
		animal.position = origin + Vector3(randf_range(-2, 2), 1, randf_range(-2, 2))
		world.add_child(animal)
		await process_frame
		animal.tame()
		herd[animal] = species
	_check(pen.call("get_occupants").size() == 4, "4 bêtes en enclos")
	_check(pen.call("get_prompt") != "ACTION_COLLECT_ALL", "rien de prêt : pas d'invite de collecte")
	for animal in herd:
		animal.set("ready_at", 0.0)
	await process_frame
	# La laine exige la faucille : sans elle, seules 3 bêtes sont collectables.
	_check(pen.call("collectable").size() == 3, "sans faucille : 3 bêtes collectables")
	_check(pen.call("get_prompt") == "ACTION_COLLECT_ALL" and pen.call("get_prompt_args") == [3], "invite : tout collecter (3)")
	pen.call("_on_interact", player)
	_check(int(inventory.call("count_of", "item_milk")) >= 2, "lait collecté")
	_check(int(inventory.call("count_of", "item_egg")) >= 1, "œuf collecté")
	_check(int(inventory.call("count_of", "item_wool")) == 0, "pas de laine sans faucille")
	_check(pen.call("collectable").is_empty(), "plus rien de prêt après la collecte")
	_check(pen.call("get_prompt") != "ACTION_COLLECT_ALL", "l'invite revient à rassembler / libérer")
	_check(int(progression.call("get_stat", "stat_products")) == 3, "3 produits comptés pour les succès")
	# Faucille en main : la laine suit.
	inventory.call("add_item", "tool_sickle", 1)
	inventory.call("equip", "tool_sickle")
	for animal in herd:
		animal.set("ready_at", 0.0)
	var totals: Dictionary = pen.call("collect_all")
	_check(int(totals.get("item_wool", 0)) >= 1, "avec la faucille : laine collectée")
	_check(totals.size() == 3, "trois sortes de produits récoltés en un clic")
	print("TEST_PEN_COLLECT: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
