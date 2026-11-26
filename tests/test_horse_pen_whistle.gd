extends SceneTree
## Chevaux en enclos, filtre « hors enclos » de la fenêtre Ranch, et sifflet : un cheval en
## enclos ou un chien de garde ne répondent pas tant qu'on ne les a pas libérés.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	await process_frame
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
	world.get_node("Livestock").call("disable_saving_for_test")
	progression.call("clear_for_test", true)
	progression.call("add_xp", 100000)
	for existing in get_nodes_in_group("domestic"):
		existing.remove_from_group("tamed")
		existing.queue_free()
	await process_frame
	var origin: Vector3 = player.global_position + Vector3(14, 0, 14)
	spawner.call("place", "building_pen", origin, 0.0)
	var pen: Node3D = get_nodes_in_group("pens")[0]
	var scene := load("res://scenes/world/domestic_animal.tscn") as PackedScene
	var animals := {}
	for species in ["horse", "dog", "cow"]:
		var animal = scene.instantiate()
		animal.species = species
		animal.position = origin + Vector3(0, 1, 26)
		world.add_child(animal)
		await process_frame
		animal.tame()
		animals[species] = animal
	var horse = animals["horse"]
	var dog = animals["dog"]
	_check(horse.call("can_be_penned") and not horse.penned, "un cheval peut aller en enclos")
	_check(not pen.call("herdable").has(horse), "« Rassembler » ne prend pas le cheval (seulement par la fenêtre Ranch)")

	# Fenêtre Ranch : filtre, puis cheval mis dans l'enclos.
	var hud := world.get_node("HUD")
	hud.call("open_ranch_panel", pen)
	var panel: RanchPanel = hud.get("ranch_panel")
	var filter := panel.find_child("OnlyFreeFilter", true, false) as CheckButton
	_check(filter != null, "filtre « hors enclos » présent")
	var horse_button: Button = null
	for i in 4:
		var b := panel.find_child("Animal%d" % i, true, false) as Button
		if b != null and b.get_parent().get_child(0).text.contains(tr("SPECIES_HORSE")):
			horse_button = b
	_check(horse_button != null and horse_button.text == tr("ACTION_PUT_HERE"), "le cheval est listé (« Mettre ici »)")
	horse_button.pressed.emit()
	for i in 2400:
		await physics_frame
		if horse.penned:
			break
	_check(horse.penned and pen.call("contains", horse.global_position), "le cheval est dans l'enclos")
	# La vache, apprivoisée près de l'enclos, y est entrée d'elle-même : on la sort.
	pen.call("release_animal", animals["cow"])
	filter = panel.find_child("OnlyFreeFilter", true, false) as CheckButton
	filter.toggled.emit(true)
	_check(panel.only_free, "filtre activé")
	var listed_horse := false
	for i in 4:
		var b := panel.find_child("Animal%d" % i, true, false) as Button
		if b != null and b.get_parent().get_child(0).text.contains(tr("SPECIES_HORSE")):
			listed_horse = true
	_check(not listed_horse, "filtre actif : le cheval en enclos est masqué")
	_check(panel.find_child("Animal0", true, false) != null, "la vache hors enclos reste listée")

	# Sifflet : cheval en enclos et chien de garde ne viennent pas.
	pen.call("assign_guard", dog)
	_check(dog.guarding, "chien de garde affecté")
	dog.following = false
	_check(not player.call("whistle"), "sifflet sans effet : personne de libre")
	_check(horse.penned and dog.guarding and not horse.summoned, "le cheval reste en enclos, le chien garde")
	pen.call("release_animal", horse)
	pen.call("unassign_guard", dog)
	_check(player.call("whistle"), "après libération, ils répondent au sifflet")
	_check(horse.summoned and dog.following, "le cheval accourt et le chien suit")
	print("TEST_HORSE_PEN_WHISTLE: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
