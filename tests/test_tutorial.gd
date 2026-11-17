extends SceneTree
## Premiers pas : les consignes s'enchaînent dans l'ordre et ne se valident que par l'action
## demandée ; « Passer » arrête tout ; on peut recommencer ; textes tactiles et clavier
## en français et en anglais.

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
	var journal := Control.new()
	var map := Control.new()
	journal.visible = false
	map.visible = false
	root.add_child(journal)
	root.add_child(map)
	var player := Node3D.new()
	root.add_child(player)

	var tutorial := (load("res://scripts/ui/tutorial_panel.gd") as GDScript).new() as Control
	root.add_child(tutorial)
	tutorial.call("set_context", player, journal, map)
	tutorial.call("clear_for_test", true)
	await process_frame
	if String(tutorial.call("current_step")) != "move" or not tutorial.visible:
		errors.append("la première consigne est de marcher (%s)" % String(tutorial.call("current_step")))

	# Marcher : il faut vraiment avancer de quelques mètres.
	player.global_position = Vector3(2.0, 0.0, 0.0)
	await process_frame
	if String(tutorial.call("current_step")) != "move":
		errors.append("deux mètres ne suffisent pas")
	# Pas à pas (un saut de plus de 3 m est pris pour une téléportation et ignoré).
	for k in range(3, 10):
		player.global_position = Vector3(float(k), 0.0, 0.0)
		await process_frame
	await process_frame
	if String(tutorial.call("current_step")) != "look":
		errors.append("après quelques mètres : regarder autour (%s)" % String(tutorial.call("current_step")))
	# Regarder : un vrai tour de tête.
	player.rotation.y = 0.8
	await process_frame
	player.rotation.y = 1.7
	await process_frame
	await process_frame
	if String(tutorial.call("current_step")) != "pickup":
		errors.append("après un tour de tête : ramasser (%s)" % String(tutorial.call("current_step")))
	# Ramasser : seul un objet obtenu valide l'étape.
	await process_frame
	if String(tutorial.call("current_step")) != "pickup":
		errors.append("ramasser ne se valide pas tout seul")
	inventory.call("add_item", "item_stone", 1)
	await process_frame
	if String(tutorial.call("current_step")) != "journal":
		errors.append("après une pierre ramassée : ouvrir le journal (%s)" % String(tutorial.call("current_step")))
	map.visible = true
	await process_frame
	if String(tutorial.call("current_step")) != "journal":
		errors.append("ouvrir la carte ne valide pas l'étape du journal")
	map.visible = false
	journal.visible = true
	await process_frame
	journal.visible = false
	if String(tutorial.call("current_step")) != "map":
		errors.append("après le journal : la carte (%s)" % String(tutorial.call("current_step")))
	map.visible = true
	await process_frame
	if String(tutorial.call("current_step")) != "compass":
		errors.append("après la carte : la boussole (%s)" % String(tutorial.call("current_step")))
	tutorial.set("_step_time", 100.0)
	await process_frame
	if not bool(tutorial.get("done")) or tutorial.visible:
		errors.append("la dernière consigne termine le tutoriel")

	# Recommencer puis passer.
	tutorial.call("restart")
	tutorial.set("_delay", 0.0)
	await process_frame
	if String(tutorial.call("current_step")) != "move" or bool(tutorial.get("done")):
		errors.append("« Revoir le tutoriel » repart de la première consigne")
	tutorial.call("skip")
	if not bool(tutorial.get("done")) or tutorial.visible or tutorial.is_processing():
		errors.append("« Passer » arrête le tutoriel")

	# Textes : tactile et clavier différents, dans les deux langues.
	for lang in ["fr", "en"]:
		var csv := FileAccess.get_file_as_string("res://locales/translations.%s.csv" % lang)
		var keys := ["TUTO_TITLE", "TUTO_SKIP", "TUTO_DONE", "TUTO_COMPASS", "SETTING_TUTORIAL"]
		for step_name in ["MOVE", "LOOK", "PICKUP", "JOURNAL", "MAP"]:
			keys.append("TUTO_%s_TOUCH" % step_name)
			keys.append("TUTO_%s_KEYS" % step_name)
		for key in keys:
			if not csv.contains("\n" + key + ","):
				errors.append("clé de traduction manquante (%s) : %s" % [lang, key])

	tutorial.queue_free()
	if errors.is_empty():
		print("TEST_TUTORIAL: PASS")
		quit(0)
	else:
		for e in errors:
			print("TEST_TUTORIAL FAIL: " + e)
		quit(1)
