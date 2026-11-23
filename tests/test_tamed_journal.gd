extends SceneTree
## Journal des animaux apprivoisés, succès d'élevage, sifflet du chien à cheval,
## invite d'action au-dessus du réticule.

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
	var quests := root.get_node("QuestManager")
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	paused = false
	var player := world.get_node("Player") as CharacterBody3D
	player.add_to_group("player")
	world.get_node("Livestock").call("disable_saving_for_test")
	progression.call("clear_for_test", true)
	quests.call("clear_for_test")
	for existing in get_nodes_in_group("domestic"):
		existing.remove_from_group("tamed")
		existing.queue_free()
	await process_frame
	var scene := load("res://scenes/world/domestic_animal.tscn") as PackedScene
	var animals := {}
	for species in ["cow", "sheep", "dog", "horse"]:
		var animal = scene.instantiate()
		animal.species = species
		animal.position = player.global_position + Vector3(20, 2, 20)
		world.add_child(animal)
		await process_frame
		animal.tame()
		animals[species] = animal
	_check(int(progression.call("get_stat", "stat_tamed")) == 4, "4 animaux apprivoisés au total")
	_check(int(progression.call("get_stat", "stat_tamed_cow")) == 1 and int(progression.call("get_stat", "stat_tamed_dog")) == 1, "compteur par espèce")
	_check(int(progression.call("get_stat", "stat_tamed_goat")) == 0, "espèce non apprivoisée : 0")

	# --- Succès d'élevage ----------------------------------------------------------------
	for id in ["quest_tamer_3", "quest_tamer_8", "quest_tamer_15"]:
		_check(quests.QUESTS.has(id), "succès %s déclaré" % id)
		_check(tr(quests.QUESTS[id]["title"]) != quests.QUESTS[id]["title"], "titre traduit pour %s" % id)
	_check(quests.QUESTS["quest_tamer_8"]["requires"] == "quest_tamer_3", "paliers enchaînés")

	# --- Journal : onglet Animaux -------------------------------------------------------------
	var journal := world.get_node("HUD/Overlay/JournalPanel") if world.has_node("HUD/Overlay/JournalPanel") else null
	if journal == null:
		for node in world.find_children("*", "", true, false):
			if node.has_method("show_tab") and node.has_method("_refresh_animals"):
				journal = node
				break
	_check(journal != null, "journal trouvé")
	if journal != null:
		journal.call("_refresh_animals")
		var list: VBoxContainer = journal.get("_animals_list")
		_check(list != null and list.get_child_count() >= 7, "intro + 6 espèces listées")
		var text := ""
		for child in list.get_children():
			text += (child.text if child is RichTextLabel or child is Label else "") + "\n"
		_check(text.contains("×1"), "les espèces apprivoisées affichent leur compteur")
		_check(text.contains("???"), "les espèces inconnues restent cachées")

	# --- Sifflet : le chien reste appelable à cheval -----------------------------------------------
	var hud := world.get_node("HUD")
	animals["horse"].mount(player)
	hud.call("_refresh_whistle_button")
	_check(hud.get("whistle_button").visible, "à cheval : le bouton Siffler reste là pour le chien")
	animals["dog"].following = false
	animals["dog"].global_position = player.global_position + Vector3(30, 1, 0)
	_check(player.call("whistle"), "à cheval, le sifflet appelle le chien")
	_check(animals["dog"].following, "le chien revient")
	animals["horse"].dismount(player)

	# --- Invite d'action : au-dessus du réticule, hors du personnage ---------------------------------
	var prompt: Control = hud.get("interact_prompt")
	_check(prompt.offset_top < 0.0, "l'invite est au-dessus du réticule")

	print("TEST_TAMED_JOURNAL: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
