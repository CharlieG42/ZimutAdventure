extends SceneTree
## Prédateurs : santé du joueur, apparitions nocturnes, morsures, hache et arc, feu, chien, bétail.

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
	var clock := root.get_node("DayNightCycle")
	var quests := root.get_node("QuestManager")
	inventory.call("clear_for_test")
	quests.call("clear_for_test")
	progression.call("clear_for_test", true)
	survival.call("clear_for_test")

	# --- Santé -----------------------------------------------------------------------------
	_check(is_equal_approx(float(survival.call("get_health")), 1.0), "santé pleine au départ")
	survival.call("damage", 0.3)
	_check(is_equal_approx(float(survival.call("get_health")), 0.7), "dégâts retirés")
	survival.call("heal", 0.2)
	_check(is_equal_approx(float(survival.call("get_health")), 0.9), "soin ajouté")
	survival.call("heal", 5.0)
	_check(is_equal_approx(float(survival.call("get_health")), 1.0), "santé plafonnée à 1")
	inventory.call("add_item", "armor_fur_cloak", 1)
	survival.call("damage", 0.2)
	_check(absf(float(survival.call("get_health")) - 0.87) < 0.001, "la cape réduit les dégâts de 35 %")
	inventory.call("clear_for_test")
	survival.call("clear_for_test")

	# --- Plan des apparitions --------------------------------------------------------------------
	var spawner_script = load("res://scripts/world/predator_spawner.gd")
	var pred_script = load("res://scripts/world/predator.gd")
	_check(spawner_script.plan("night", 1)["species"] == "", "niveau 1 : nuit paisible")
	_check(spawner_script.plan("night", 2)["species"] == "coyote", "niveau 2 : coyotes la nuit")
	_check(spawner_script.plan("night", 4)["species"] == "wolf", "niveau 4 : loups la nuit")
	_check(int(spawner_script.plan("night", 20)["count"]) == 3, "population plafonnée à 3")
	_check(spawner_script.plan("day", 10)["species"] == "", "le jour : personne")
	_check(spawner_script.plan("dusk", 3)["species"] == "coyote" and int(spawner_script.plan("dusk", 3)["count"]) == 1, "crépuscule : un coyote")

	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var player := world.get_node("Player") as CharacterBody3D
	world.get_node("Livestock").call("disable_saving_for_test")
	world.get_node("Structures").call("disable_saving_for_test")
	var spawner := world.get_node("Predators")
	_check(not bool(spawner.get("enabled")), "headless : pas de rôdeurs par défaut")
	inventory.call("clear_for_test")
	survival.call("clear_for_test")
	progression.call("clear_for_test", true)
	progression.call("add_xp", 100000)
	clock.set("enabled", false)

	# --- Apparition et retraite -----------------------------------------------------------------------
	spawner.call("enable_for_test")
	clock.call("set_hour", 23.0)
	spawner.call("update_population")
	_check(get_nodes_in_group("predators").size() == 1, "un rôdeur apparaît la nuit")
	var first: Node3D = get_nodes_in_group("predators")[0]
	_check(first.species == "wolf" and first.global_position.distance_to(player.global_position) > 30.0, "loup, loin du joueur")
	clock.call("set_hour", 10.0)
	spawner.call("update_population")
	_check(bool(first.get("_retreating")), "au jour, le rôdeur se retire")
	first.queue_free()
	await process_frame
	spawner.set("enabled", false)

	# --- Morsure ---------------------------------------------------------------------------------------------
	var anchor := player.global_position
	var coyote = pred_script.new_for("coyote")
	coyote.position = anchor + Vector3(7, 1, 0)
	world.add_child(coyote)
	for i in 400:
		await physics_frame
	_check(float(survival.call("get_health")) < 1.0, "le coyote charge et mord le joueur")
	_check(float(world.get_node("HUD/Overlay/Vitals").call("get_value", "health")) < 1.0, "la jauge de santé baisse")
	# --- Hache -----------------------------------------------------------------------------------------------
	inventory.call("add_item", "tool_stone_axe", 1)
	inventory.call("equip", "tool_stone_axe")
	var wolf = pred_script.new_for("wolf")
	wolf.position = player.global_position - player.global_transform.basis.z * 1.6 + Vector3(0, 1, 0)
	world.add_child(wolf)
	await physics_frame
	player.set("_melee_cooldown", 0.0)
	_check(bool(player.call("try_melee")), "coup de hache sur le loup")
	player.set("_melee_cooldown", 0.0)
	var wolf_hp: int = wolf.get("_hp")
	_check(wolf_hp == 2, "la hache inflige 2 dégâts")
	player.call("try_melee")
	await process_frame
	_check(inventory.call("count_of", "item_pelt") == 2, "deux peaux de loup")
	_check(int(progression.call("get_stat", "stat_predators")) == 1, "compteur de prédateurs")
	coyote.queue_free()
	# --- Arc ---------------------------------------------------------------------------------------------------
	var coyote2 = pred_script.new_for("coyote")
	coyote2.position = anchor + Vector3(30, 1, 30)
	world.add_child(coyote2)
	await physics_frame
	coyote2.call("take_arrow_hit", anchor)
	await process_frame
	_check(int(progression.call("get_stat", "stat_predators")) == 2, "une flèche abat un coyote")
	_check(inventory.call("count_of", "item_pelt") == 3, "peau de coyote")

	# --- Feu de camp ---------------------------------------------------------------------------------------------------
	var fire := (load("res://scenes/interaction/campfire.tscn") as PackedScene).instantiate()
	fire.position = anchor + Vector3(-60, 0, -60)
	world.add_child(fire)
	await process_frame
	fire.set("_stage", 3)
	var scared = pred_script.new_for("wolf")
	scared.position = fire.position + Vector3(4, 1, 0)
	world.add_child(scared)
	var d0: float = scared.global_position.distance_to(fire.global_position)
	for i in 90:
		await physics_frame
	_check(scared.global_position.distance_to(fire.global_position) > d0 + 2.0, "le loup fuit le feu allumé")
	scared.queue_free()
	fire.queue_free()

	# --- Chien gardien ---------------------------------------------------------------------------------------------------
	var animal_scene := load("res://scenes/world/domestic_animal.tscn") as PackedScene
	var far := anchor + Vector3(70, 0, -70)
	var dog = animal_scene.instantiate()
	dog.species = "dog"
	dog.position = far + Vector3(0, 1, 0)
	world.add_child(dog)
	await process_frame
	dog.tame()
	dog.following = false
	var guarded = pred_script.new_for("wolf")
	guarded.position = far + Vector3(2, 1, 0)
	world.add_child(guarded)
	for i in 10:
		await physics_frame
	_check(int(guarded.get("_hp")) < 4, "le chien mord le loup")
	guarded.queue_free()
	dog.queue_free()

	# --- Bétail laissé dehors ---------------------------------------------------------------------------------------------------
	var cow = animal_scene.instantiate()
	cow.species = "cow"
	var field := anchor + Vector3(-70, 0, 70)
	cow.position = field + Vector3(0, 1, 0)
	world.add_child(cow)
	await process_frame
	cow.tame()
	var ready_before: float = cow.ready_at
	var raider = pred_script.new_for("wolf")
	raider.position = field + Vector3(6, 1, 0)
	world.add_child(raider)
	for i in 300:
		await physics_frame
	_check(cow.ready_at > ready_before + 60.0, "le loup effraie la vache : production retardée")
	raider.queue_free()
	cow.queue_free()

	# --- Défaite et soins -------------------------------------------------------------------------------------------------------
	player.global_position = anchor + Vector3(40, 3, 40)
	survival.call("damage", 2.0)
	await process_frame
	var flat := Vector2(player.global_position.x - anchor.x, player.global_position.z - anchor.z)
	_check(flat.length() < 3.0, "terrassé : retour au camp de départ")
	_check(is_equal_approx(float(survival.call("get_health")), 0.5), "réveil à demi-santé")
	var recipe_ok: bool = load("res://scripts/autoload/craft_manager.gd").new().RECIPES.has("armor_fur_cloak")
	_check(recipe_ok, "recette de la cape")
	for id in ["quest_predator", "quest_cloak"]:
		_check(quests.QUESTS.has(id), "quête %s" % id)

	print("TEST_PREDATORS: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
