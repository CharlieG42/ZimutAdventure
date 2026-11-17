extends SceneTree
## Carnet d'observation : entrées notées en regardant (cône de vue, portée), par objet obtenu,
## par lieu atteint ; une seule fois ; paliers récompensés ; quête liée ; textes FR + EN.

func _ensure(node_name: String, script_path: String) -> Node:
	var node := root.get_node_or_null(node_name)
	if node == null:
		node = (load(script_path) as GDScript).new()
		node.name = node_name
		root.add_child(node)
	return node

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var inventory := _ensure("Inventory", "res://scripts/autoload/inventory.gd")
	_ensure("Sfx", "res://scripts/autoload/sfx.gd")
	await process_frame
	inventory.call("clear_for_test")
	var progression := _ensure("Progression", "res://scripts/autoload/progression.gd")
	var quests := _ensure("QuestManager", "res://scripts/autoload/quest_manager.gd")
	var exploration := _ensure("Exploration", "res://scripts/autoload/exploration_manager.gd")
	var notebook := _ensure("Notebook", "res://scripts/autoload/notebook.gd")
	await process_frame
	progression.call("clear_for_test")
	quests.call("clear_for_test")
	quests.call("enable_rewards_for_test")
	quests.call("_unlock_available")
	exploration.call("clear_for_test")
	exploration.set_process(false)
	notebook.call("clear_for_test")
	notebook.set_process(false)
	var landscape := (load("res://scripts/world/landscape_manager.gd") as GDScript).new() as Node3D
	root.add_child(landscape)
	await process_frame

	# --- Regarder un animal : dans le cône et à portée seulement.
	# Animal minimal : seul compte son espèce et son groupe.
	var stub := GDScript.new()
	stub.source_code = "extends Node3D\nvar species := \"deer\"\n"
	stub.reload()
	var deer := Node3D.new()
	deer.set_script(stub)
	root.add_child(deer)
	deer.add_to_group("huntable")
	deer.global_position = Vector3(0.0, 0.0, -10.0)
	var eye := Vector3(0.0, 1.6, 0.0)
	if not bool(notebook.call("can_see_entry", "deer", eye, Vector3.FORWARD, landscape)):
		errors.append("un cerf droit devant à 10 m se voit")
	if bool(notebook.call("can_see_entry", "deer", eye, Vector3.BACK, landscape)):
		errors.append("un cerf dans le dos ne se voit pas")
	if bool(notebook.call("can_see_entry", "rabbit", eye, Vector3.FORWARD, landscape)):
		errors.append("un cerf n'est pas un lièvre")
	deer.global_position = Vector3(0.0, 0.0, -60.0)
	if bool(notebook.call("can_see_entry", "deer", eye, Vector3.FORWARD, landscape)):
		errors.append("un cerf à 60 m est trop loin")
	deer.queue_free()

	# --- Décor : un pin réel du paysage, regardé de près.
	var pines: PackedVector2Array = landscape.call("get_kind_positions", "pine")
	if pines.size() < 100:
		errors.append("le paysage doit lister les positions des pins (%d)" % pines.size())
	else:
		var p: Vector2 = pines[0]
		var ground: float = landscape.call("terrain_height_at", p.x, p.y)
		var from := Vector3(p.x, ground + 1.6, p.y + 6.0)
		if not bool(notebook.call("can_see_entry", "pine", from, Vector3.FORWARD, landscape)):
			errors.append("un pin à 6 m droit devant se voit")
		for kind in ["cactus", "agave", "shrub", "flowers", "hoodoo", "arch", "butte"]:
			if (landscape.call("get_kind_positions", kind) as PackedVector2Array).is_empty():
				errors.append("aucune position pour %s : l'entrée serait introuvable" % kind)

	# --- Noter : une seule fois, XP et compteur de quête.
	if not bool(notebook.call("observe", "deer")) or bool(notebook.call("observe", "deer")):
		errors.append("une entrée se note une seule fois")
	if int(progression.call("get_stat", "stat_observations")) != 1:
		errors.append("chaque observation compte pour les quêtes")
	if bool(notebook.call("observe", "licorne")):
		errors.append("pas d'entrée inventée")

	# --- Objet obtenu : un poisson pêché se note.
	inventory.call("add_item", "item_fish", 1)
	if not bool(notebook.call("is_observed", "fish")):
		errors.append("pêcher un poisson le note dans le carnet")

	# --- Lieu atteint : la rivière.
	exploration.call("check_landmarks", landscape, Vector3(35.0, 0.0, float(landscape.call("river_center_z", 35.0))))
	if not bool(notebook.call("is_observed", "river")):
		errors.append("atteindre la rivière la note dans le carnet")

	# --- Palier : la 6e observation offre des flèches.
	var before := int(inventory.call("count_of", "arrow"))
	for entry_id in ["rabbit", "cow", "sheep"]:
		notebook.call("observe", entry_id)
	if int(notebook.call("get_count")) != 6:
		errors.append("six observations attendues (%d)" % int(notebook.call("get_count")))
	if int(inventory.call("count_of", "arrow")) != before + 6:
		errors.append("le palier de 6 observations offre 6 flèches")
	if int(notebook.call("get_next_milestone")) != 12:
		errors.append("prochain palier : 12")
	var fauna: Vector2i = notebook.call("get_category_progress", "fauna")
	if fauna != Vector2i(5, 11):
		errors.append("faune : 5 / 11 attendu, reçu %s" % str(fauna))

	# --- Quête du naturaliste : ouverte après la rivière, terminée à 8 observations.
	inventory.call("add_item", "item_stone", 3)
	if int(quests.call("state_of", "quest_naturalist")) != 1:
		errors.append("« Carnet de naturaliste » s'ouvre une fois la rivière trouvée")
	notebook.call("observe", "goat")
	notebook.call("observe", "chicken")
	if int(quests.call("state_of", "quest_naturalist")) != 2:
		errors.append("8 observations terminent « Carnet de naturaliste »")

	# --- Textes de chaque entrée dans les deux langues.
	for lang in ["fr", "en"]:
		var csv := FileAccess.get_file_as_string("res://locales/translations.%s.csv" % lang)
		var keys := ["JOURNAL_NOTEBOOK", "NOTEBOOK_INTRO", "NOTEBOOK_NEXT", "TOAST_OBSERVED", "TOAST_NOTEBOOK_REWARD",
				"QUEST_NATURALIST_TITLE", "QUEST_NATURALIST_DESC"]
		for category in notebook.get("CATEGORIES"):
			keys.append("NOTEBOOK_" + String(category).to_upper())
		for entry_id in notebook.get("ENTRIES"):
			keys.append(notebook.call("name_key", entry_id))
			keys.append(notebook.call("description_key", entry_id))
			keys.append(notebook.call("hint_key", entry_id))
		for key in keys:
			if not csv.contains("\n" + key + ","):
				errors.append("clé de traduction manquante (%s) : %s" % [lang, key])

	# --- Journal : l'onglet Carnet se construit.
	var journal := (load("res://scripts/ui/journal_panel.gd") as GDScript).new() as Control
	root.add_child(journal)
	await process_frame
	journal.call("_refresh_notebook")
	var list := journal.get("_notebook_list") as VBoxContainer
	if list == null or list.get_child_count() < 4:
		errors.append("l'onglet Carnet affiche l'introduction et les trois catégories")
	journal.queue_free()

	landscape.free()
	if errors.is_empty():
		print("TEST_NOTEBOOK: PASS")
		quit(0)
	else:
		for e in errors:
			print("TEST_NOTEBOOK FAIL: " + e)
		quit(1)
