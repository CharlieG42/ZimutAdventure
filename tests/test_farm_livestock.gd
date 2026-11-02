extends SceneTree
## Ferme (parcelle, houe, graines), élevage (apprivoisement, produits), cheval (monture), chien.

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
	quests.call("clear_for_test")
	progression.call("clear_for_test", true)
	progression.call("add_xp", 100000)

	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var player := world.get_node("Player") as CharacterBody3D
	player.add_to_group("player")
	world.get_node("Structures").call("disable_saving_for_test")
	world.get_node("Livestock").call("disable_saving_for_test")
	inventory.call("clear_for_test")
	quests.call("clear_for_test")
	progression.call("clear_for_test", true)
	progression.call("add_xp", 100000)

	# --- Recettes : houe et parcelle verrouillées par niveau ----------------------------
	progression.call("clear_for_test", true)
	_check(not bool(craft.call("meets_level", "tool_hoe")), "houe verrouillée au niveau 1")
	progression.call("add_xp", 100000)
	_check(bool(craft.call("meets_level", "building_farm_plot")), "parcelle débloquée au niveau max")

	# --- Parcelle ---------------------------------------------------------------------------
	var plot: Node3D = load("res://scripts/world/farm_plot.gd").create()
	plot.position = player.global_position + Vector3(0, 0, -6)
	world.add_child(plot)
	await process_frame
	inventory.call("add_item", "tool_hoe", 1)
	inventory.call("add_item", "tool_sickle", 1)
	inventory.call("equip", "tool_sickle")
	_check(plot.call("get_prompt") == "ACTION_NEED_HOE", "sans houe équipée : houe requise")
	inventory.call("equip", "tool_hoe")
	_check(plot.call("get_prompt") == "ACTION_NEED_SEEDS", "sans graines : graines requises")
	plot.call("interact", player)
	_check(int(plot.call("get_stage")) == 0, "rien ne pousse sans graines")
	inventory.call("add_item", "item_seeds", 2)
	_check(plot.call("get_prompt") == "ACTION_PLANT", "avec houe et graines : semer")
	plot.call("interact", player)
	_check(int(plot.call("get_stage")) == 1, "la graine est semée")
	_check(inventory.call("count_of", "item_seeds") == 1, "une graine consommée")
	_check(not bool(plot.call("can_interact")), "parcelle en croissance : pas d'invite")
	plot.call("advance_time", 180.0 * 0.5)
	_check(float(plot.call("get_growth")) > 0.4 and float(plot.call("get_growth")) < 0.6, "croissance à mi-chemin")
	plot.call("advance_time", 180.0)
	_check(int(plot.call("get_stage")) == 2, "la récolte est mûre")
	_check(plot.call("get_prompt") == "ACTION_HARVEST", "invite de récolte")
	plot.call("interact", player)
	_check(inventory.call("count_of", "item_vegetables") >= 2, "légumes récoltés")
	_check(inventory.call("count_of", "item_seeds") >= 2, "graines rendues")
	_check(int(plot.call("get_stage")) == 0, "parcelle libre après récolte")
	_check(int(progression.call("get_stat", "stat_harvests")) == 1, "compteur de récoltes")
	var state: Dictionary = plot.call("get_state")
	_check(float(state["planted_at"]) < 0.0, "état sauvegardable (vide)")

	# --- Pose via le gestionnaire de constructions ----------------------------------------------
	var spawner := world.get_node("Structures")
	_check(bool(spawner.call("is_placeable", "building_farm_plot")), "la parcelle est posable")
	var err: String = spawner.call("place", "building_farm_plot", player.global_position + Vector3(8, 0, 8), 0.0)
	_check(err == "" or err == "TOAST_TOO_STEEP", "pose de parcelle (%s)" % err)

	# --- Bétail ------------------------------------------------------------------------------------
	var livestock := world.get_node("Livestock")
	_check((livestock.call("get_animals") as Array).size() == 19, "19 animaux domestiques répartis")
	var animal_scene := load("res://scenes/world/domestic_animal.tscn") as PackedScene
	var cow = animal_scene.instantiate()
	cow.species = "cow"
	cow.position = player.global_position + Vector3(3, 1, 3)
	world.add_child(cow)
	await process_frame
	inventory.call("clear_for_test")
	_check(cow.get_prompt_key() == "ACTION_NEED_FOOD", "vache : nourriture requise")
	cow.interact_with(player)
	_check(not cow.tamed, "sans nourriture, rien ne se passe")
	inventory.call("add_item", "item_vegetables", 5)
	_check(cow.get_prompt_key() == "ACTION_TAME", "vache : nourrir pour apprivoiser")
	cow.interact_with(player)
	cow.interact_with(player)
	_check(not cow.tamed and cow.trust == 2, "la confiance monte repas après repas")
	cow.interact_with(player)
	_check(cow.tamed, "troisième repas : apprivoisée")
	_check(inventory.call("count_of", "item_vegetables") == 2, "les repas consomment la nourriture")
	_check(not cow.can_interact_now(), "produit pas encore prêt : pas d'invite")
	cow.advance_time(300.0)
	_check(cow.is_product_ready() and cow.get_prompt_key() == "ACTION_MILK", "lait prêt : traire")
	cow.interact_with(player)
	_check(inventory.call("count_of", "item_milk") >= 2, "lait récolté")
	_check(not cow.is_product_ready(), "délai avant la prochaine traite")
	_check(int(progression.call("get_stat", "stat_tamed_livestock")) == 1, "compteur d'élevage")

	var sheep = animal_scene.instantiate()
	sheep.species = "sheep"
	sheep.position = player.global_position + Vector3(5, 1, 3)
	world.add_child(sheep)
	await process_frame
	sheep.tame()
	sheep.advance_time(400.0)
	inventory.call("add_item", "tool_sickle", 1)
	inventory.call("unequip")
	sheep.interact_with(player)
	_check(inventory.call("count_of", "item_wool") == 0, "tonte impossible sans serpette équipée")
	inventory.call("equip", "tool_sickle")
	sheep.interact_with(player)
	_check(inventory.call("count_of", "item_wool") >= 2, "laine récoltée avec la serpette")

	var hen = animal_scene.instantiate()
	hen.species = "chicken"
	hen.position = player.global_position + Vector3(2, 1, 5)
	world.add_child(hen)
	await process_frame
	inventory.call("add_item", "item_seeds", 4)
	hen.interact_with(player)
	hen.interact_with(player)
	_check(hen.tamed, "poule apprivoisée avec des graines (2 repas)")
	hen.advance_time(200.0)
	hen.interact_with(player)
	_check(inventory.call("count_of", "item_egg") >= 1, "œuf ramassé")
	_check(int(progression.call("get_stat", "stat_products")) >= 3, "trois produits récoltés")

	# --- Persistance (aller-retour d'état) ----------------------------------------------------------
	var saved: Dictionary = cow.get_state()
	_check(saved["species"] == "cow" and float(saved["ready_at"]) > 0.0, "état d'une bête apprivoisée sauvegardable")

	# --- Chien -------------------------------------------------------------------------------------------
	var dog = animal_scene.instantiate()
	dog.species = "dog"
	dog.position = player.global_position + Vector3(4, 1, -4)
	world.add_child(dog)
	await process_frame
	progression.call("clear_for_test", true)
	inventory.call("add_item", "item_raw_meat", 3)
	dog.interact_with(player)
	_check(not dog.tamed and inventory.call("count_of", "item_raw_meat") == 3, "chien : niveau 3 requis")
	progression.call("add_xp", 100000)
	dog.interact_with(player)
	dog.interact_with(player)
	_check(dog.tamed, "chien apprivoisé avec de la viande")
	_check(int(progression.call("get_stat", "stat_dog")) == 1, "compteur chien")
	_check(dog.get_prompt_key() == "ACTION_DOG_STAY", "chien : peut rester")
	dog.interact_with(player)
	_check(not dog.following and dog.get_prompt_key() == "ACTION_DOG_FOLLOW", "ordre : rester")
	dog.interact_with(player)
	_check(dog.following, "ordre : suivre")
	dog.global_position = player.global_position + Vector3(12, 0, 0)
	for i in 120:
		await physics_frame
	_check(dog.global_position.distance_to(player.global_position) < 11.0, "le chien se rapproche du joueur")

	# --- Cheval -------------------------------------------------------------------------------------------
	var horse = animal_scene.instantiate()
	horse.species = "horse"
	horse.position = player.global_position + Vector3(-4, 1, -4)
	world.add_child(horse)
	await process_frame
	progression.call("clear_for_test", true)
	inventory.call("add_item", "item_vegetables", 6)
	var veg_before := int(inventory.call("count_of", "item_vegetables"))
	horse.interact_with(player)
	_check(not horse.tamed and inventory.call("count_of", "item_vegetables") == veg_before, "cheval : niveau 5 requis")
	progression.call("add_xp", 100000)
	for i in 4:
		horse.interact_with(player)
	_check(horse.tamed and int(progression.call("get_stat", "stat_horse")) == 1, "cheval apprivoisé")
	_check(horse.get_prompt_key() == "ACTION_MOUNT", "cheval : monter")
	var walk_before: float = player.walk_speed
	horse.interact_with(player)
	_check(player.is_mounted() and horse.mounted, "le joueur est en selle")
	_check(root.get_node("InteractionManager").get("_forced") == horse.get("_interaction"), "cible forcée : descendre")
	horse.global_position = player.global_position + Vector3(9, 0, 9)
	for i in 3:
		await physics_frame
	_check(horse.global_position.distance_to(player.global_position) < 0.5, "la monture suit le joueur")
	_check(horse.get_prompt_key() == "ACTION_DISMOUNT", "en selle : descendre")
	horse.interact_with(player)
	_check(not player.is_mounted() and not horse.mounted, "le joueur descend")
	_check(horse.global_position.distance_to(player.global_position) > 0.8, "le cheval est posé à côté")
	_check(is_equal_approx(player.walk_speed, walk_before), "vitesse de base inchangée")

	# --- Quêtes de la ferme --------------------------------------------------------------------------------------
	quests.call("clear_for_test")
	progression.call("clear_for_test", true)
	for quest_id in ["quest_first_stone", "quest_builder", "quest_lumberjack", "quest_sickle", "quest_berries", "quest_hoe", "quest_plot"]:
		quests.call("set_state", quest_id, 2)
	quests.call("_unlock_available")
	_check("quest_harvest" in quests.call("get_active"), "la récolte se débloque après le potager")
	inventory.call("clear_for_test")
	inventory.call("add_item", "item_vegetables", 4)
	_check("quest_harvest" in quests.call("get_completed") and "quest_livestock" in quests.call("get_active"), "récolte -> élevage")
	progression.call("add_stat", "stat_tamed_livestock", 1)
	_check("quest_dairy" in quests.call("get_active") and "quest_horse" in quests.call("get_active"), "élevage -> produits et cheval")

	print("FAIL" if _failures > 0 else "PASS", " test_farm_livestock")
	quit(1 if _failures > 0 else 0)
