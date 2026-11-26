extends SceneTree
## Objets en fer : outils forgés (palier fer, niveau 6), flèches à pointe de fer, carabine à
## levier (niveau 10) et cartouches.

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
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	paused = false
	var player := world.get_node("Player") as CharacterBody3D
	player.add_to_group("player")
	inventory.call("clear_for_test")
	progression.call("clear_for_test", true)

	# Recettes : niveaux élevés pour la carabine et les cartouches.
	_check(int(craft.RECIPES["tool_rifle"]["level"]) == 10 and int(craft.RECIPES["item_cartridge"]["level"]) == 10, "carabine et cartouches au niveau 10")
	_check(int(craft.RECIPES["arrow_iron"]["batch"]) == 8, "flèches de fer par 8")

	# Forge d'un outil en fer.
	inventory.call("add_item", "tool_stone_axe", 1)
	inventory.call("add_item", "item_iron_ingot", 10)
	inventory.call("add_item", "item_wood", 10)
	_check(inventory.call("forge_iron_tool", "tool_stone_axe") == "TOAST_UPGRADE_LEVEL", "forge : niveau 6 requis")
	progression.call("add_xp", 100000)
	_check(inventory.call("forge_iron_tool", "tool_stone_axe") == "", "hache forgée en fer")
	_check(inventory.call("is_iron_tool", "tool_stone_axe") and int(inventory.call("count_of", "item_iron_ingot")) == 8, "palier fer, 2 lingots dépensés")
	_check(inventory.call("forge_iron_tool", "tool_stone_axe") == "TOAST_MAX_LEVEL", "déjà en fer")

	# Fenêtre Personnage : ligne de forge pour l'outil en main.
	inventory.call("add_item", "tool_pickaxe", 1)
	inventory.call("equip", "tool_pickaxe")
	var panel := CharacterPanel.new()
	root.add_child(panel)
	await process_frame
	panel.call("open")
	var forge := panel.find_child("Forge_tool_pickaxe", true, false) as Button
	_check(forge != null and not forge.disabled, "bouton Forger pour la pioche en main")
	forge.pressed.emit()
	_check(inventory.call("is_iron_tool", "tool_pickaxe"), "pioche forgée depuis la fenêtre")
	panel.queue_free()

	# Flèches de fer : tirées en premier, deux fois plus de dégâts aux prédateurs.
	inventory.call("add_item", "tool_hunting_bow", 1)
	inventory.call("equip", "tool_hunting_bow")
	inventory.call("add_item", "arrow", 3)
	inventory.call("add_item", "arrow_iron", 2)
	_check(player.call("arrow_count") == 5, "5 flèches au total")
	player.call("shoot_arrow", 1.0)
	_check(int(inventory.call("count_of", "arrow_iron")) == 1 and int(inventory.call("count_of", "arrow")) == 3, "la flèche de fer part d'abord")
	var coyote = (load("res://scripts/world/predator.gd")).new_for("coyote")
	coyote.position = player.global_position + Vector3(0, 1, -12)
	world.add_child(coyote)
	await process_frame
	var arrow = (load("res://scenes/interaction/arrow.tscn") as PackedScene).instantiate()
	arrow.set("iron", true)
	world.add_child(arrow)
	var hp: int = coyote.get("_hp")
	arrow.call("_strike", coyote, player.global_position)
	_check(int(coyote.get("_hp")) == hp - 4 or bool(coyote.get("_dead")), "flèche de fer : 4 points de dégâts")
	arrow.queue_free()

	# Carabine : cartouche, portée, tir à travers rien, cadence.
	inventory.call("add_item", "tool_rifle", 1)
	inventory.call("equip", "tool_rifle")
	var camera := player.get_viewport().get_camera_3d()
	_check(player.call("fire_rifle") == null and int(inventory.call("count_of", "item_cartridge")) == 0, "sans cartouche, rien ne part")
	inventory.call("add_item", "item_cartridge", 3)
	var from: Vector3 = player.call("_arrow_origin", camera)
	var dir: Vector3 = -camera.global_transform.basis.z
	var target_pos := from + Vector3(dir.x, 0, dir.z).normalized() * 30.0
	coyote.global_position = Vector3(target_pos.x, target_pos.y - 0.9, target_pos.z)
	coyote.set("_hp", 5)
	coyote.set("_dead", false)
	coyote.add_to_group("predators")
	await physics_frame
	var aimed: Node3D = player.call("rifle_target", from, (coyote.global_position + Vector3(0, 0.6, 0) - from).normalized())
	_check(aimed == coyote, "le coyote dans la ligne de mire est visé")
	player.set("_bow_target", coyote)
	var hit: Node3D = player.call("fire_rifle")
	_check(hit == coyote and (bool(coyote.get("_dead")) or int(coyote.get("_hp")) <= 0), "un tir de carabine abat le coyote")
	_check(int(inventory.call("count_of", "item_cartridge")) == 2, "une cartouche consommée")
	_check(player.call("fire_rifle") == null and int(inventory.call("count_of", "item_cartridge")) == 2, "coup de levier : pas de second tir immédiat")
	_check(player.call("get_bow_state").get("weapon") == "rifle" and player.call("get_bow_state").get("arrows") == 2, "le viseur affiche les cartouches")
	_check(ResourceLoader.exists("res://assets/audio/sfx/rifle_shot.wav"), "son de détonation")
	print("TEST_IRON_ITEMS: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
