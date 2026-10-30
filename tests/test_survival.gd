extends SceneTree
## Survie : faim/soif décroissent, boire/manger restaure, pénalités d'endurance.

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
	var survival := _ensure("SurvivalManager", "res://scripts/autoload/survival_manager.gd")
	await process_frame
	inventory.call("clear_for_test")
	survival.call("clear_for_test")
	survival.set("hunger_drain", 0.1)
	survival.set("thirst_drain", 0.2)

	# --- Décroissance et restauration ------------------------------------------------
	if absf(float(survival.call("get_hunger")) - 1.0) > 0.001 or absf(float(survival.call("get_thirst")) - 1.0) > 0.001:
		errors.append("faim et soif doivent démarrer pleines")
	await process_frame
	await process_frame
	if float(survival.call("get_hunger")) >= 1.0 or float(survival.call("get_thirst")) >= 1.0:
		errors.append("faim et soif doivent décroître avec le temps")
	survival.call("eat", 0.5)
	survival.call("drink", 0.7)
	if float(survival.call("get_hunger")) > 1.0 or float(survival.call("get_thirst")) > 1.0:
		errors.append("manger/boire ne doit pas dépasser le maximum")

	# --- Pénalités d'endurance --------------------------------------------------------
	survival.call("clear_for_test")
	if absf(float(survival.call("stamina_regen_factor")) - 1.0) > 0.001:
		errors.append("jauges pleines : régénération normale")
	survival.set("_hunger", 0.0)
	if absf(float(survival.call("stamina_regen_factor")) - 0.6) > 0.001:
		errors.append("faim vide : facteur 0.6 attendu, reçu %f" % float(survival.call("stamina_regen_factor")))
	survival.set("_thirst", 0.0)
	if float(survival.call("stamina_regen_factor")) > 0.4001:
		errors.append("les deux vides : facteur >= 0.4 attendu (plancher), reçu %f" % float(survival.call("stamina_regen_factor")))
	if survival.call("can_sprint"):
		errors.append("faim ET soif vides : la course doit être bloquée")
	survival.set("_hunger", 0.5)
	if not survival.call("can_sprint"):
		errors.append("faim restaurée : la course doit redevenir possible")

	# --- Source d'eau dans le canyon ---------------------------------------------------
	survival.call("clear_for_test")
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in range(10):
		await process_frame
	var water := world.get_node_or_null("WaterSource") as Node
	if water == null:
		errors.append("canyon doit contenir une source d'eau")
	else:
		if water.get_prompt() != "ACTION_DRINK":
			errors.append("la source doit proposer ACTION_DRINK, reçu %s" % water.get_prompt())
		survival.set("_thirst", 0.3)
		water.call("interact", world.get_node("Player"))
		await process_frame
		if float(survival.call("get_thirst")) < 0.6:
			errors.append("boire doit restaurer la soif, reçu %f" % float(survival.call("get_thirst")))
		if water.can_interact():
			errors.append("après avoir bu, la source doit se remplir à nouveau (can_interact false)")
		water.set("_refill_left", 0.0)
		if not water.can_interact():
			errors.append("après le remplissage, la source doit redevenir buvable")
	world.free()

	# --- Manger depuis le Sac (bouton du journal) ---------------------------------------
	var journal: GDScript = load("res://scripts/ui/journal_panel.gd")
	if not journal.EDIBLE.has("item_cooked_meat"):
		errors.append("la viande cuite doit être comestible depuis le Sac")
	if float(journal.EDIBLE.get("item_cooked_meat", 0.0)) <= float(journal.EDIBLE.get("item_raw_meat", 99.0)):
		errors.append("la viande cuite doit nourrir davantage que la crue")

	var exit_code := 0
	if errors.is_empty():
		print("TEST_SURVIVAL: PASS")
	else:
		exit_code = 1
		for e in errors:
			printerr("TEST_SURVIVAL FAIL: " + e)
	quit(exit_code)
