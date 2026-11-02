extends SceneTree
## Exploration : brouillard de la carte, sites à découvrir, coffres au trésor, voyage rapide.

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
	var exploration := root.get_node("Exploration")
	inventory.call("clear_for_test")
	progression.call("clear_for_test", true)
	survival.call("clear_for_test")
	exploration.call("clear_for_test")

	# Brouillard.
	_check(int(exploration.call("revealed_count")) == 0, "carte entièrement voilée au départ")
	exploration.call("reveal", 0.0, 0.0, 40.0)
	var count := int(exploration.call("revealed_count"))
	_check(count > 4, "révéler dévoile des cases (%d)" % count)
	_check(bool(exploration.call("is_revealed", 0.0, 0.0)), "le point révélé est visible")
	_check(not bool(exploration.call("is_revealed", 200.0, 200.0)), "un point lointain reste voilé")

	# Sites : monde complet.
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var player := world.get_node("Player") as CharacterBody3D
	var sites: Dictionary = exploration.call("get_sites")
	_check(sites.size() >= 4, "des sites sont enregistrés (%d)" % sites.size())
	_check(bool(exploration.call("is_discovered", "start")), "le panneau de départ est connu")
	var site_nodes := world.get_tree().get_nodes_in_group("sites")
	_check(site_nodes.size() == sites.size() - 1, "un décor par site")
	var chests := world.get_tree().get_nodes_in_group("treasures")
	_check(chests.size() == site_nodes.size(), "un coffre au trésor par site")

	# Déterminisme du plan.
	var spawner := world.get_node("Sites")
	var plan_a: Array = spawner.call("plan_sites", 4242, 6, Vector3.ZERO)
	var plan_b: Array = spawner.call("plan_sites", 4242, 6, Vector3.ZERO)
	_check(plan_a.size() == plan_b.size() and plan_a.size() > 0 and plan_a[0]["x"] == plan_b[0]["x"], "plan de sites déterministe")

	# Découverte à l'approche.
	var target_id := ""
	for site_id in sites:
		if site_id != "start":
			target_id = site_id
			break
	var target: Vector3 = sites[target_id]["pos"]
	_check(not bool(exploration.call("is_discovered", target_id)), "site lointain non découvert")
	player.global_position = target + Vector3(3, 2, 3)
	await create_timer(0.8).timeout
	_check(bool(exploration.call("is_discovered", target_id)), "approcher découvre le site")
	_check(int(progression.call("get_stat", "stat_discovered")) == 1, "stat_discovered incrémentée")
	_check(bool(exploration.call("is_revealed", target.x, target.z)), "la zone autour du site est dévoilée")
	_check(not bool(exploration.call("discover", target_id)), "découverte unique")

	# Coffre au trésor.
	var chest: Node = null
	for node in chests:
		if String(node.get("site_id")) == target_id:
			chest = node
	_check(chest != null, "coffre du site trouvé")
	inventory.call("clear_for_test")
	chest.call("interact", player)
	_check(inventory.call("count_of", "item_relic") == 1, "le coffre livre une relique")
	_check(not bool(chest.call("can_interact")), "coffre à usage unique")
	_check(bool(exploration.call("is_looted", target_id)), "coffre marqué comme pillé")

	# Voyage rapide.
	_check(String(exploration.call("can_travel", "inconnu")) == "TOAST_TRAVEL_UNKNOWN", "voyage vers un lieu inconnu refusé")
	progression.call("clear_for_test", true)
	var low := String(exploration.call("can_travel", target_id))
	_check(low == "TOAST_TRAVEL_LEVEL", "voyage refusé au niveau 1 (%s)" % low)
	progression.call("clear_for_test", true)
	progression.call("add_xp", 100000)
	survival.call("clear_for_test")
	player.global_position = Vector3(0, 12, 0)
	var hunger_before := float(survival.call("get_hunger"))
	var error := String(exploration.call("fast_travel", target_id, player))
	_check(error == "", "voyage accepté (%s)" % error)
	_check(Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() < 6.0, "le joueur arrive au site")
	_check(float(survival.call("get_hunger")) < hunger_before, "le voyage coûte de la faim")
	survival.call("consume", 1.0, 1.0)
	_check(String(exploration.call("can_travel", target_id)) == "TOAST_TRAVEL_TIRED", "voyage refusé affamé")

	world.queue_free()
	await process_frame
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
