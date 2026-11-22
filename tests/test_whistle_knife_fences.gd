extends SceneTree
## Sifflet du cheval apprivoisé, couteau fabricable (plus de viande) et palissades déplaçables.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var inventory: Node = root.get_node("Inventory")
	var craft: Node = root.get_node("CraftManager")
	inventory.call("clear_for_test")
	var host := Node3D.new()
	root.add_child(host)

	# --- Couteau -------------------------------------------------------------------------
	if not CraftManager_has(craft, "tool_knife"):
		errors.append("recette tool_knife absente")
	inventory.call("add_item", "item_stone", 2)
	inventory.call("add_item", "item_wood", 1)
	if not bool(craft.call("can_craft", "tool_knife")):
		errors.append("couteau fabricable avec 2 pierres + 1 bois")
	craft.call("craft", "tool_knife")
	if int(inventory.call("count_of", "tool_knife")) != 1:
		errors.append("le couteau doit arriver dans le sac")
	if tr("CRAFT_KNIFE") == "CRAFT_KNIFE" or tr("ITEM_TOOL_KNIFE") == "ITEM_TOOL_KNIFE":
		errors.append("traductions du couteau manquantes")
	var carcass: Node = load("res://scripts/world/carcass.gd").new()
	host.add_child(carcass)
	carcass.set("loot", {"item_raw_meat": 2})
	inventory.call("equip", "tool_knife")
	var meat_before := int(inventory.call("count_of", "item_raw_meat"))
	carcass.call("harvest")
	if int(inventory.call("count_of", "item_raw_meat")) - meat_before != 3:
		errors.append("couteau équipé : +1 viande au dépeçage")

	# --- Sifflet -------------------------------------------------------------------------
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	host.add_child(player)
	player.global_position = Vector3.ZERO
	var horse: Node3D = (load("res://scripts/world/domestic_animal.gd") as GDScript).new()
	horse.set("species", "horse")
	host.add_child(horse)
	horse.global_position = Vector3(30.0, 0.0, 0.0)
	await process_frame
	if bool(player.call("whistle")):
		errors.append("cheval sauvage : le sifflet ne doit rien appeler")
	horse.call("tame")
	if not bool(player.call("whistle")):
		errors.append("cheval apprivoisé : le sifflet doit l'appeler")
	if not bool(horse.get("summoned")):
		errors.append("le cheval doit être en route")
	horse.set("mounted", true)
	if bool(horse.call("call_to_player", player)):
		errors.append("un cheval monté ne répond pas")
	horse.set("mounted", false)
	horse.global_position = Vector3(500.0, 0.0, 0.0)
	if bool(horse.call("call_to_player", player)):
		errors.append("un cheval hors de portée n'entend pas")
	# Le HUD propose le bouton seulement avec un cheval apprivoisé.
	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	root.add_child(hud)
	await process_frame
	hud.call("_refresh_whistle_button")
	if not (hud.get("whistle_button") as Button).visible:
		errors.append("bouton Siffler attendu avec un cheval apprivoisé")

	# --- Palissade déplaçable ----------------------------------------------------------------
	var spawner: Node = load("res://scripts/world/structure_spawner.gd").new()
	spawner.add_to_group("structure_spawner")
	host.add_child(spawner)
	await process_frame
	inventory.call("add_item", "item_wood", 20)
	inventory.call("add_item", "item_stone", 20)
	spawner.call("place", "building_palisade", Vector3(0.0, 0.0, -8.0), 0.0)
	var fence: Node3D = null
	for n in get_nodes_in_group("palisades"):
		fence = n
	if fence == null:
		errors.append("palissade posée introuvable")
	else:
		var handle := fence.get_node_or_null("Handle")
		if handle == null:
			errors.append("poignée de visée absente")
		elif spawner.call("movable_for", handle) != fence:
			errors.append("la palissade visée doit être déplaçable")

	if errors.is_empty():
		print("TEST_WHISTLE_KNIFE_FENCES: PASS")
		quit(0)
	else:
		for e in errors: printerr("TEST_WHISTLE_KNIFE_FENCES FAIL: " + e)
		quit(1)

func CraftManager_has(craft: Node, id: String) -> bool:
	return (craft.get("RECIPES") as Dictionary).has(id)
