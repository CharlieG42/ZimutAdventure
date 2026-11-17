extends SceneTree
## Abri évolutif : coût par niveau, matériaux manquants, effets (chaleur, sommeil
## réparateur, sieste de jour au niveau 3), persistance de l'état.

var _errors: Array[String] = []

func _check(ok: bool, message: String) -> void:
	if not ok:
		_errors.append(message)

func _init() -> void:
	await process_frame
	var clock := root.get_node_or_null("DayNightCycle")
	if clock == null:
		clock = (load("res://scripts/autoload/day_night_cycle.gd") as GDScript).new()
		clock.name = "DayNightCycle"
		root.add_child(clock)
	clock.set("enabled", false)
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 5:
		await process_frame
	var placed_script = load("res://scripts/world/placed_structure.gd")
	var spawner := world.get_node("Structures")
	spawner.call("disable_saving_for_test")
	var player := world.get_node("Player") as CharacterBody3D
	var inventory := root.get_node_or_null("Inventory")
	var survival := root.get_node_or_null("SurvivalManager")
	_check(inventory != null and survival != null, "autoloads disponibles")
	var spot := Vector3(player.global_position.x + 8.0, 0.0, player.global_position.z)
	_check(spawner.call("place", "building_shelter", spot, 0.0) == "", "abri posé")
	_check(spawner.call("place", "furniture_camp_bed", spot + Vector3(0, 0, 10), 0.0) == "", "lit posé")
	await process_frame
	var shelter: Node3D = null
	var bed: Node3D = null
	for node in get_nodes_in_group("structures"):
		if node.get("kind") == "shelter":
			shelter = node as Node3D
		elif node.get("kind") == "camp_bed":
			bed = node as Node3D
	_check(shelter.get("level") == 1 and shelter.call("can_upgrade"), "abri niveau 1, améliorable")
	_check(not bed.call("can_upgrade"), "le lit ne s'améliore pas")
	var bodies_1 := shelter.find_children("*", "StaticBody3D", false, false).size()
	var meshes_1 := shelter.find_children("*", "MeshInstance3D", true, false).size()

	# Matériaux manquants : rien n'est consommé.
	for item in ["item_wood", "item_stone", "item_pelt"]:
		var owned: int = inventory.call("count_of", item)
		if owned > 0:
			inventory.call("remove_item", item, owned)
	_check(shelter.call("upgrade") == "TOAST_UPGRADE_MISSING", "sans matériaux : refus")
	_check(shelter.get("level") == 1, "le niveau ne change pas")
	var missing: Dictionary = shelter.call("upgrade_missing")
	_check(int(missing.get("item_wood", 0)) == 6 and int(missing.get("item_pelt", 0)) == 2, "manque : 6 bois, 2 peaux")

	# Niveau 2.
	inventory.call("add_item", "item_wood", 20)
	inventory.call("add_item", "item_stone", 10)
	inventory.call("add_item", "item_pelt", 5)
	_check(shelter.call("upgrade") == "", "niveau 2")
	_check(shelter.get("level") == 2, "abri niveau 2")
	_check(int(inventory.call("count_of", "item_wood")) == 14 and int(inventory.call("count_of", "item_pelt")) == 3, "coût du niveau 2 consommé")
	await process_frame
	_check(shelter.find_children("*", "MeshInstance3D", true, false).size() > meshes_1, "le niveau 2 ajoute de la matière")
	_check(shelter.find_children("*", "StaticBody3D", false, false).size() == bodies_1, "pas de collision en double")
	_check(shelter.find_children("*", "CollisionShape3D", false, false).size() == 1, "une seule zone d'interaction")
	_check(shelter.get_prompt() == "ACTION_SLEEP", "de jour au niveau 2 : on ne fait que dormir la nuit")

	# Chaleur : +40 % du bonus d'abri par niveau.
	var context := {"season": "winter", "hour": 2.0, "weather": "clear", "altitude": 0.0, "sheltered": true}
	var level1: float = survival.call("felt_temperature", context)
	context["shelter_level"] = 3
	var level3: float = survival.call("felt_temperature", context)
	_check(level3 > level1 + 5.0, "un abri niveau 3 est plus chaud (%.1f vs %.1f)" % [level3, level1])

	# Sommeil réparateur de nuit.
	clock.call("set_hour", 22.0)
	survival.call("damage", 0.6)
	var hurt: float = survival.call("get_health")
	(shelter as Interactable).interact(player)
	_check(float(survival.call("get_health")) > hurt + 0.2, "dormir au niveau 2 soigne")

	# Niveau 3 : sieste de jour.
	_check(shelter.call("upgrade") == "", "niveau 3")
	_check(not shelter.call("can_upgrade") and shelter.call("upgrade") == "TOAST_MAX_LEVEL", "niveau maximum")
	clock.call("set_hour", 12.0)
	_check(shelter.get_prompt() == "ACTION_REST_BED", "le niveau 3 permet une sieste de jour")
	player.set("stamina", 0.1)
	(shelter as Interactable).interact(player)
	_check(float(player.get("stamina")) > 0.9, "la sieste rend l'endurance")

	# Persistance : l'état est restitué par apply_state.
	_check(shelter.call("get_state").get("level") == 3, "état sauvegardé : niveau 3")
	var copy = placed_script.create("shelter")
	copy.call("apply_state", {"level": 3})
	world.add_child(copy)
	await process_frame
	_check(copy.get("level") == 3, "niveau restauré au chargement")
	_check(copy.find_children("*", "MeshInstance3D", true, false).size() == shelter.find_children("*", "MeshInstance3D", true, false).size(), "même aspect après chargement")

	# Panneau : bouton « Améliorer » sur un abri améliorable.
	var shelter2: Node3D = placed_script.create("shelter")
	world.add_child(shelter2)
	shelter2.position = spot + Vector3(0, 0, -14)
	await process_frame
	inventory.call("add_item", "item_wood", 10)
	inventory.call("add_item", "item_pelt", 4)
	var panel := world.get_node("HUD/Overlay/BuildPanel")
	panel.call("_on_focus_changed", shelter2)
	_check(panel.get("_upgrade").visible, "bouton Améliorer visible")
	_check(String(panel.get("_upgrade").text).contains("×6"), "le coût est affiché")
	panel.call("_on_upgrade")
	_check(shelter2.get("level") == 2, "le bouton améliore l'abri")

	if _errors.is_empty():
		print("TEST_SHELTER_UPGRADE: PASS")
		quit(0)
	else:
		for e in _errors:
			printerr("TEST_SHELTER_UPGRADE FAIL: " + e)
		quit(1)
