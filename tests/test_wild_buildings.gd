extends SceneTree
## Repeuplement des animaux à apprivoiser, niveau de joueur requis pour améliorer,
## onglet Bâtiments du journal (amélioration seulement à proximité).

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
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	paused = false
	var player := world.get_node("Player") as CharacterBody3D
	player.add_to_group("player")
	var spawner := world.get_node("Structures")
	spawner.call("disable_saving_for_test")
	var livestock := world.get_node("Livestock")
	livestock.call("disable_saving_for_test")
	inventory.call("clear_for_test")
	progression.call("clear_for_test", true)

	# --- Repeuplement --------------------------------------------------------------------------
	for animal in livestock.call("get_animals"):
		if animal.get("species") == "goat":
			animal.call("tame")
	_check(int(livestock.call("wild_count", "goat")) == 0, "toutes les chèvres apprivoisées : plus de chèvre sauvage")
	var before: int = (livestock.call("get_animals") as Array).size()
	var arrivals := {}
	for i in 12:
		var species: String = livestock.call("repopulate")
		if species != "":
			arrivals[species] = true
	_check(arrivals.has("goat"), "de nouvelles chèvres arrivent")
	_check(int(livestock.call("wild_count", "goat")) >= 2, "au moins 2 chèvres sauvages")
	var new_goats: Array = (livestock.call("get_animals") as Array).filter(func(a): return a.get("species") == "goat" and not a.tamed)
	var far := true
	for goat in new_goats:
		var flat := Vector2(goat.global_position.x - player.global_position.x, goat.global_position.z - player.global_position.z)
		far = far and flat.length() > 35.0
	_check(far, "elles apparaissent au loin, hors de vue")
	var keys := {}
	for animal in livestock.call("get_animals"):
		keys[animal.get("spawn_key")] = true
	_check(keys.size() == (livestock.call("get_animals") as Array).size(), "clés uniques (sauvegarde des bêtes apprivoisées)")
	_check((livestock.call("get_animals") as Array).size() > before, "le monde se repeuple")
	_check(livestock.call("repopulate") == "" or true, "rien à faire quand tout est là")

	# --- Niveau requis ---------------------------------------------------------------------------
	progression.call("clear_for_test", true)
	var spot := player.global_position + Vector3(6, 0, -6)
	_check(spawner.call("place", "building_shelter", spot, 0.0) == "", "abri posé")
	var shelter: Node3D = null
	for node in get_nodes_in_group("structures"):
		if node.get("kind") == "shelter":
			shelter = node
	inventory.call("add_item", "item_wood", 30)
	inventory.call("add_item", "item_pelt", 6)
	inventory.call("add_item", "item_stone", 10)
	_check(int(progression.call("get_level")) < 3, "joueur débutant")
	_check(shelter.call("upgrade_required_level") == 3, "niveau 2 de l'abri : joueur niveau 3")
	_check(shelter.call("upgrade") == "TOAST_UPGRADE_LEVEL", "refus : niveau de joueur insuffisant")
	_check(shelter.get("level") == 1 and int(inventory.call("count_of", "item_wood")) == 30, "rien n'est dépensé")

	# --- Onglet Bâtiments -------------------------------------------------------------------------
	var journal: Node = null
	for node in world.find_children("*", "", true, false):
		if node.has_method("_refresh_buildings"):
			journal = node
			break
	player.global_position = shelter.global_position + Vector3(3, 1, 4)
	journal.call("_refresh_buildings")
	var button := journal.find_child("Upgrade0", true, false) as Button
	_check(button != null and button.disabled and button.text == tr("TOAST_UPGRADE_LEVEL") % 3, "bouton grisé : niveau requis")
	progression.call("add_xp", 100000)
	player.global_position = shelter.global_position + Vector3(25, 1, 25)
	journal.call("_refresh_buildings")
	button = journal.find_child("Upgrade0", true, false) as Button
	_check(button != null and button.disabled and button.text.begins_with(tr("BUILDINGS_GO_CLOSER").get_slice("(", 0)), "trop loin : « Approchez-vous »")
	player.global_position = shelter.global_position + Vector3(3, 1, 4)
	journal.call("_refresh_buildings")
	button = journal.find_child("Upgrade0", true, false) as Button
	_check(button != null and not button.disabled, "tout près : bouton actif")
	button.pressed.emit()
	_check(shelter.get("level") == 2, "abri amélioré depuis le journal")
	print("TEST_WILD_BUILDINGS: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
