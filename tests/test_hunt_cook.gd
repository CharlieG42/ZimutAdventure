extends SceneTree
## Chasse et cuisson : tir de flèche, proie touchée -> viande, cuisson au feu, quêtes.

func _ensure(node_name: String, script_path: String) -> Node:
	var node := root.get_node_or_null(node_name)
	if node == null:
		node = (load(script_path) as GDScript).new()
		node.name = node_name
		root.add_child(node)
	return node

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	var inventory := _ensure("Inventory", "res://scripts/autoload/inventory.gd")
	_ensure("Sfx", "res://scripts/autoload/sfx.gd")
	await process_frame
	inventory.call("clear_for_test")
	var quests := _ensure("QuestManager", "res://scripts/autoload/quest_manager.gd")
	var craft := _ensure("CraftManager", "res://scripts/autoload/craft_manager.gd")
	await process_frame
	quests.call("clear_for_test")
	quests.call("enable_rewards_for_test")
	quests.call("_unlock_available")

	# --- Flèches en batch ------------------------------------------------------------
	inventory.call("add_item", "item_wood", 2)
	inventory.call("add_item", "item_stone", 2)
	if not craft.call("craft", "arrow"):
		errors.append("les flèches doivent être fabricables (1 bois + 1 pierre)")
	if inventory.call("count_of", "arrow") != 4:
		errors.append("la recette de flèches doit donner 4 flèches, reçu %d" % inventory.call("count_of", "arrow"))

	# --- Tir sans arc : rien ne se passe ---------------------------------------------
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in range(10):
		await process_frame
	var player := world.get_node("Player") as CharacterBody3D
	var before_arrows := int(inventory.call("count_of", "arrow"))
	player.call("try_shoot_arrow")
	await physics_frame
	if int(inventory.call("count_of", "arrow")) != before_arrows:
		errors.append("tirer sans arc ne doit pas consommer de flèche")

	# --- Quêtes du chasseur : déblocage de la chaîne (hache -> arc) ---------------------
	# Fabriquer hache et arc enchaîne les quêtes jusqu'à quest_first_hunt.
	inventory.call("add_item", "item_stone", 4)
	inventory.call("add_item", "item_wood", 5)
	await process_frame
	if not craft.call("craft", "tool_stone_axe"):
		errors.append("la hache doit être fabricable (2 pierres + 1 bois)")
	if not craft.call("craft", "tool_hunting_bow"):
		errors.append("l'arc doit être fabricable avec 3 bois")
	await process_frame
	# Chaîne de quêtes : le bûcheron (3 arbres abattus) précède l'arc.
	root.get_node("Progression").call("add_stat", "stat_trees", 3)
	quests.call("_evaluate_all", true)
	await process_frame
	var active: Array = quests.call("get_active")
	if not ("quest_first_hunt" in active):
		errors.append("quest_first_hunt doit se débloquer après quest_hunter (actives : %s)" % str(active))
	# --- L'arc possédé mais non équipé ne tire pas (la hache, obtenue d'abord, est équipée) ---
	var arrows_before_equip := int(inventory.call("count_of", "arrow"))
	player.call("try_shoot_arrow")
	if int(inventory.call("count_of", "arrow")) != arrows_before_equip:
		errors.append("tirer avec l'arc non équipé ne doit pas consommer de flèche")
	inventory.call("equip", "tool_hunting_bow")
	# --- Tir avec arc : la flèche part et touche l'animal visé ------------------------
	var animals := world.get_node("Animals")
	var prey: Node = null
	for animal in animals.get_children():
		prey = animal
		break
	if prey == null:
		errors.append("des animaux doivent être présents dans le canyon")
	else:
		# Place la proie pile devant le joueur, dans l'axe de la caméra.
		var cam := player.get_node("CameraPivot/Camera3D") as Camera3D
		var aim := -cam.global_transform.basis.z
		prey.global_position = cam.global_position + aim * 3.0
		prey.velocity = Vector3.ZERO
		await physics_frame
		var meat_before := int(inventory.call("count_of", "item_raw_meat"))
		var arrows := int(inventory.call("count_of", "arrow"))
		player.call("try_shoot_arrow")
		if int(inventory.call("count_of", "arrow")) != arrows - 1:
			errors.append("le tir doit consommer exactement une flèche")
		# La flèche vole ~3 m à 26 m/s : quelques frames suffisent.
		var hit := false
		for i in range(60):
			await physics_frame
			if prey.get("_dead") == true:
				hit = true
				break
		if not hit:
			errors.append("la flèche tirée droit sur la proie doit la toucher")
		var meat_after := int(inventory.call("count_of", "item_raw_meat"))
		if meat_after <= meat_before:
			errors.append("une proie abattue doit donner de la viande crue (avant %d, après %d)" % [meat_before, meat_after])
		# Une proie morte ne se blesse pas deux fois.
		var arrows2 := int(inventory.call("count_of", "arrow"))
		prey.call("take_arrow_hit", prey.global_position)
		if int(inventory.call("count_of", "arrow")) != arrows2:
			errors.append("toucher une proie déjà abattue ne doit rien consommer")

	# --- Cuisson au feu plein -----------------------------------------------------------
	var fire := world.get_node("Campfire")
	fire.set("_stage", 4)
	await process_frame
	if fire.get_prompt() != "ACTION_COOK":
		errors.append("un feu plein avec de la viande crue doit proposer ACTION_COOK, reçu %s" % fire.get_prompt())
	inventory.call("add_item", "item_raw_meat", 1)
	var raw := int(inventory.call("count_of", "item_raw_meat"))
	var cooked := int(inventory.call("count_of", "item_cooked_meat"))
	fire.call("interact", player)
	await process_frame
	if int(inventory.call("count_of", "item_raw_meat")) != raw - 1:
		errors.append("la cuisson doit consommer une viande crue")
	if int(inventory.call("count_of", "item_cooked_meat")) != cooked + 1:
		errors.append("la cuisson doit donner une viande cuite")

	if quests.call("state_of", "quest_first_hunt") != 2:
		errors.append("la récolte de viande crue doit terminer quest_first_hunt")
	# La quête du repas a pu être activée puis complétée dans la même évaluation :
	# on exige l'état final COMPLETED.
	if quests.call("state_of", "quest_cooked_meal") != 2:
		errors.append("la viande cuite doit terminer quest_cooked_meal (reçu %d)" % quests.call("state_of", "quest_cooked_meal"))

	world.free()

	var exit_code := 0
	if errors.is_empty():
		print("TEST_HUNT_COOK: PASS")
	else:
		exit_code = 1
		for e in errors:
			printerr("TEST_HUNT_COOK FAIL: " + e)
	quit(exit_code)
