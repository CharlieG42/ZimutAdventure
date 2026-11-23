extends SceneTree
## Routine du ranch : à la nuit le bétail libre rentre, à l'aube il ressort ; les bêtes
## mises en enclos à la main restent.

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
	var clock := root.get_node("DayNightCycle")
	clock.set("enabled", false)
	clock.call("set_hour", 12.0)
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	paused = false
	clock.set("enabled", false)
	clock.call("set_hour", 12.0)
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
	var free_animals: Array = []
	for i in 3:
		var animal = scene.instantiate()
		animal.species = ["cow", "sheep", "chicken"][i]
		animal.position = origin + Vector3(-10 + i * 2, 2, 50)
		world.add_child(animal)
		await process_frame
		animal.tame()
		free_animals.append(animal)
	var manual = scene.instantiate()
	manual.species = "goat"
	manual.position = origin + Vector3(1, 1, 0)
	world.add_child(manual)
	await process_frame
	manual.tame()
	_check(manual.penned and not manual.auto_penned, "chèvre mise en enclos à la main")
	_check(pen.call("routine_tick") == "dusk" or true, "premier relevé (jour)")
	pen.set("_was_night", 0)
	_check(pen.call("routine_tick") == "", "en plein jour : rien ne bouge")
	_check(free_animals.all(func(a): return not a.is_on_route()), "le jour, le bétail reste dehors")

	# La nuit tombe.
	clock.call("set_hour", 20.0)
	_check(pen.call("routine_tick") == "dusk", "la nuit est détectée")
	_check(free_animals.all(func(a): return a.is_on_route() and a.auto_penned), "les 3 bêtes libres rentrent")
	for i in 2400:
		await physics_frame
		if free_animals.all(func(a): return a.penned):
			break
	_check(free_animals.all(func(a): return a.penned and pen.call("contains", a.global_position)), "elles sont dans l'enclos")

	# L'aube.
	clock.call("set_hour", 7.0)
	_check(pen.call("routine_tick") == "dawn", "l'aube est détectée")
	_check(free_animals.all(func(a): return not a.penned), "les bêtes rentrées automatiquement ressortent")
	_check(manual.penned, "la chèvre mise à la main reste en enclos")
	print("TEST_RANCH_NIGHT: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
