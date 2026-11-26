extends SceneTree
## Ruines restaurées : chantier en trois étapes (pierre, bois, fer) réservé aux hauts niveaux,
## refuge (lit, coffre sauvegardé, âtre, abri contre le froid) et voyage rapide gratuit.

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
	var exploration := root.get_node("Exploration")
	var survival := root.get_node("SurvivalManager")
	var quests := root.get_node("QuestManager")
	exploration.call("clear_for_test")
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	paused = false
	var player := world.get_node("Player") as CharacterBody3D
	player.add_to_group("player")
	world.get_node("Structures").call("disable_saving_for_test")
	inventory.call("clear_for_test")
	progression.call("clear_for_test", true)

	var sites := get_nodes_in_group("ruin_restorations")
	_check(sites.size() == 3, "un chantier par ruine (%d)" % sites.size())
	var ruin: Node3D = sites[0]
	var site_id := String(ruin.get("site_id"))
	_check(String(exploration.call("get_site", site_id).get("kind", "")) == "ruin", "chantier rattaché à une ruine")
	_check(not ruin.is_in_group("structures"), "ruine non restaurée : pas encore un abri")
	_check(ruin.call("get_prompt") == "ACTION_RUIN_RESTORE", "invite « Restaurer la ruine »")
	_check(int(ruin.call("get_prompt_args")[1]) == 1, "étape 1/3")

	# Haut niveau requis.
	inventory.call("add_item", "item_stone", 20)
	inventory.call("add_item", "item_wood", 6)
	_check(ruin.call("advance") == "TOAST_RUIN_LEVEL", "niveau 1 : chantier refusé")
	progression.call("add_xp", 100000)
	inventory.call("clear_for_test")
	inventory.call("add_item", "item_stone", 10)
	_check(ruin.call("advance") == "TOAST_RUIN_NEED", "matériaux manquants : refusé")
	_check(String(ruin.call("cost_text")).contains("10/20"), "coût affiché avec ce qu'on a (%s)" % ruin.call("cost_text"))
	inventory.call("add_item", "item_stone", 10)
	inventory.call("add_item", "item_wood", 6)
	_check(ruin.call("advance") == "" and int(ruin.get("stage")) == 1, "étape 1 : murs relevés")
	_check(int(inventory.call("count_of", "item_stone")) == 0, "pierres dépensées")
	_check(int(exploration.call("ruin_stage", site_id)) == 1, "avancement enregistré")
	inventory.call("add_item", "item_wood", 16)
	inventory.call("add_item", "item_pelt", 2)
	_check(ruin.call("advance") == "", "étape 2 : charpente")
	inventory.call("add_item", "item_iron_ingot", 6)
	inventory.call("add_item", "item_wood", 10)
	_check(ruin.call("advance") == "" and bool(ruin.call("is_complete")), "étape 3 : toit ferré, refuge terminé")
	_check(bool(exploration.call("is_refuge", site_id)), "refuge connu de l'exploration")
	_check(ruin.call("advance") == "TOAST_RUIN_DONE", "plus rien à faire")
	await process_frame

	# Mobilier et abri.
	var bed_found := false
	var hearth_found := false
	for node in ruin.find_children("*", "", true, false):
		if node.get("kind") == "wool_bed":
			bed_found = true
		if node.is_in_group("campfire") and bool(node.call("is_lit")):
			hearth_found = true
	_check(bed_found, "lit de laine dans le refuge")
	_check(hearth_found, "âtre toujours allumé")
	var chest: Node = ruin.call("get_chest")
	_check(chest != null and chest.is_in_group("chests"), "coffre dans le refuge")
	inventory.call("add_item", "item_berries", 5)
	_check(int(chest.call("store_item", "item_berries", 5)) == 5, "dépôt dans le coffre")
	_check(int((exploration.call("refuge_stock", site_id) as Dictionary).get("item_berries", 0)) == 5, "contenu du coffre sauvegardé")
	_check(ruin.is_in_group("structures") and ruin.get("kind") == "shelter", "le refuge compte comme un abri")
	player.global_position = ruin.call("shelter_center") + Vector3(0, 1, 0)
	var context: Dictionary = survival.call("_gather_context", player)
	_check(bool(context.get("sheltered", false)), "à l'intérieur : à l'abri")
	_check(float(context.get("fire_distance", -1.0)) >= 0.0 and float(context.get("fire_distance", -1.0)) < 4.0, "l'âtre réchauffe")

	# Reconstruction : le coffre retrouve son contenu.
	ruin.call("_rebuild")
	await process_frame
	var chest2: Node = ruin.call("get_chest")
	_check(int((chest2.get("stock") as Dictionary).get("item_berries", 0)) == 5, "coffre rechargé avec son contenu")

	# Voyage rapide gratuit vers le refuge, payant ailleurs.
	exploration.call("discover", site_id, true)
	_check(bool(exploration.call("travel_is_free_to", site_id)), "voyage gratuit vers le refuge")
	var other := String(sites[1].get("site_id"))
	_check(not bool(exploration.call("travel_is_free_to", other)), "voyage payant vers une ruine non restaurée")
	player.global_position = Vector3(0, 5, 0)
	survival.call("consume", 0.95, 0.95)
	_check(exploration.call("fast_travel", site_id, player) == "", "même affamé, on rejoint son refuge")
	_check(int(progression.call("get_stat", "stat_refuges")) == 1, "statistique refuges")
	_check(quests.QUESTS.has("quest_refuge"), "quête « Un toit dans l'Ouest »")

	print("TEST_RUIN_REFUGE: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures > 0 else 0)
