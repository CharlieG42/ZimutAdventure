class_name SaveSlots
extends RefCounted
## Parties sauvegardées (3 emplacements). Chaque partie a son dossier user://saves/slotN/ qui contient
## tous les fichiers .cfg du jeu (sac, quêtes, carte, personnage...) et un slot.cfg avec le nom du
## héros, son genre et la date de dernière partie. Tant qu'aucune partie n'est choisie (tests, lancement
## direct de la scène du monde), les fichiers vont dans user://saves/_none.
## Les réglages (musique, langue) restent communs à toutes les parties.

const MAX_SLOTS := 3
const ROOT := "user://saves"
const INFO_FILE := "slot.cfg"
const MIGRATED_FILE := "user://saves/migrated.cfg"
## Fichiers des anciennes versions (un seul jeu, à la racine de user://) : migrés vers la partie 1.
const LEGACY_FILES := ["inventory.cfg", "quests.cfg", "notebook.cfg", "progression.cfg", "survival.cfg",
		"exploration.cfg", "weather.cfg", "structures.cfg", "livestock.cfg", "tutorial.cfg", "character.cfg"]
## Gestionnaires globaux à relire quand on choisit une partie.
const RELOADED_AUTOLOADS := ["Inventory", "QuestManager", "Notebook", "Progression", "SurvivalManager",
		"Exploration", "Weather"]

## 0 = aucune partie choisie.
static var active_slot: int = 0

static func slot_dir(slot: int) -> String:
	return "%s/%s" % [ROOT, "_none" if slot <= 0 else "slot%d" % slot]

## Chemin d'un fichier de la partie active (le dossier est créé au besoin).
static func file(file_name: String) -> String:
	var dir := slot_dir(active_slot)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return "%s/%s" % [dir, file_name]

static func slot_exists(slot: int) -> bool:
	return slot >= 1 and slot <= MAX_SLOTS and FileAccess.file_exists("%s/%s" % [slot_dir(slot), INFO_FILE])

## Infos affichées sur la carte d'une partie ; "exists" est faux pour un emplacement vide.
static func info(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {"exists": false, "slot": slot}
	var config := ConfigFile.new()
	config.load("%s/%s" % [slot_dir(slot), INFO_FILE])
	return {
		"exists": true,
		"slot": slot,
		"name": String(config.get_value("slot", "name", "")),
		"gender": String(config.get_value("slot", "gender", "male")),
		"created": int(config.get_value("slot", "created", 0)),
		"last_played": int(config.get_value("slot", "last_played", 0)),
	}

static func first_free_slot() -> int:
	for slot in range(1, MAX_SLOTS + 1):
		if not slot_exists(slot):
			return slot
	return 0

static func _write_info(slot: int, profile_dict: Dictionary, created: int, last_played: int) -> void:
	var dir := slot_dir(slot)
	DirAccess.make_dir_recursive_absolute(dir)
	var config := ConfigFile.new()
	config.set_value("slot", "name", String(profile_dict.get("hero_name", "")))
	config.set_value("slot", "gender", String(profile_dict.get("gender", "male")))
	config.set_value("slot", "created", created)
	config.set_value("slot", "last_played", last_played)
	config.save("%s/%s" % [dir, INFO_FILE])

## Nouvelle partie : repart d'un dossier vide, enregistre le personnage et rend la partie active.
## `profile` est un CharacterProfile ; renvoie faux si l'emplacement est invalide.
static func create(slot: int, profile: Object) -> bool:
	if slot < 1 or slot > MAX_SLOTS:
		return false
	_wipe(slot)
	active_slot = slot
	profile.call("save")
	var now := int(Time.get_unix_time_from_system())
	_write_info(slot, profile.call("to_dict"), now, now)
	return true

## Choisit une partie existante et relit les gestionnaires globaux depuis ses fichiers.
static func activate(slot: int, tree: SceneTree = null) -> bool:
	if not slot_exists(slot):
		return false
	active_slot = slot
	var data := info(slot)
	_write_info(slot, {"hero_name": data["name"], "gender": data["gender"]}, int(data["created"]),
			int(Time.get_unix_time_from_system()))
	if tree != null:
		reload_autoloads(tree)
	return true

static func reload_autoloads(tree: SceneTree) -> void:
	for autoload_name: String in RELOADED_AUTOLOADS:
		var node := tree.root.get_node_or_null(autoload_name)
		if node != null and node.has_method("reload_from_disk"):
			node.call("reload_from_disk")

## Met à jour nom / genre de la partie active (le joueur modifie son personnage en cours d'aventure).
static func update_active_info(profile: Object) -> void:
	if not slot_exists(active_slot):
		return
	var data := info(active_slot)
	_write_info(active_slot, profile.call("to_dict"), int(data["created"]), int(data["last_played"]))

static func delete(slot: int) -> void:
	if slot < 1 or slot > MAX_SLOTS:
		return
	_wipe(slot)
	if active_slot == slot:
		active_slot = 0

static func _wipe(slot: int) -> void:
	var dir := slot_dir(slot)
	if not DirAccess.dir_exists_absolute(dir):
		return
	for entry in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute("%s/%s" % [dir, entry])
	DirAccess.remove_absolute(dir)

## Première ouverture après la mise à jour : la partie existante (fichiers à la racine) devient la partie 1.
static func migrate_legacy() -> void:
	if FileAccess.file_exists(MIGRATED_FILE):
		return
	DirAccess.make_dir_recursive_absolute(ROOT)
	var any_legacy := false
	for legacy in LEGACY_FILES:
		if FileAccess.file_exists("user://%s" % legacy):
			any_legacy = true
	if any_legacy and not slot_exists(1):
		var dir := slot_dir(1)
		DirAccess.make_dir_recursive_absolute(dir)
		for legacy in LEGACY_FILES:
			var source := "user://%s" % legacy
			if FileAccess.file_exists(source):
				DirAccess.copy_absolute(source, "%s/%s" % [dir, legacy])
		var hero := {"hero_name": "", "gender": "male"}
		var config := ConfigFile.new()
		if config.load("user://character.cfg") == OK:
			var saved: Dictionary = config.get_value("character", "profile", {})
			hero["gender"] = String(saved.get("gender", "male"))
			hero["hero_name"] = String(saved.get("hero_name", ""))
		var now := int(Time.get_unix_time_from_system())
		_write_info(1, hero, now, now)
	var marker := ConfigFile.new()
	marker.set_value("migration", "done", true)
	marker.save(MIGRATED_FILE)
