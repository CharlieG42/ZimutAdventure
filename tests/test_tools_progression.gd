extends SceneTree
## Outils équipables, abattage d'arbres (hache), baies (serpette), niveaux et quêtes liées.

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
	var quests := root.get_node("QuestManager")
	var craft := root.get_node("CraftManager")
	inventory.call("clear_for_test")
	progression.call("clear_for_test", true)
	quests.call("clear_for_test")
	quests.call("_unlock_available")

	# --- Niveaux ------------------------------------------------------------------------
	_check(int(progression.call("get_level")) == 1, "niveau 1 au départ")
	_check(not bool(craft.call("meets_level", "tool_sickle")), "serpette interdite au niveau 1")
	inventory.call("add_item", "item_wood", 5)
	inventory.call("add_item", "item_stone", 5)
	# Les ajouts ci-dessus ont validé des quêtes (XP) : on repart d'un niveau 1 propre.
	quests.call("clear_for_test")
	progression.call("clear_for_test", true)
	_check(not bool(craft.call("can_craft", "tool_sickle")), "ingrédients réunis mais niveau insuffisant")
	var levels := [0]
	progression.connect("level_up", func(l: int) -> void: levels[0] = l)
	progression.call("add_xp", int(progression.call("get_xp_needed")))
	_check(int(progression.call("get_level")) == 2 and levels[0] == 2, "niveau 2 atteint, signal émis")
	_check(bool(craft.call("can_craft", "tool_sickle")), "serpette fabricable au niveau 2")
	_check(float(progression.call("stamina_regen_multiplier")) > 1.0, "bonus d'endurance par niveau")
	progression.call("add_xp", 100000)
	_check(int(progression.call("get_level")) == int(progression.get("MAX_LEVEL")), "niveau plafonné")
	progression.call("clear_for_test", true)
	progression.call("add_xp", 45)

	# --- Équipement ----------------------------------------------------------------------
	_check(not bool(inventory.call("equip", "tool_stone_axe")), "impossible d'équiper un outil absent")
	_check(not bool(inventory.call("equip", "item_wood")), "une ressource n'est pas un outil")
	craft.call("craft", "tool_stone_axe")
	_check(inventory.call("get_equipped") == "tool_stone_axe", "le premier outil est équipé d'office")
	craft.call("craft", "tool_sickle")
	_check(inventory.call("get_equipped") == "tool_stone_axe", "un second outil ne remplace pas le premier")
	inventory.call("equip", "tool_sickle")
	_check(bool(inventory.call("is_equipped", "tool_sickle")), "changement d'outil")
	_check((inventory.call("get_owned_tools") as Array).size() == 2, "deux outils dans la barre")

	# --- Barre d'outils ---------------------------------------------------------------------
	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	var hotbar: Node = hud.get_node("Overlay/Hotbar")
	hotbar.call("refresh")
	await process_frame
	_check(int(hotbar.call("slot_count")) == 2, "un emplacement par outil possédé")
	hotbar.call("select_index", 0)
	_check(inventory.call("get_equipped") == "tool_stone_axe", "emplacement 1 = hache")
	hotbar.call("select_index", 0)
	_check(inventory.call("get_equipped") == "", "retoucher l'outil le range")
	hotbar.call("select_index", 0)

	# --- Arbre : hache requise, plusieurs coups --------------------------------------------------
	var host := Node3D.new()
	root.add_child(host)
	var tree_scene := load("res://scenes/interaction/choppable_tree.tscn") as PackedScene
	var tree_node: Node3D = tree_scene.instantiate()
	host.add_child(tree_node)
	await process_frame
	inventory.call("equip", "tool_sickle")
	tree_node.call("interact", null)
	_check(int(tree_node.get("hits")) == 0, "sans hache équipée, un coup ne compte pas")
	_check(tree_node.call("get_prompt") == "ACTION_NEED_AXE", "invite : hache requise")
	inventory.call("equip", "tool_stone_axe")
	_check(tree_node.call("get_prompt") == "ACTION_CHOP", "invite : couper")
	var wood_before := host.get_children().size()
	for i in 3:
		tree_node.call("interact", null)
	_check(not bool(tree_node.get("felled")), "l'arbre résiste aux premiers coups")
	tree_node.call("interact", null)
	_check(bool(tree_node.get("felled")), "le quatrième coup abat l'arbre")
	_check(not bool(tree_node.call("can_interact")), "un arbre abattu n'est plus interactif")
	_check(host.get_children().size() > wood_before, "du bois tombe au sol")
	_check(int(progression.call("get_stat", "stat_trees")) == 1, "compteur d'arbres abattus")

	# --- Baies : serpette requise, repousse -----------------------------------------------------
	var bush: Node3D = (load("res://scenes/interaction/berry_bush.tscn") as PackedScene).instantiate()
	host.add_child(bush)
	await process_frame
	inventory.call("equip", "tool_stone_axe")
	bush.call("interact", null)
	_check(inventory.call("count_of", "item_berries") == 0, "sans serpette, pas de baies")
	_check(bool(bush.call("can_interact")), "le buisson reste mûr")
	inventory.call("equip", "tool_sickle")
	bush.call("interact", null)
	_check(inventory.call("count_of", "item_berries") >= 2, "baies cueillies")
	_check(not bool(bush.call("can_interact")), "buisson vide : plus d'invite")
	bush.call("_regrow")
	_check(bool(bush.call("can_interact")), "le buisson repousse")

	# --- Quêtes liées ----------------------------------------------------------------------------
	quests.call("clear_for_test")
	quests.call("_unlock_available")
	progression.call("clear_for_test", true)
	_check("quest_lumberjack" in quests.call("get_locked"), "bûcheron verrouillé au départ")
	quests.call("set_state", "quest_first_stone", 2)
	quests.call("set_state", "quest_builder", 2)
	quests.call("_unlock_available")
	_check("quest_lumberjack" in quests.call("get_active"), "bûcheron actif après la hache")
	progression.call("add_stat", "stat_trees", 2)
	_check("quest_lumberjack" in quests.call("get_active"), "2 arbres sur 3 : pas terminée")
	progression.call("add_stat", "stat_trees", 1)
	_check("quest_lumberjack" in quests.call("get_completed"), "3 arbres : quête terminée")
	_check("quest_sickle" in quests.call("get_active"), "la serpette se débloque ensuite")
	_check(int(progression.call("get_xp")) > 0, "la quête rapporte de l'XP")

	print("FAIL" if _failures > 0 else "PASS", " test_tools_progression")
	quit(1 if _failures > 0 else 0)
