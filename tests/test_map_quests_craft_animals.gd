extends SceneTree
## Carte, quêtes, fabrication, animaux : intégration complète.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	var inventory_node := root.get_node_or_null("Inventory")
	if inventory_node == null:
		inventory_node = (load("res://scripts/autoload/inventory.gd") as GDScript).new()
		inventory_node.name = "Inventory"
		root.add_child(inventory_node)
		await process_frame
	inventory_node.call("clear_for_test")
	var sfx_node := root.get_node_or_null("Sfx")
	if sfx_node == null:
		sfx_node = (load("res://scripts/autoload/sfx.gd") as GDScript).new()
		sfx_node.name = "Sfx"
		root.add_child(sfx_node)
		await process_frame
	var quest_node := root.get_node_or_null("QuestManager")
	if quest_node == null:
		quest_node = (load("res://scripts/autoload/quest_manager.gd") as GDScript).new()
		quest_node.name = "QuestManager"
		root.add_child(quest_node)
		await process_frame
	var craft_node := root.get_node_or_null("CraftManager")
	if craft_node == null:
		craft_node = (load("res://scripts/autoload/craft_manager.gd") as GDScript).new()
		craft_node.name = "CraftManager"
		root.add_child(craft_node)
		await process_frame

	# --- Fabrication ----------------------------------------------------------------
	var recipe_ids: Array = craft_node.call("get_recipe_ids")
	if recipe_ids.size() < 4:
		errors.append("CraftManager should expose at least 4 recipes, got %d" % recipe_ids.size())
	if craft_node.call("can_craft", "tool_stone_axe"):
		errors.append("stone axe should not be craftable without ingredients")
	inventory_node.call("add_item", "item_stone", 2)
	inventory_node.call("add_item", "item_wood", 1)
	if not craft_node.call("can_craft", "tool_stone_axe"):
		errors.append("stone axe should be craftable with 2 stones + 1 wood")
	if not craft_node.call("craft", "tool_stone_axe"):
		errors.append("craft(tool_stone_axe) should succeed")
	if inventory_node.call("count_of", "tool_stone_axe") != 1:
		errors.append("craft should add the tool to inventory")
	if inventory_node.call("count_of", "item_stone") != 0 or inventory_node.call("count_of", "item_wood") != 0:
		errors.append("craft should consume ingredients")

	# --- Quêtes ----------------------------------------------------------------------
	quest_node.call("clear_for_test")
	# La hache fabriquée plus haut terminerait « Premiers outils » (et sa récompense de
	# bûches ferait aboutir « Un feu au chaud ») : on la retire pour isoler ce test.
	inventory_node.call("remove_item", "tool_stone_axe", 1)
	for quest_id in quest_node.get("QUESTS").keys():
		quest_node.call("activate", quest_id)
	inventory_node.call("add_item", "item_stone", 3)
	await process_frame
	if quest_node.call("state_of", "quest_first_stone") != 2:
		errors.append("quest_first_stone should be COMPLETED with 3 stones, state=%d" % quest_node.call("state_of", "quest_first_stone"))
	if quest_node.call("state_of", "quest_warm_fire") == 2:
		errors.append("quest_warm_fire should not complete without wood")

	# --- Animaux ----------------------------------------------------------------------
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in range(10):
		await process_frame
	var animals := world.get_node_or_null("Animals")
	if animals == null or animals.get_child_count() < 3:
		errors.append("canyon should spawn animals, got %d" % (animals.get_child_count() if animals != null else -1))
	else:
		var landscape := world.get_node("Landscape")
		var moved := false
		var start_positions := {}
		for animal in animals.get_children():
			start_positions[animal] = animal.global_position
		for i in range(30):
			await physics_frame
		for animal in animals.get_children():
			if animal.global_position.distance_to(start_positions[animal]) > 0.1:
				moved = true
			var ground: float = landscape.terrain_height_at(animal.global_position.x, animal.global_position.z)
			if animal.global_position.y < ground - 1.0 or animal.global_position.y > ground + 4.0:
				errors.append("animal hors sol : y=%f sol=%f" % [animal.global_position.y, ground])
				break
		if not moved:
			errors.append("animals should wander")

	# --- Carte ------------------------------------------------------------------------
	var map_panel := world.get_node_or_null("HUD/MapPanel")
	if map_panel == null:
		errors.append("HUD should contain MapPanel")
	else:
		if map_panel.visible:
			errors.append("map should start hidden")
		map_panel.call("open")
		await process_frame
		if not map_panel.visible:
			errors.append("map open() should show it")
		if map_panel.get("_terrain_image") == null:
			errors.append("map should build a terrain texture")
		map_panel.call("close")
		if map_panel.visible:
			errors.append("map close() should hide it")

	# --- Invite de ramassage éteinte après collecte ------------------------------------
	var prompt: Label = world.get_node("HUD/Overlay/CenterPrompt")
	var player := world.get_node("Player")
	var item_scene := load("res://scenes/interaction/collectible_item.tscn") as PackedScene
	var item := item_scene.instantiate()
	world.add_child(item)
	var cam := player.get_node("CameraPivot/Camera3D") as Camera3D
	item.global_position = cam.global_position + (-cam.global_transform.basis.z) * 1.5
	for i in range(5):
		await process_frame
	if not prompt.visible:
		errors.append("prompt should be visible when aiming at a collectible")
	player.call("try_interact")
	for i in range(5):
		await process_frame
	if prompt.visible:
		errors.append("prompt should hide after pickup (bug bouton ramasser)")
	var hud_script: GDScript = load("res://scripts/ui/hud.gd")
	world.free()

	var exit_code := 0
	if errors.is_empty():
		print("TEST_MAP_QUESTS_CRAFT_ANIMALS: PASS")
	else:
		exit_code = 1
		for e in errors:
			printerr("TEST_MAP_QUESTS_CRAFT_ANIMALS FAIL: " + e)
	quit(exit_code)
