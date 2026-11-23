extends SceneTree
## Corrections : onglet Animaux rattrapé pour les anciennes parties, palissades raccordées,
## cavalier assis sur le dos du cheval, pieds hors du sol.

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

	# --- Onglet Animaux : ancienne partie sans compteur par espèce -----------------------------
	var tamed_cows := 0
	for animal in world.get_node("Livestock").call("get_animals"):
		if animal.get("species") == "cow" and tamed_cows < 2:
			animal.call("tame")
			tamed_cows += 1
	progression.call("clear_for_test", true)
	progression.call("add_stat", "stat_tamed", 2)
	_check(int(progression.call("get_stat", "stat_tamed_cow")) == 0, "ancienne partie : pas de compteur par espèce")
	var journal: Node = null
	for node in world.find_children("*", "", true, false):
		if node.has_method("_refresh_animals"):
			journal = node
			break
	journal.call("_refresh_animals")
	_check(int(progression.call("get_stat", "stat_tamed_cow")) == tamed_cows, "compteur des vaches rattrapé (%d)" % tamed_cows)
	var text := ""
	for child in (journal.get("_animals_list") as Node).get_children():
		if child is RichTextLabel or child is Label:
			text += child.text + "\n"
	_check(text.contains("×%d" % tamed_cows), "la ligne des vaches s'affiche")

	# --- Palissades raccordées ---------------------------------------------------------------------
	var base: Vector3 = player.global_position + Vector3(0, 0, -10)
	_check(spawner.call("place", "building_palisade", base, 0.0) == "", "première palissade")
	# Visée approximative au bout droit, légèrement de travers : elle doit s'aligner.
	_check(spawner.call("place", "building_palisade", base + Vector3(3.4, 0, 0.5), 0.2) == "", "deuxième palissade")
	var fences := get_nodes_in_group("palisades")
	var first: Node3D = fences[0]
	var second: Node3D = fences[1]
	var half: float = Palisade.LENGTH * 0.5
	var end_a: Vector3 = first.global_position + first.global_transform.basis.x * half
	var end_b1: Vector3 = second.global_position - second.global_transform.basis.x * half
	var end_b2: Vector3 = second.global_position + second.global_transform.basis.x * half
	var gap := minf(Vector2(end_a.x - end_b1.x, end_a.z - end_b1.z).length(), Vector2(end_a.x - end_b2.x, end_a.z - end_b2.z).length())
	_check(gap < 0.05, "les extrémités se touchent (écart %.2f m)" % gap)
	_check(is_zero_approx(fmod(absf(angle_difference(second.rotation.y, first.rotation.y)), PI * 0.5)), "alignée ou en angle droit")
	# En angle : visée près du bout, orientée à 90°.
	_check(spawner.call("place", "building_palisade", base + Vector3(6.2, 0, -1.6), PI * 0.5) == "", "troisième palissade en angle")
	var third: Node3D = get_nodes_in_group("palisades")[2]
	_check(absf(absf(angle_difference(third.rotation.y, first.rotation.y)) - PI * 0.5) < 0.01, "angle droit")
	# Loin de tout : pas de raccord.
	var lone: Dictionary = spawner.call("snap_palisade", base + Vector3(-30, 0, 0), 0.3)
	_check(not bool(lone["snapped"]) and is_equal_approx(float(lone["yaw"]), 0.3), "loin des autres : posée telle quelle")

	# --- Cavalier sur le dos du cheval ---------------------------------------------------------------
	var lift: float = player.call("mount_lift_for_hero")
	var hip: float = player.call("hero_hip_height")
	_check(hip > 0.5, "hauteur du bassin connue (%.2f)" % hip)
	_check(absf(hip - 0.18 + lift - 1.86) < 0.02, "le bassin se pose à 1,86 m, sur le dos du cheval")

	# --- Pieds : terrain plat, pas de surélévation --------------------------------------------------
	for i in 30:
		await physics_frame
	_check(float(player.call("foot_lift")) < 0.05, "sol plat : pieds au sol, sans surélévation")
	print("TEST_FIXES_SELLE_PALISSADES: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
