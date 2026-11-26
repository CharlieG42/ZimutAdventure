extends SceneTree
## Ordres du chien : suit → reste → garde (enclos) → suit ; le chien de garde chasse les prédateurs.

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
	for existing in get_nodes_in_group("predators"):
		existing.queue_free()
	await process_frame
	var origin: Vector3 = player.global_position + Vector3(14, 0, 14)
	spawner.call("place", "building_pen", origin, 0.0)
	var pen: Node3D = get_nodes_in_group("pens")[0]
	var scene := load("res://scenes/world/domestic_animal.tscn") as PackedScene
	var dog = scene.instantiate()
	dog.species = "dog"
	dog.position = origin + Vector3(0, 1, 18)
	world.add_child(dog)
	await process_frame
	dog.tame()
	_check(dog.following and dog.call("get_prompt_key") == "ACTION_DOG_STAY", "le chien suit : invite « rester »")
	dog.call("interact_with", player)
	_check(not dog.following and not dog.guarding and dog.call("get_prompt_key") == "ACTION_DOG_GUARD", "il reste : invite « garder les lieux »")
	dog.call("interact_with", player)
	_check(dog.guarding and not dog.following and dog.call("get_prompt_key") == "ACTION_DOG_FOLLOW", "il garde : invite « appeler le chien »")
	_check(dog.is_on_route(), "le chien se rend à l'enclos")
	for i in 1500:
		await physics_frame
		if not dog.is_on_route():
			break
	_check(pen.call("contains", dog.global_position) or dog.global_position.distance_to(pen.global_position) < 6.0, "le chien est posté à l'enclos")
	_check(dog.get("_center").distance_to(pen.global_position) < 6.0, "son poste est l'enclos")

	# Un coyote s'approche : le chien le chasse et le mord.
	var coyote = (load("res://scripts/world/predator.gd")).new_for("coyote")
	coyote.position = pen.global_position + Vector3(6, 1, 0)
	world.add_child(coyote)
	await process_frame
	var hp_before: int = coyote.get("_hp")
	for i in 900:
		await physics_frame
		if not is_instance_valid(coyote) or bool(coyote.get("_dead")) or int(coyote.get("_hp")) < hp_before:
			break
	_check(not is_instance_valid(coyote) or bool(coyote.get("_dead")) or int(coyote.get("_hp")) < hp_before, "le chien de garde a mordu le prédateur")

	# Un chien de garde ne répond pas au sifflet : il faut d'abord le libérer.
	_check(not player.call("whistle"), "sifflet : le chien de garde reste à son poste")
	_check(dog.guarding and not dog.following, "toujours de garde")
	_check(dog.get("guarding") and dog.call("get_state").get("guarding") == true, "la garde est sauvegardée")
	var restored = scene.instantiate()
	restored.species = "dog"
	restored.position = origin + Vector3(0, 1, 5)
	world.add_child(restored)
	await process_frame
	restored.call("apply_state", {"following": false, "guarding": true})
	_check(restored.guarding and not restored.following, "la garde est restaurée")
	dog.call("interact_with", player)
	_check(dog.following and not dog.guarding, "troisième clic : le chien suit à nouveau")
	dog.following = false
	_check(player.call("whistle") and dog.following, "libéré, il répond au sifflet")
	print("TEST_DOG_GUARD: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
