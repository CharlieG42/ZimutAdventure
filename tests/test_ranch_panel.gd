extends SceneTree
## Fenêtre Ranch : renommer un enclos, affecter des chiens de garde (2 max), choisir les bêtes
## de chaque enclos, persistance du nom et de la garde.

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
	var hud := world.get_node("HUD")
	hud.call("_refresh_ranch_button")
	_check(not hud.get("ranch_button").visible, "pas d'enclos : pas de bouton Ranch")
	var origin: Vector3 = player.global_position + Vector3(14, 0, 14)
	spawner.call("place", "building_pen", origin, 0.0)
	spawner.call("place", "building_pen", origin + Vector3(30, 0, 0), 0.0)
	var pens := get_nodes_in_group("pens")
	var pen_a: Node3D = pens[0]
	var pen_b: Node3D = pens[1]
	hud.call("_refresh_ranch_button")
	_check(hud.get("ranch_button").visible, "un enclos : bouton Ranch visible")
	_check(pen_a.call("display_name") == tr("PEN_DEFAULT_NAME") % 1 and pen_b.call("display_name") == tr("PEN_DEFAULT_NAME") % 2, "noms par défaut numérotés")
	_check(pen_a.get("pen_id") != pen_b.get("pen_id"), "identifiants distincts")

	var scene := load("res://scenes/world/domestic_animal.tscn") as PackedScene
	var dogs: Array = []
	for i in 3:
		var dog = scene.instantiate()
		dog.species = "dog"
		dog.position = origin + Vector3(-6 + i, 1, 20)
		world.add_child(dog)
		await process_frame
		dog.tame()
		dogs.append(dog)
	var cow = scene.instantiate()
	cow.species = "cow"
	cow.position = origin + Vector3(1, 1, 0)
	world.add_child(cow)
	await process_frame
	cow.tame()
	_check(pen_a.call("get_occupants").has(cow), "la vache est dans l'enclos 1")

	# --- Fenêtre ---------------------------------------------------------------------------------------
	hud.call("open_ranch_panel", pen_a)
	var panel: RanchPanel = hud.get("ranch_panel")
	_check(panel.visible and panel.selected_pen() == pen_a, "la fenêtre s'ouvre sur l'enclos 1")
	var name_edit := panel.find_child("PenName", true, false) as LineEdit
	name_edit.text = "Prairie des vaches"
	name_edit.text_submitted.emit(name_edit.text)
	_check(pen_a.call("display_name") == "Prairie des vaches", "enclos renommé")
	_check(pen_a.call("get_state").get("name") == "Prairie des vaches", "nom sauvegardé")

	# Chiens de garde : 2 au plus.
	(panel.find_child("Guard0", true, false) as Button).pressed.emit()
	(panel.find_child("Guard1", true, false) as Button).pressed.emit()
	_check(pen_a.call("guard_dogs").size() == 2, "deux chiens affectés à l'enclos 1")
	_check((panel.find_child("Guard2", true, false) as Button).disabled, "le troisième ne peut pas être affecté")
	_check(pen_a.call("assign_guard", dogs[2]) == "TOAST_PEN_GUARDS_FULL", "refus au-delà de deux")
	_check(dogs[0].guard_pen_id == pen_a.get("pen_id") and dogs[0].call("get_state").get("guard_pen") == pen_a.get("pen_id"), "affectation sauvegardée")
	(panel.find_child("Guard0", true, false) as Button).pressed.emit()
	_check(pen_a.call("guard_dogs").size() == 1 and not dogs[0].guarding, "un chien retiré de la garde")

	# Bétail : déplacer la vache vers l'enclos 2.
	panel.open(pen_b)
	var row: Button = null
	for i in 5:
		var candidate := panel.find_child("Animal%d" % i, true, false) as Button
		if candidate != null:
			row = candidate
			break
	_check(row != null and row.text == tr("ACTION_PUT_HERE"), "bouton « Mettre ici » pour la vache")
	row.pressed.emit()
	_check(not cow.penned and cow.herd_pen == pen_b, "la vache quitte l'enclos 1 et part vers l'enclos 2")
	for i in 2400:
		await physics_frame
		if cow.penned:
			break
	_check(cow.penned and pen_b.call("contains", cow.global_position), "la vache est dans l'enclos 2")
	panel.refresh()
	var out := panel.find_child("Animal0", true, false) as Button
	_check(out != null and out.text == tr("ACTION_TAKE_OUT"), "bouton « Sortir »")
	out.pressed.emit()
	_check(not cow.penned, "la vache sort")

	# Restauration.
	var copy = load("res://scripts/world/pen.gd").create()
	copy.call("apply_state", {"level": 1, "name": "Basse-cour", "id": "pen_test"})
	world.add_child(copy)
	copy.position = origin + Vector3(-40, 0, 0)
	await process_frame
	_check(copy.call("display_name") == "Basse-cour" and copy.get("pen_id") == "pen_test", "nom et identifiant restaurés")
	hud.call("open_ranch_panel")
	_check(not panel.visible, "le bouton referme la fenêtre")
	print("TEST_RANCH_PANEL: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
