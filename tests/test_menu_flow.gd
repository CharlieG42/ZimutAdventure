extends SceneTree
## Parcours complet : partie 1 -> monde -> retour au menu -> partie 2 (sac vide, pas de mélange)
## -> retour -> partie 1 (sac retrouvé).

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	for slot in range(1, 4):
		SaveSlots.delete(slot)
	var p1 := CharacterProfile.default_for("male")
	p1.hero_name = "Un"
	var p2 := CharacterProfile.default_for("female")
	p2.hero_name = "Deux"
	SaveSlots.create(1, p1)
	SaveSlots.create(2, p2)
	SaveSlots.active_slot = 0
	var inventory := root.get_node("Inventory")
	inventory.call("clear_for_test")
	inventory.set("_autosave", true)

	# Version du jeu affichée sur le menu de démarrage.
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await _frames(2)
	var version_label := menu.find_child("VersionLabel", true, false) as Label
	var version := String(ProjectSettings.get_setting("application/config/version"))
	if version_label == null or not version_label.text.contains(version) or not version.begins_with("v0."):
		errors.append("menu : version du jeu absente (%s)" % (version_label.text if version_label else "aucun label"))
	root.remove_child(menu)
	menu.queue_free()

	SaveSlots.activate(1, self)
	change_scene_to_file(MainMenu.GAME_SCENE)
	await _frames(20)
	if current_scene == null:
		errors.append("le monde doit se charger")
	inventory.call("add_item", "item_wood", 4)
	var hud := get_first_node_in_group("hud")
	if hud == null:
		errors.append("le HUD de la partie 1 existe")
	# Retour au menu principal depuis le journal (réglages).
	var journal := current_scene.find_child("JournalPanel", true, false)
	var button: Node = journal.find_child("MainMenuButton", true, false) if journal != null else null
	if button == null:
		errors.append("le journal propose « Retour au menu principal »")
		SaveSlots.return_to_menu(self)
	else:
		(button as Button).pressed.emit()
	await _frames(10)
	if not (current_scene is MainMenu) or SaveSlots.active_slot != 0:
		errors.append("retour au menu : scène %s, partie active %d" % [str(current_scene), SaveSlots.active_slot])
	# Partie 2 : sac vide.
	SaveSlots.activate(2, self)
	if int(inventory.call("count_of", "item_wood")) != 0:
		errors.append("la partie 2 ne doit pas hériter du sac de la partie 1")
	change_scene_to_file(MainMenu.GAME_SCENE)
	await _frames(20)
	if current_scene == null or get_first_node_in_group("hud") == null:
		errors.append("le monde de la partie 2 se charge")
	SaveSlots.return_to_menu(self)
	await _frames(10)
	# Partie 1 : le bois est retrouvé.
	SaveSlots.activate(1, self)
	if int(inventory.call("count_of", "item_wood")) != 4:
		errors.append("la partie 1 retrouve son sac (%d)" % int(inventory.call("count_of", "item_wood")))
	paused = false
	inventory.call("clear_for_test")
	for slot in range(1, 4):
		SaveSlots.delete(slot)
	if errors.is_empty():
		print("PASS test_menu_flow")
		quit(0)
	else:
		for e in errors:
			print("FAIL: ", e)
		quit(1)
