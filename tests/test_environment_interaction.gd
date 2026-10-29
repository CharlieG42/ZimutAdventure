extends SceneTree
## Objets interactifs : feu de camp (bois, allumage, repos), pancarte,
## panneau d'inventaire du HUD.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	# En mode headless (-s) les autoloads peuvent ne pas être chargés selon la
	# version : on réutilise ceux du root s'ils existent, sinon on les instancie
	# avec les noms attendus.
	var inventory_node := root.get_node_or_null("Inventory")
	if inventory_node == null:
		inventory_node = (load("res://scripts/autoload/inventory.gd") as GDScript).new()
		inventory_node.name = "Inventory"
		root.add_child(inventory_node)
		await process_frame
	var sfx_node := root.get_node_or_null("Sfx")
	if sfx_node == null:
		sfx_node = (load("res://scripts/autoload/sfx.gd") as GDScript).new()
		sfx_node.name = "Sfx"
		root.add_child(sfx_node)
	await process_frame
	inventory_node.call("clear_for_test")
	var stub := Node3D.new()
	root.add_child(stub)
	await process_frame

	# --- Feu de camp ----------------------------------------------------------------
	var campfire_scene := load("res://scenes/interaction/campfire.tscn") as PackedScene
	if campfire_scene == null:
		errors.append("campfire.tscn missing")
	else:
		var fire := campfire_scene.instantiate()
		if fire == null:
			errors.append("campfire.tscn should instantiate")
		else:
			root.add_child(fire)
			await process_frame
			var stage: int = fire.get("_stage")
			if stage != 0:
				errors.append("campfire should start at stage 0, got %d" % stage)
			var light := fire.get_node("FireLight") as OmniLight3D
			if light == null or light.visible:
				errors.append("campfire light should start hidden")
			if fire.get_prompt() != "ACTION_STOKE_FIRE":
				errors.append("campfire prompt should be ACTION_STOKE_FIRE, got %s" % fire.get_prompt())
			var inventory := inventory_node
			# Pas de bois -> pas d'alimentation
			fire.call("interact", stub)
			if fire.get("_stage") != 0:
				errors.append("campfire stage should stay 0 without wood")
			# 4 bois -> feu complet
			inventory.call("add_item", "item_wood", 4)
			for i in 4:
				fire.call("interact", stub)
				await process_frame
			if fire.get("_stage") != 4:
				errors.append("campfire stage should be 4 after 4 wood, got %d" % fire.get("_stage"))
			if light == null or not light.visible or light.light_energy <= 0.0:
				errors.append("campfire light should be lit at full stage")
			if fire.get_prompt() != "ACTION_REST":
				errors.append("full campfire prompt should be ACTION_REST, got %s" % fire.get_prompt())
			if inventory.call("count_of", "item_wood") != 0:
				errors.append("wood should be consumed")
			# Repos -> stamina restaurée
			var player_scene := load("res://scenes/player/player.tscn") as PackedScene
			var player := player_scene.instantiate()
			root.add_child(player)
			await process_frame
			player.set("stamina", 0.05)
			player.call("restore_stamina")
			if absf(float(player.get("stamina")) - 1.0) > 0.001:
				errors.append("restore_stamina should refill stamina, got %f" % float(player.get("stamina")))
			player.free()
			fire.free()

	# --- Pancarte -------------------------------------------------------------------
	var sign_scene := load("res://scenes/interaction/signpost.tscn") as PackedScene
	if sign_scene == null:
		errors.append("signpost.tscn missing")
	else:
		var sign := sign_scene.instantiate()
		if sign == null:
			errors.append("signpost.tscn should instantiate")
		else:
			root.add_child(sign)
			await process_frame
			if sign.get_prompt() != "ACTION_READ":
				errors.append("signpost prompt should be ACTION_READ, got %s" % sign.get_prompt())
			if String(sign.get("message_key")) == "":
				errors.append("signpost should have a message_key")
			sign.free()

	# --- Bois ramassable ------------------------------------------------------------
	var wood_scene := load("res://scenes/interaction/wood_item.tscn") as PackedScene
	if wood_scene == null:
		errors.append("wood_item.tscn missing")
	else:
		var wood := wood_scene.instantiate()
		if wood == null:
			errors.append("wood_item.tscn should instantiate")
		else:
			if String(wood.get("item_id")) != "item_wood":
				errors.append("wood item_id should be item_wood, got %s" % wood.get("item_id"))
			wood.free()

	# --- Panneau d'inventaire --------------------------------------------------------
	var hud_packed := load("res://scenes/ui/hud.tscn") as PackedScene
	if hud_packed == null:
		errors.append("hud.tscn missing")
	else:
		var hud := hud_packed.instantiate()
		root.add_child(hud)
		await process_frame
		await process_frame
		var panel := hud.get_node_or_null("InventoryCenter/InventoryPanel")
		if panel == null:
			errors.append("HUD should contain InventoryCenter/InventoryPanel")
		else:
			if panel.visible:
				errors.append("inventory panel should start hidden")
			var inventory2 := inventory_node
			inventory2.call("clear_for_test")
			panel.call("open")
			await process_frame
			if not panel.visible:
				errors.append("inventory panel open() should show it")
			var rows: Array = panel.get("_list").get_children()
			if rows.is_empty() or not String(rows[0].text).contains(tr("INVENTORY_EMPTY")):
				errors.append("empty inventory should show INVENTORY_EMPTY, got %s" % (rows[0].text if not rows.is_empty() else "nothing"))
			inventory2.call("add_item", "item_wood", 3)
			panel.call("open")
			await process_frame
			rows = panel.get("_list").get_children()
			if rows.size() != 1 or not String(rows[0].text).contains("3"):
				errors.append("panel should list 3x item_wood, got %d row(s)" % rows.size())
			panel.call("close")
			if panel.visible:
				errors.append("inventory panel close() should hide it")
		hud.free()

	# --- Scène du canyon --------------------------------------------------------------
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var campfire := world.get_node_or_null("Campfire")
	if campfire == null:
		errors.append("canyon_playground should contain a Campfire")
	var signpost := world.get_node_or_null("Signpost")
	if signpost == null:
		errors.append("canyon_playground should contain a Signpost")
	var wood_spawner := world.get_node_or_null("WoodCollectibles")
	if wood_spawner == null or wood_spawner.get_child_count() < 1:
		errors.append("canyon_playground should spawn wood collectibles")
	if campfire != null and signpost != null:
		var landscape := world.get_node("Landscape")
		var ground_fire: float = landscape.terrain_height_at(campfire.global_position.x, campfire.global_position.z)
		var ground_sign: float = landscape.terrain_height_at(signpost.global_position.x, signpost.global_position.z)
		if absf(campfire.global_position.y - ground_fire) > 0.01:
			errors.append("campfire flottant/enterré : y=%f sol=%f" % [campfire.global_position.y, ground_fire])
		if absf(signpost.global_position.y - ground_sign) > 0.01:
			errors.append("signpost flottant/enterré : y=%f sol=%f" % [signpost.global_position.y, ground_sign])
	world.free()

	var exit_code := 0
	if errors.is_empty():
		print("TEST_ENVIRONMENT_INTERACTION: PASS")
	else:
		exit_code = 1
		for e in errors:
			printerr("TEST_ENVIRONMENT_INTERACTION FAIL: " + e)
	quit(exit_code)
