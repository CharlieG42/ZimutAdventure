extends SceneTree
## Fer : filons dans le monde (pioche requise), minerai, four (2 minerais + 1 bois = 1 lingot),
## recettes, quêtes et repères de carte.

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
	var craft := root.get_node("CraftManager")
	var quests := root.get_node("QuestManager")
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	paused = false
	var player := world.get_node("Player") as CharacterBody3D
	player.add_to_group("player")
	var spawner := world.get_node("Structures")
	spawner.call("disable_saving_for_test")
	inventory.call("clear_for_test")
	progression.call("clear_for_test", true)
	progression.call("add_xp", 100000)

	var veins := get_nodes_in_group("iron_veins")
	_check(veins.size() >= 15, "filons de fer dans le monde (%d)" % veins.size())
	var vein: Node3D = veins[0]
	_check(not vein.is_in_group("breakable"), "un filon n'est pas un simple rocher")
	_check(vein.call("get_prompt") == "ACTION_MINE_IRON_NEED_PICKAXE", "sans pioche : invite « pioche requise »")
	vein.call("_on_interact", player)
	await process_frame
	_check(is_instance_valid(vein) and not vein.is_queued_for_deletion(), "sans pioche, le filon résiste")

	# Pioche : recette.
	_check(craft.RECIPES.has("tool_pickaxe") and craft.RECIPES.has("building_furnace"), "recettes pioche et four")
	inventory.call("add_item", "tool_pickaxe", 1)
	inventory.call("equip", "tool_pickaxe")
	_check(vein.call("get_prompt") == "ACTION_MINE_IRON", "pioche en main : « Extraire le fer »")
	var vein_pos := vein.global_position
	vein.call("_on_interact", player)
	await process_frame
	var ore_drops := 0
	for node in world.find_children("*", "", true, false):
		if node.get("item_id") == "item_iron_ore" and node is Node3D and (node as Node3D).global_position.distance_to(vein_pos) < 4.0:
			ore_drops += 1
	_check(ore_drops >= 2, "le filon donne du minerai de fer (%d)" % ore_drops)

	# Four.
	_check(spawner.call("place", "building_furnace", player.global_position + Vector3(6, 0, -6), 0.0) == "", "four posé")
	var furnace: Node = get_nodes_in_group("furnaces")[0]
	_check(furnace.call("get_prompt") == "ACTION_SMELT_EMPTY", "four vide : rappel de la recette")
	inventory.call("add_item", "item_iron_ore", 7)
	inventory.call("add_item", "item_wood", 2)
	_check(furnace.call("smeltable") == 2, "7 minerais + 2 bois : 2 lingots possibles")
	furnace.call("_on_interact", player)
	_check(int(inventory.call("count_of", "item_iron_ingot")) == 2, "2 lingots de fer")
	_check(int(inventory.call("count_of", "item_iron_ore")) == 3 and int(inventory.call("count_of", "item_wood")) == 0, "minerai et bois consommés")

	# Quêtes, carte.
	_check(quests.QUESTS.has("quest_iron_ore") and quests.QUESTS["quest_iron_ingot"]["requires"] == "quest_iron_ore", "quêtes du fer enchaînées")
	_check(FileAccess.get_file_as_string("res://scripts/ui/map_panel.gd").contains("\"iron_veins\""), "filons sur la carte")
	print("TEST_IRON: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
