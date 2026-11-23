extends SceneTree
## Ranch : rappel du chien au sifflet, enclos interactif (rassembler / libérer),
## niveaux d'enclos (capacité, taille, coût, persistance, place requise).

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _animal(scene: PackedScene, species: String, pos: Vector3, world: Node) -> Node:
	var animal = scene.instantiate()
	animal.species = species
	animal.position = pos
	world.add_child(animal)
	await process_frame
	animal.tame()
	return animal

func _initialize() -> void:
	await process_frame
	var inventory := root.get_node("Inventory")
	var progression := root.get_node("Progression")
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
	progression.call("clear_for_test", true)
	progression.call("add_xp", 100000)
	for existing in get_nodes_in_group("domestic"):
		existing.remove_from_group("tamed")
		existing.queue_free()
	await process_frame
	var scene := load("res://scenes/world/domestic_animal.tscn") as PackedScene

	# --- Chien : sifflet ---------------------------------------------------------------
	var dog = await _animal(scene, "dog", player.global_position + Vector3(30, 2, 0), world)
	dog.following = false
	_check(bool(dog.call("call_to_player", player)), "le chien répond au sifflet")
	_check(dog.following, "le chien se remet à suivre le joueur")
	dog.following = false
	_check(player.call("whistle"), "le joueur siffle : le chien vient")
	_check(dog.following, "le sifflet réactive le suivi")
	dog.global_position = player.global_position + Vector3(400, 2, 0)
	_check(not bool(dog.call("call_to_player", player)), "trop loin : le chien n'entend pas")
	dog.global_position = player.global_position + Vector3(30, 2, 0)
	var hud := world.get_node("HUD")
	hud.call("_refresh_whistle_button")
	_check(hud.get("whistle_button").visible, "bouton Siffler visible avec un chien seul")

	# --- Enclos : rassembler ---------------------------------------------------------------
	var origin: Vector3 = player.global_position + Vector3(14, 0, 14)
	_check(spawner.call("place", "building_pen", origin, 0.0) == "", "enclos posé")
	var pen: Node = get_nodes_in_group("pens")[0]
	_check(pen is Interactable and pen.get("level") == 1, "enclos interactif, niveau 1")
	_check(pen.call("get_prompt") == "ACTION_PEN_EMPTY", "enclos vide : rien à rassembler")
	var herd: Array = []
	for i in 4:
		herd.append(await _animal(scene, ["cow", "sheep", "goat", "chicken"][i], origin + Vector3(-16 + i * 2, 2, 55), world))
	_check(herd.all(func(a): return not a.penned), "bêtes éloignées : en liberté")
	_check(pen.call("get_prompt") == "ACTION_HERD" and pen.call("get_prompt_args") == [4], "invite : rassembler 4 bêtes")
	pen.call("_on_interact", player)
	_check(herd.all(func(a): return a.is_on_route()), "les 4 bêtes se mettent en route")
	for i in 2400:
		await physics_frame
		if herd.all(func(a): return a.penned):
			break
	_check(herd.all(func(a): return a.penned and pen.call("contains", a.global_position)), "les bêtes arrivent dans l'enclos")
	_check(pen.call("get_occupants").size() == 4, "4 occupants")
	_check(pen.call("get_prompt") == "ACTION_RELEASE" and pen.call("get_prompt_args") == [4], "invite : libérer 4 bêtes")

	# --- Libérer ---------------------------------------------------------------------------------
	pen.call("_on_interact", player)
	_check(herd.all(func(a): return not a.penned), "libérées : plus en enclos")
	# On relève chaque bête à l'instant où elle finit son trajet de sortie.
	var exits := {}
	for i in 2400:
		await physics_frame
		for a in herd:
			if not exits.has(a) and not a.is_on_route():
				exits[a] = pen.call("contains", a.global_position)
		if exits.size() == herd.size():
			break
	_check(exits.size() == herd.size() and not exits.values().has(true), "les bêtes sortent de l'enclos")
	_check(pen.call("get_occupants").is_empty(), "enclos vidé (aucune bête marquée en enclos)")

	# --- Capacité et niveaux -----------------------------------------------------------------------
	_check(pen.call("capacity") == 6 and is_equal_approx(pen.call("half"), 4.5), "niveau 1 : 6 places")
	var crowd: Array = []
	for i in 8:
		crowd.append(await _animal(scene, "chicken", origin + Vector3(-10 + i * 0.5, 2, 55), world))
	pen.call("release_all")
	var sent: int = pen.call("start_herd")
	_check(sent == 6, "seules 6 bêtes sur 8 sont envoyées (%d)" % sent)
	inventory.call("clear_for_test")
	_check(pen.call("upgrade") == "TOAST_UPGRADE_MISSING", "amélioration sans matériaux : refus")
	inventory.call("add_item", "item_wood", 40)
	inventory.call("add_item", "item_stone", 10)
	inventory.call("add_item", "item_pelt", 3)
	var panel := world.get_node("HUD/Overlay/BuildPanel")
	panel.call("_on_focus_changed", pen)
	_check(panel.get("_upgrade").visible, "bouton Améliorer visible sur l'enclos")
	_check(pen.call("upgrade") == "", "enclos niveau 2")
	_check(pen.get("level") == 2 and pen.call("capacity") == 10 and pen.call("half") > 6.0, "niveau 2 : 10 places, plus grand")
	_check(int(inventory.call("count_of", "item_wood")) == 30 and int(inventory.call("count_of", "item_stone")) == 8, "coût du niveau 2")
	_check(pen.call("upgrade") == "", "enclos niveau 3")
	_check(pen.call("capacity") == 16 and pen.call("upgrade") == "TOAST_MAX_LEVEL", "niveau 3 : 16 places, maximum")
	_check(pen.call("get_state").get("level") == 3, "niveau sauvegardé")
	var copy = load("res://scripts/world/pen.gd").create()
	copy.call("apply_state", {"level": 3})
	world.add_child(copy)
	copy.position = origin + Vector3(60, 0, 0)
	await process_frame
	_check(copy.get("level") == 3 and copy.call("capacity") == 16, "niveau restauré au chargement")

	# --- Place requise ------------------------------------------------------------------------------
	var small = load("res://scripts/world/pen.gd").create()
	world.add_child(small)
	small.position = origin + Vector3(-60, 0, 0)
	await process_frame
	var obstacle: Node3D = load("res://scripts/world/placed_structure.gd").create("camp_bed")
	world.add_child(obstacle)
	obstacle.position = small.position + Vector3(5.5, 0, 0)
	await process_frame
	_check(small.call("upgrade") == "TOAST_UPGRADE_NO_ROOM", "construction voisine : pas d'agrandissement")

	print("TEST_RANCH: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
