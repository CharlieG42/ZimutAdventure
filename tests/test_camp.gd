extends SceneTree
## Camps : feu de camp posable, coffre de rangement, palissade solide, point de réveil.

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
	var survival := root.get_node("SurvivalManager")
	var craft := root.get_node("CraftManager")
	var quests := root.get_node("QuestManager")
	inventory.call("clear_for_test")
	quests.call("clear_for_test")
	progression.call("clear_for_test", true)
	survival.call("clear_for_test")
	for recipe_id in ["building_campfire", "furniture_chest", "building_palisade"]:
		_check(not bool(craft.call("meets_level", recipe_id)), "%s verrouillé au niveau 1" % recipe_id)
	progression.call("add_xp", 100000)

	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var player := world.get_node("Player") as CharacterBody3D
	var spawner := world.get_node("Structures")
	spawner.call("disable_saving_for_test")
	world.get_node("Livestock").call("disable_saving_for_test")
	inventory.call("clear_for_test")
	survival.call("clear_for_test")
	progression.call("clear_for_test", true)
	progression.call("add_xp", 100000)
	var origin: Vector3 = player.global_position + Vector3(10, 0, 10)

	# --- Feu de camp posable -------------------------------------------------------------------
	_check(spawner.call("is_placeable", "building_campfire"), "feu de camp posable")
	_check(spawner.call("place", "building_campfire", origin, 0.0) == "", "pose du feu de camp")
	var fires := get_nodes_in_group("campfire")
	var placed_fire: Node = fires[fires.size() - 1]
	_check(not bool(placed_fire.call("is_lit")), "feu posé éteint")
	inventory.call("add_item", "item_wood", 5)
	for i in 3:
		placed_fire.call("interact", player)
	_check(bool(placed_fire.call("is_lit")), "nourri de bois : allumé")
	_check(int(placed_fire.call("get_state")["stage"]) == 3, "état du feu sauvegardable")

	# --- Coffre ---------------------------------------------------------------------------------------
	_check(spawner.call("place", "furniture_chest", origin + Vector3(6, 0, 0), 0.0) == "", "pose du coffre")
	var chest: Node = get_nodes_in_group("chests")[0]
	inventory.call("clear_for_test")
	_check(chest.call("get_prompt") == "ACTION_CHEST_EMPTY", "coffre vide")
	inventory.call("add_item", "item_wood", 7)
	inventory.call("add_item", "item_cooked_meat", 2)
	inventory.call("add_item", "tool_stone_axe", 1)
	inventory.call("add_item", "arrow", 5)
	_check(chest.call("get_prompt") == "ACTION_CHEST_STORE", "objets à ranger : déposer")
	chest.call("interact", player)
	_check(inventory.call("count_of", "item_wood") == 0 and inventory.call("count_of", "item_cooked_meat") == 0, "ressources rangées")
	_check(inventory.call("count_of", "tool_stone_axe") == 1 and inventory.call("count_of", "arrow") == 5, "outils et flèches gardés")
	_check(int(chest.call("total_stored")) == 9, "contenu du coffre")
	_check(chest.call("get_prompt") == "ACTION_CHEST_TAKE", "plus rien à ranger : reprendre")
	var saved: Dictionary = chest.call("get_state")
	chest.call("interact", player)
	_check(inventory.call("count_of", "item_wood") == 7 and int(chest.call("total_stored")) == 0, "contenu repris")
	var chest2 = load("res://scripts/interaction/chest.gd").create()
	world.add_child(chest2)
	chest2.call("apply_state", saved)
	_check(int(chest2.call("total_stored")) == 9, "contenu restauré depuis la sauvegarde")

	# --- Palisade ----------------------------------------------------------------------------------------
	_check(spawner.call("place", "building_palisade", origin + Vector3(0, 0, -8), 0.0) == "", "pose de la palissade")
	var fence: Node3D = get_nodes_in_group("palisades")[0]
	var space = world.get_world_3d().direct_space_state
	var from := fence.global_position + Vector3(0, 1.0, 3.0)
	var query = PhysicsRayQueryParameters3D.create(from, fence.global_position + Vector3(0, 1.0, -3.0), 1)
	_check(not space.intersect_ray(query).is_empty(), "la palissade bloque le passage (couche 1)")

	# --- Point de réveil ---------------------------------------------------------------------------------------
	_check(spawner.call("place", "furniture_camp_bed", origin + Vector3(-8, 0, 0), 0.0) == "", "pose du lit")
	var bed: Node = null
	for node in get_nodes_in_group("structures"):
		if node.get("kind") == "camp_bed":
			bed = node
	player.global_position = bed.global_position + Vector3(0, 1, 2)
	bed.call("interact", player)
	survival.call("damage", 2.0)
	await process_frame
	var flat := Vector2(player.global_position.x - bed.global_position.x, player.global_position.z - bed.global_position.z)
	_check(flat.length() < 3.0, "terrassé : on se réveille près du lit")

	for id in ["quest_camp", "quest_chest"]:
		_check(quests.QUESTS.has(id), "quête %s" % id)
	print("TEST_CAMP: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
