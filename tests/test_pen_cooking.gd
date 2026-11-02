extends SceneTree
## Phase 3 : arrosoir et céréales, cuisine au feu, lit en laine, enclos du bétail, quêtes liées.

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
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var player := world.get_node("Player") as CharacterBody3D
	player.add_to_group("player")
	var spawner := world.get_node("Structures")
	spawner.call("disable_saving_for_test")
	world.get_node("Livestock").call("disable_saving_for_test")
	inventory.call("clear_for_test")
	quests.call("clear_for_test")
	progression.call("clear_for_test", true)

	# --- Niveaux requis ----------------------------------------------------------------
	for recipe_id in ["tool_watering_can", "furniture_wool_bed", "building_pen"]:
		_check(not bool(craft.call("meets_level", recipe_id)), "%s verrouillé au niveau 1" % recipe_id)
	progression.call("add_xp", 100000)
	for recipe_id in ["tool_watering_can", "furniture_wool_bed", "building_pen"]:
		_check(bool(craft.call("meets_level", recipe_id)), "%s débloqué" % recipe_id)

	# --- Arrosage et céréales ---------------------------------------------------------------
	var plot: Node3D = load("res://scripts/world/farm_plot.gd").create()
	plot.position = player.global_position + Vector3(0, 0, -6)
	world.add_child(plot)
	await process_frame
	inventory.call("add_item", "tool_hoe", 1)
	inventory.call("add_item", "tool_watering_can", 1)
	inventory.call("add_item", "item_grain_seeds", 1)
	inventory.call("add_item", "item_seeds", 1)
	inventory.call("equip", "tool_hoe")
	plot.call("interact", player)
	_check(int(plot.call("get_stage")) == 1, "graines semées")
	_check(inventory.call("count_of", "item_grain_seeds") == 0 and inventory.call("count_of", "item_seeds") == 1, "les céréales sont semées en premier")
	_check(not bool(plot.call("can_interact")), "houe équipée : rien à faire sur une pousse")
	inventory.call("equip", "tool_watering_can")
	_check(bool(plot.call("can_interact")) and plot.call("get_prompt") == "ACTION_WATER", "arrosoir : arroser")
	plot.call("advance_time", 60.0)
	var before: float = plot.call("get_growth")
	plot.call("interact", player)
	_check(float(plot.call("get_growth")) > before + 0.3, "l'arrosage accélère la pousse")
	_check(not bool(plot.call("can_interact")), "une seule fois par culture")
	_check(int(progression.call("get_stat", "stat_watered")) == 1, "compteur d'arrosages")
	plot.call("advance_time", 60.0)
	_check(int(plot.call("get_stage")) == 2, "le blé mûrit plus vite que les légumes")
	var state: Dictionary = plot.call("get_state")
	_check(state.get("crop") == "item_grain_seeds", "culture sauvegardée")
	plot.call("interact", player)
	_check(inventory.call("count_of", "item_wheat") >= 3, "blé récolté")
	_check(int(progression.call("get_stat", "stat_grain")) == 1, "compteur de céréales")

	# --- Cuisine ------------------------------------------------------------------------------
	var fire := (load("res://scenes/interaction/campfire.tscn") as PackedScene).instantiate()
	fire.position = player.global_position + Vector3(5, 0, 5)
	world.add_child(fire)
	await process_frame
	fire.set("_stage", 4)
	inventory.call("clear_for_test")
	_check(fire.call("get_prompt") == "ACTION_REST", "feu plein et sac vide : se reposer")
	inventory.call("add_item", "item_egg", 1)
	_check(fire.call("get_prompt") == "ACTION_COOK", "œuf : cuisiner")
	fire.call("interact", player)
	_check(inventory.call("count_of", "item_boiled_egg") == 1 and inventory.call("count_of", "item_egg") == 0, "œuf cuit")
	inventory.call("add_item", "item_milk", 1)
	inventory.call("add_item", "item_vegetables", 2)
	fire.call("interact", player)
	_check(inventory.call("count_of", "item_soup") == 1, "soupe : lait + légumes")
	fire.call("interact", player)
	_check(inventory.call("count_of", "item_roast_vegetables") == 1, "légumes rôtis")
	inventory.call("add_item", "item_wheat", 2)
	fire.call("interact", player)
	_check(inventory.call("count_of", "item_bread") == 1, "pain : 2 blés")
	inventory.call("add_item", "item_raw_meat", 1)
	fire.call("interact", player)
	_check(inventory.call("count_of", "item_cooked_meat") == 1, "viande cuite toujours possible")
	_check(int(progression.call("get_stat", "stat_cooked")) == 5, "compteur de plats")

	# --- Lit en laine -----------------------------------------------------------------------------
	_check(spawner.call("is_placeable", "furniture_wool_bed"), "lit en laine posable")
	var clock := root.get_node_or_null("DayNightCycle")
	if clock != null:
		clock.call("set_hour", 12.0)
	var err: String = spawner.call("place", "furniture_wool_bed", player.global_position + Vector3(-8, 0, 8), 0.0)
	_check(err == "", "pose du lit en laine (%s)" % err)
	var bed: Node = null
	for node in get_nodes_in_group("structures"):
		if node.get("kind") == "wool_bed":
			bed = node
	_check(bed != null and bed.call("get_prompt") == "ACTION_REST_BED", "lit en laine : repos de jour")
	if clock != null and bed != null:
		clock.call("set_hour", 22.0)
		_check(bed.call("get_prompt") == "ACTION_SLEEP", "lit en laine : dormir la nuit")
		bed.call("interact", player)
		_check(float(clock.get("hour")) < 12.0, "la nuit passe (réveil au matin)")

	# --- Enclos ------------------------------------------------------------------------------------------
	var animal_scene := load("res://scenes/world/domestic_animal.tscn") as PackedScene
	var origin: Vector3 = player.global_position + Vector3(12, 0, 12)
	var sheep = animal_scene.instantiate()
	sheep.species = "sheep"
	sheep.position = origin + Vector3(6, 2, 0)
	world.add_child(sheep)
	var dog = animal_scene.instantiate()
	dog.species = "dog"
	dog.position = origin + Vector3(7, 2, 0)
	world.add_child(dog)
	await process_frame
	sheep.tame()
	dog.tame()
	_check(not sheep.penned, "sans enclos : bête en liberté")
	err = spawner.call("place", "building_pen", origin, 0.0)
	_check(err == "", "pose de l'enclos (%s)" % err)
	var pen: Node = get_nodes_in_group("pens")[0]
	_check(sheep.penned and pen.call("contains", sheep.global_position), "le mouton emménage dans l'enclos")
	_check(not dog.penned, "le chien reste libre")
	_check(int(progression.call("get_stat", "stat_pens")) == 1, "compteur d'enclos")
	var seconds_free := float(sheep.PRODUCTS["sheep"]["seconds"])
	sheep.ready_at = 0.0
	inventory.call("add_item", "tool_sickle", 1)
	inventory.call("equip", "tool_sickle")
	sheep.interact_with(player)
	_check(sheep.ready_at - sheep.call("_now") < seconds_free * 0.7, "production plus rapide en enclos")
	for i in 240:
		await physics_frame
	_check(pen.call("contains", sheep.global_position), "le mouton reste dans l'enclos")
	var saved: Dictionary = sheep.call("get_state")
	_check(bool(saved.get("penned", false)), "enclos sauvegardé")
	# Une bête apprivoisée plus tard rejoint l'enclos.
	var cow = animal_scene.instantiate()
	cow.species = "cow"
	cow.position = origin + Vector3(10, 2, 3)
	world.add_child(cow)
	await process_frame
	cow.tame()
	_check(cow.penned, "une vache apprivoisée rejoint l'enclos")
	# Capacité.
	for i in 6:
		var extra = animal_scene.instantiate()
		extra.species = "chicken"
		extra.position = origin + Vector3(9, 2, i)
		world.add_child(extra)
		await process_frame
		extra.tame()
	_check(pen.call("get_occupants").size() == 6, "capacité limitée à 6")

	# --- Quêtes -----------------------------------------------------------------------------------------------
	for id in ["quest_cook", "quest_water", "quest_grain", "quest_wool_bed", "quest_pen"]:
		_check(quests.QUESTS.has(id), "quête %s déclarée" % id)
	_check(quests.QUESTS["quest_grain"]["requires"] == "quest_water", "blé après arrosage")

	print("TEST_PEN_COOKING: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
