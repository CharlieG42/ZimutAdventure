extends SceneTree
## Autel des reliques (bénédictions) et réglages du joueur.

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

	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var player := world.get_node("Player") as Node3D
	var altars := world.get_tree().get_nodes_in_group("altar")
	_check(altars.size() == 1, "un autel près du départ")
	var altar: Node = altars[0]
	var start: Vector3 = exploration.call("get_site", "start")["pos"]
	_check((altar as Node3D).global_position.distance_to(start) < 12.0, "autel proche du panneau")

	altar.call("interact", player)
	_check(int(exploration.get("blessings")) == 0, "sans relique : rien")
	_check(float(exploration.call("drain_factor")) == 1.0, "pas d'endurance au départ")

	inventory.call("add_item", "item_relic", 3)
	altar.call("interact", player)
	_check(int(exploration.get("blessings")) == 1 and inventory.call("count_of", "item_relic") == 2, "1re offrande : relique consommée")
	_check(float(exploration.call("drain_factor")) < 1.0, "endurance : faim et soif ralenties")
	_check(not bool(exploration.call("travel_is_free")), "voyage encore payant")
	_check(int(progression.call("get_stat", "stat_blessings")) == 1, "stat_blessings")

	altar.call("interact", player)
	_check(bool(exploration.call("travel_is_free")), "2e offrande : voyage gratuit")
	var before := float(progression.call("bonus_loot_chance"))
	altar.call("interact", player)
	_check(float(progression.call("bonus_loot_chance")) > before, "3e offrande : fortune")
	_check(String(altar.call("get_prompt")) == "ACTION_ALTAR_FULL", "autel comblé")
	inventory.call("add_item", "item_relic", 1)
	altar.call("interact", player)
	_check(inventory.call("count_of", "item_relic") == 1 and int(exploration.get("blessings")) == 3, "pas de 4e offrande")

	# Voyage gratuit : aucune dépense, même affamé.
	progression.call("add_xp", 100000)
	survival.call("consume", 1.0, 1.0)
	_check(String(exploration.call("can_travel", "start")) == "", "voyage possible affamé une fois béni")

	# Réglages.
	var settings := root.get_node("GameSettings")
	var guard := root.get_node("PerformanceGuard")
	var ambience := root.get_node("Ambience")
	settings.call("set_music", false)
	_check(not bool(ambience.get("music_enabled")), "musique coupée par les réglages")
	settings.call("set_music", true)
	settings.call("set_quality", "low")
	_check(int(guard.get("level")) == 2 and String(guard.get("mode")) == "low", "qualité basse forcée")
	settings.call("set_quality", "high")
	_check(int(guard.get("level")) == 0, "qualité haute")
	settings.call("set_quality", "n'importe quoi")
	_check(String(settings.get("quality")) == "auto", "valeur inconnue : automatique")
	settings.call("set_volume", 0.5)
	var master := AudioServer.get_bus_index("Master")
	_check(absf(AudioServer.get_bus_volume_db(master) - linear_to_db(0.5)) < 0.1, "volume général appliqué")
	settings.call("set_volume", 0.0)
	_check(AudioServer.is_bus_mute(master), "volume 0 : muet")
	settings.call("set_volume", 1.0)

	# Onglet Réglages du journal.
	var journal := world.find_child("JournalPanel", true, false)
	if journal == null:
		for node in world.find_children("*", "PanelContainer", true, false):
			if node.get_script() != null and String(node.get_script().resource_path).ends_with("journal_panel.gd"):
				journal = node
	_check(journal != null, "journal trouvé")
	if journal != null:
		var tabs: TabContainer = journal.get("_tabs")
		_check(tabs.get_tab_count() == 4, "quatre onglets dont Réglages (%d)" % tabs.get_tab_count())

	world.queue_free()
	await process_frame
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
