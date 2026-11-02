extends SceneTree
## Pêche : canne, étangs, touche et ferrage, poissons grillés.

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
	inventory.call("clear_for_test")
	progression.call("clear_for_test", true)
	_check(not bool(craft.call("meets_level", "tool_fishing_rod")), "canne verrouillée au niveau 1")
	progression.call("add_xp", 100000)
	_check(bool(craft.call("meets_level", "tool_fishing_rod")), "canne disponible ensuite")

	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var player := world.get_node("Player") as CharacterBody3D
	inventory.call("clear_for_test")
	progression.call("clear_for_test", true)
	progression.call("add_xp", 100000)
	var ponds := world.get_tree().get_nodes_in_group("fishing")
	_check(ponds.size() == 3, "trois étangs (%d)" % ponds.size())
	var pond: Node = ponds[0]
	_check(String(pond.call("get_prompt")) == "ACTION_FISH_NEED_ROD", "sans canne : invite à en fabriquer une")
	pond.call("interact", player)
	_check(int(pond.get("state")) == 0, "sans canne, pas de lancer")

	inventory.call("add_item", "tool_fishing_rod", 1)
	_check(String(pond.call("get_prompt")) == "ACTION_FISH_CAST", "avec canne : lancer")
	pond.call("interact", player)
	_check(int(pond.get("state")) == 1, "ligne lancée, en attente")
	pond.call("interact", player)
	_check(int(pond.get("state")) == 0 and inventory.call("count_of", "item_fish") == 0, "relever trop tôt : rien")

	pond.call("cast")
	pond.set("_timer", 0.01)
	await create_timer(0.3).timeout
	_check(int(pond.get("state")) == 2, "la touche arrive")
	_check(String(pond.call("get_prompt")) == "ACTION_FISH_STRIKE", "invite à ferrer")
	pond.call("interact", player)
	var fish := int(inventory.call("count_of", "item_fish")) + int(inventory.call("count_of", "item_fish_big"))
	_check(fish == 1, "poisson pris")
	_check(int(progression.call("get_stat", "stat_fished")) == 1, "stat_fished incrémentée")
	_check(int(pond.get("state")) == 0, "retour au repos")

	pond.call("cast")
	pond.set("_timer", 0.01)
	await create_timer(0.3).timeout
	pond.set("_timer", 0.01)
	await create_timer(0.3).timeout
	_check(int(pond.get("state")) == 0, "touche manquée : le poisson s'échappe")

	# Cuisson.
	var fire := world.get_node("Campfire")
	fire.call("apply_state", {"stage": 4})
	inventory.call("clear_for_test")
	inventory.call("add_item", "item_fish", 1)
	fire.call("interact", player)
	_check(inventory.call("count_of", "item_grilled_fish") == 1, "truite grillée")
	_check(int(progression.call("get_stat", "stat_fish_cooked")) == 1, "stat_fish_cooked")

	world.queue_free()
	await process_frame
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
