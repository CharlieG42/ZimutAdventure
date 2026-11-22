extends SceneTree
## Parties : 3 emplacements isolés, migration de l'ancienne sauvegarde, menu de démarrage
## (jouer, supprimer, nouvelle partie avec nom et genre), nom du héros modifiable.

func _wipe_all() -> void:
	for slot in range(1, SaveSlots.MAX_SLOTS + 1):
		SaveSlots.delete(slot)
	SaveSlots.active_slot = 0

func _profile(hero_name: String, gender: String) -> CharacterProfile:
	var p := CharacterProfile.default_for(gender)
	p.hero_name = hero_name
	return p

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	_wipe_all()

	# --- Nom du héros ---------------------------------------------------------------------
	if CharacterProfile.clean_name("  Alice\nBob  ") != "Alice Bob":
		errors.append("nom : espaces et retours à la ligne nettoyés")
	if CharacterProfile.clean_name("1234567890123456789").length() != CharacterProfile.NAME_MAX:
		errors.append("nom : longueur limitée")
	var back := CharacterProfile.from_dict(_profile("Zoé", "female").to_dict())
	if back.hero_name != "Zoé" or back.gender != "female":
		errors.append("le nom doit survivre à to_dict / from_dict")
	if CharacterProfile.default_for("male").display_name() == "":
		errors.append("un nom par défaut est affiché")

	# --- Emplacements -----------------------------------------------------------------------
	if SaveSlots.first_free_slot() != 1:
		errors.append("tous les emplacements doivent être libres au départ")
	if SaveSlots.create(0, _profile("x", "male")) or SaveSlots.create(4, _profile("x", "male")):
		errors.append("seuls les emplacements 1 à 3 existent")
	var names := ["Alix", "Bea", "Chen"]
	for i in 3:
		if not SaveSlots.create(i + 1, _profile(names[i], "female" if i == 1 else "male")):
			errors.append("création de la partie %d" % (i + 1))
		var f := FileAccess.open(SaveSlots.file("marque.txt"), FileAccess.WRITE)
		f.store_string("partie %d" % (i + 1))
		f.close()
	if SaveSlots.first_free_slot() != 0:
		errors.append("3 parties : plus aucun emplacement libre")
	if String(SaveSlots.info(2)["name"]) != "Bea" or String(SaveSlots.info(2)["gender"]) != "female":
		errors.append("infos de la partie 2 : %s" % str(SaveSlots.info(2)))
	for i in 3:
		SaveSlots.active_slot = i + 1
		if FileAccess.get_file_as_string(SaveSlots.file("marque.txt")) != "partie %d" % (i + 1):
			errors.append("les parties doivent être isolées (partie %d)" % (i + 1))
		if CharacterProfile.load_saved().hero_name != names[i]:
			errors.append("le personnage se relit dans sa partie (%d)" % (i + 1))
	# Modifier le nom et le genre en cours d'aventure.
	SaveSlots.active_slot = 1
	var edited := CharacterProfile.load_saved()
	edited.hero_name = "Alix II"
	edited.gender = "female"
	edited.save()
	SaveSlots.update_active_info(edited)
	if String(SaveSlots.info(1)["name"]) != "Alix II" or String(SaveSlots.info(1)["gender"]) != "female":
		errors.append("nom / genre modifiables en cours de partie")
	# Suppression.
	SaveSlots.delete(2)
	if SaveSlots.slot_exists(2) or SaveSlots.first_free_slot() != 2:
		errors.append("la partie 2 doit être supprimée")
	if SaveSlots.activate(2):
		errors.append("on ne peut pas activer une partie vide")
	SaveSlots.active_slot = 0

	# --- Migration de l'ancienne sauvegarde -----------------------------------------------
	_wipe_all()
	DirAccess.remove_absolute(SaveSlots.MIGRATED_FILE)
	var legacy := ConfigFile.new()
	legacy.set_value("items", "item_wood", 7)
	legacy.save("user://inventory.cfg")
	var legacy_char := ConfigFile.new()
	legacy_char.set_value("character", "profile", {"gender": "female", "hero_name": "Mira"})
	legacy_char.save("user://character.cfg")
	SaveSlots.migrate_legacy()
	if not SaveSlots.slot_exists(1) or String(SaveSlots.info(1)["name"]) != "Mira" or String(SaveSlots.info(1)["gender"]) != "female":
		errors.append("l'ancienne partie doit devenir la partie 1 : %s" % str(SaveSlots.info(1)))
	SaveSlots.active_slot = 1
	var migrated := ConfigFile.new()
	if migrated.load(SaveSlots.file("inventory.cfg")) != OK or int(migrated.get_value("items", "item_wood", 0)) != 7:
		errors.append("le sac de l'ancienne partie doit être repris")
	SaveSlots.active_slot = 0
	SaveSlots.migrate_legacy()
	if SaveSlots.first_free_slot() != 2:
		errors.append("la migration ne se rejoue pas")
	DirAccess.remove_absolute("user://inventory.cfg")
	DirAccess.remove_absolute("user://character.cfg")

	# --- Menu de démarrage ----------------------------------------------------------------
	_wipe_all()
	SaveSlots.create(1, _profile("Alix", "male"))
	var inv_cfg := ConfigFile.new()
	inv_cfg.set_value("items", "item_wood", 5)
	inv_cfg.save(SaveSlots.file("inventory.cfg"))
	SaveSlots.create(3, _profile("Chen", "female"))
	SaveSlots.active_slot = 0
	var menu := MainMenu.new()
	menu.change_scene_enabled = false
	root.add_child(menu)
	await process_frame
	await process_frame
	for slot in 3:
		if menu.find_child("Slot%d" % (slot + 1), true, false) == null:
			errors.append("carte de la partie %d absente" % (slot + 1))
	if menu.find_child("Slot2", true, false).find_child("New", true, false) == null:
		errors.append("emplacement libre : bouton « Nouvelle partie »")
	if menu.find_child("Slot1", true, false).find_child("Play", true, false) == null:
		errors.append("partie existante : bouton « Jouer »")
	# Jouer la partie 1 : son sac est relu.
	var inventory := root.get_node("Inventory")
	inventory.call("clear_for_test")
	(menu.find_child("Slot1", true, false).find_child("Play", true, false) as Button).pressed.emit()
	if menu.started_slot != 1 or SaveSlots.active_slot != 1:
		errors.append("jouer la partie 1 : partie active %d" % SaveSlots.active_slot)
	if int(inventory.call("count_of", "item_wood")) != 5:
		errors.append("le sac de la partie 1 doit être rechargé")
	SaveSlots.active_slot = 0
	# Supprimer la partie 3 : demande de confirmation.
	(menu.find_child("Slot3", true, false).find_child("Delete", true, false) as Button).pressed.emit()
	await process_frame
	if menu.find_child("ConfirmDelete", true, false) == null:
		errors.append("la suppression demande une confirmation")
	(menu.find_child("Cancel", true, false) as Button).pressed.emit()
	await process_frame
	if not SaveSlots.slot_exists(3):
		errors.append("annuler ne supprime rien")
	(menu.find_child("Slot3", true, false).find_child("Delete", true, false) as Button).pressed.emit()
	await process_frame
	(menu.find_child("Confirm", true, false) as Button).pressed.emit()
	await process_frame
	if SaveSlots.slot_exists(3):
		errors.append("la partie 3 doit être supprimée après confirmation")
	# Nouvelle partie dans l'emplacement 2 : création du personnage puis départ.
	(menu.find_child("Slot2", true, false).find_child("New", true, false) as Button).pressed.emit()
	var creator := menu.find_child("CharacterCreator", true, false) as CharacterCreator
	if not creator.visible:
		errors.append("nouvelle partie : l'écran de création s'ouvre")
	creator.profile.hero_name = "  Zoé  "
	creator.profile.gender = "female"
	creator._on_done()
	if menu.started_slot != 2 or not SaveSlots.slot_exists(2):
		errors.append("nouvelle partie : la partie 2 doit démarrer (%d)" % menu.started_slot)
	if String(SaveSlots.info(2)["name"]) != "Zoé" or String(SaveSlots.info(2)["gender"]) != "female":
		errors.append("nouvelle partie : nom et genre enregistrés : %s" % str(SaveSlots.info(2)))
	if CharacterProfile.load_saved().hero_name != "Zoé":
		errors.append("le personnage est enregistré dans la nouvelle partie")
	if int(inventory.call("count_of", "item_wood")) != 0:
		errors.append("une nouvelle partie démarre avec un sac vide")
	paused = false
	menu.queue_free()
	inventory.call("clear_for_test")
	_wipe_all()
	if errors.is_empty():
		print("PASS test_save_slots")
		quit(0)
	else:
		for e in errors:
			print("FAIL: ", e)
		quit(1)
