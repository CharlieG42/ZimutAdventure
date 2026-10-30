extends SceneTree
## Quêtes (progression cumulative, déblocage en chaîne), journal à onglets et carte.

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
	quests.call("_unlock_available")

	# Déblocage en chaîne : seules les quêtes sans prérequis sont actives au départ.
	var active: Array = quests.call("get_active")
	if "quest_builder" in active or "quest_hunter" in active:
		errors.append("les quêtes à prérequis doivent rester verrouillées au départ")
	if not ("quest_first_stone" in active and "quest_warm_fire" in active):
		errors.append("les quêtes de départ doivent être actives : %s" % str(active))

	# Progression visible avant la fin.
	inventory.call("add_item", "item_stone", 2)
	var progress: Vector2i = quests.call("get_progress", "quest_first_stone")
	if progress != Vector2i(2, 3):
		errors.append("progression attendue 2/3, reçu %s" % str(progress))

	# Fin de quête -> la suivante se débloque.
	inventory.call("add_item", "item_stone", 1)
	if quests.call("state_of", "quest_first_stone") != 2:
		errors.append("quest_first_stone doit être terminée à 3 pierres")
	if quests.call("state_of", "quest_builder") != 1:
		errors.append("quest_builder doit se débloquer après les premières pierres")

	# Récompense : 2 bûches offertes à la fin de « Premières pierres ».
	if int(inventory.call("count_of", "item_wood")) != 2:
		errors.append("la récompense de quest_first_stone doit offrir 2 bûches")

	# Progression CUMULATIVE : fabriquer consomme les pierres sans défaire la quête.
	inventory.call("add_item", "item_wood", 4)
	if quests.call("state_of", "quest_warm_fire") != 2:
		errors.append("quest_warm_fire doit être terminée à 4 bûches")
	inventory.call("add_item", "item_stone", 1)  # il en faut 2 pour la hache
	if not craft.call("craft", "tool_stone_axe"):
		errors.append("la hache doit être fabricable")
	if quests.call("state_of", "quest_first_stone") != 2:
		errors.append("dépenser des pierres ne doit pas annuler une quête terminée")
	if quests.call("state_of", "quest_builder") != 2:
		errors.append("fabriquer la hache doit terminer quest_builder")
	if quests.call("state_of", "quest_hunter") != 1:
		errors.append("quest_hunter doit se débloquer après la hache")
	if quests.call("get_tracked") != "quest_hunter":
		errors.append("l'objectif suivi doit être la première quête active : %s" % quests.call("get_tracked"))

	# Aides de fabrication.
	var missing: Dictionary = craft.call("get_missing", "building_shelter")
	var want_wood: int = 8 - int(inventory.call("count_of", "item_wood"))
	var want_stone: int = 4 - int(inventory.call("count_of", "item_stone"))
	if int(missing.get("item_wood", 0)) != want_wood or int(missing.get("item_stone", 0)) != want_stone:
		errors.append("get_missing doit lister %d bois et %d pierres : %s" % [want_wood, want_stone, str(missing)])
	if (craft.call("get_recipes_in_category", "tools") as Array).size() != 1:
		errors.append("la catégorie outils doit contenir une recette")

	# --- Journal -----------------------------------------------------------------
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 5:
		await process_frame
	var journal: Node = world.get_node("HUD/InventoryCenter/JournalPanel")
	journal.open()
	await process_frame
	var tabs := journal.find_children("*", "TabContainer", true, false)
	if tabs.is_empty() or (tabs[0] as TabContainer).get_tab_count() != 3:
		errors.append("le journal doit avoir 3 onglets")
	# Le journal se met à jour tout seul quand une quête progresse.
	var cards_before := journal.find_children("*", "ProgressBar", true, false).size()
	inventory.call("add_item", "item_wood", 3)
	await process_frame
	await process_frame
	var bars := journal.find_children("*", "ProgressBar", true, false)
	if bars.is_empty() or cards_before == 0:
		errors.append("le journal doit afficher des barres de progression")
	# Une recette craftable a un bouton actif, les autres sont désactivées.
	# Les récompenses ont rempli le sac : on le vide pour tester les deux états.
	inventory.call("clear_for_test")
	inventory.call("add_item", "item_wood", 3)
	journal.open()
	await process_frame
	journal.show_tab(1)
	var enabled := 0
	var disabled := 0
	for button in journal.find_children("*", "Button", true, false):
		if (button as Button).text == tr("ACTION_CRAFT") or (button as Button).text == "ACTION_CRAFT":
			if (button as Button).disabled:
				disabled += 1
			else:
				enabled += 1
	if enabled < 1 or disabled < 1:
		errors.append("boutons de fabrication : %d actifs / %d désactivés" % [enabled, disabled])
	journal.close()

	# --- Carte : carré, centré, repère du joueur au centre quand il est au centre ---
	var map_panel: Control = world.get_node("HUD/MapPanel")
	map_panel.size = Vector2(1600, 720)
	var rect: Rect2 = map_panel.call("_map_rect")
	if absf(rect.size.x - rect.size.y) > 0.5:
		errors.append("la carte doit être carrée (%s)" % str(rect.size))
	if rect.end.y > 720.0 - 70.0:
		errors.append("la carte ne doit pas recouvrir la barre du bas du HUD")
	var to_map: Transform2D = map_panel.call("_world_to_map_transform", rect)
	if (to_map * Vector2.ZERO).distance_to(rect.get_center()) > 0.5:
		errors.append("le centre du monde doit tomber au centre de la carte")
	map_panel.open()
	await process_frame
	if map_panel.get("_terrain_image") == null:
		errors.append("la carte doit avoir une texture de relief")

	world.free()
	if errors.is_empty():
		print("TEST_QUESTS_JOURNAL: PASS")
		quit(0)
	else:
		for e in errors:
			printerr("TEST_QUESTS_JOURNAL FAIL: ", e)
		quit(1)
