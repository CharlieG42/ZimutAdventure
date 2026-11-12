extends Node
## Exploration : brouillard de la carte (cases de 16 m dévoilées autour du joueur), sites à découvrir
## (ruines, grottes, panneaux) et voyage rapide entre sites découverts. Sauvegardé dans
## user://exploration.cfg.

signal site_discovered(site_id: String)
signal fog_changed
signal blessing_gained(count: int)

const SAVE_PATH := "user://exploration.cfg"
const GRID := 32
const REVEAL_RADIUS := 42.0
const DISCOVER_DISTANCE := 14.0
const TRAVEL_LEVEL := 3
const TRAVEL_HUNGER := 0.08
const TRAVEL_THIRST := 0.05
const CHECK_SECONDS := 0.5
const START_SITE := "start"
## Bénédictions de l'autel, dans l'ordre : endurance, chemins anciens, fortune.
const MAX_BLESSINGS := 3
const ENDURANCE_FACTOR := 0.8
const FORTUNE_BONUS := 0.15

var world_size: float = 512.0
var _cells := PackedByteArray()
## id -> {"name": clé de traduction, "pos": Vector3, "kind": String, "found": bool}
var _sites: Dictionary = {}
var _autosave: bool = DisplayServer.get_name() != "headless"
var _timer: float = 0.0
var _dirty: bool = false
var _save_timer: float = 0.0
var blessings: int = 0

func _ready() -> void:
	_cells.resize(GRID * GRID)
	_load()

# --- Brouillard ----------------------------------------------------------------------------

func _cell_of(x: float, z: float) -> Vector2i:
	var u := (x / world_size + 0.5) * float(GRID)
	var v := (z / world_size + 0.5) * float(GRID)
	return Vector2i(clampi(int(floor(u)), 0, GRID - 1), clampi(int(floor(v)), 0, GRID - 1))

func is_revealed(x: float, z: float) -> bool:
	var cell := _cell_of(x, z)
	return _cells[cell.y * GRID + cell.x] != 0

func is_cell_revealed(cx: int, cz: int) -> bool:
	return _cells[cz * GRID + cx] != 0

## Dévoile les cases dont le centre est à moins de `radius` mètres du point.
func reveal(x: float, z: float, radius: float = REVEAL_RADIUS) -> void:
	var cell_size := world_size / float(GRID)
	var changed := false
	var span := int(ceil(radius / cell_size)) + 1
	var center := _cell_of(x, z)
	for cz in range(maxi(center.y - span, 0), mini(center.y + span, GRID - 1) + 1):
		for cx in range(maxi(center.x - span, 0), mini(center.x + span, GRID - 1) + 1):
			var wx := (float(cx) + 0.5) / float(GRID) * world_size - world_size * 0.5
			var wz := (float(cz) + 0.5) / float(GRID) * world_size - world_size * 0.5
			if Vector2(wx - x, wz - z).length() <= radius and _cells[cz * GRID + cx] == 0:
				_cells[cz * GRID + cx] = 1
				changed = true
	if changed:
		_dirty = true
		fog_changed.emit()

func revealed_count() -> int:
	var total := 0
	for value in _cells:
		total += int(value)
	return total

# --- Sites ----------------------------------------------------------------------------------------

func register_site(site_id: String, name_key: String, pos: Vector3, kind: String) -> void:
	var known: Dictionary = _sites.get(site_id, {})
	_sites[site_id] = {"name": name_key, "pos": pos, "kind": kind, "found": bool(known.get("found", false))}

func clear_sites() -> void:
	_sites.clear()

func get_site(site_id: String) -> Dictionary:
	return _sites.get(site_id, {})

func get_sites() -> Dictionary:
	return _sites

func get_discovered_ids() -> Array:
	var ids: Array = []
	for site_id in _sites:
		if bool(_sites[site_id]["found"]):
			ids.append(site_id)
	return ids

func is_discovered(site_id: String) -> bool:
	return bool(_sites.get(site_id, {}).get("found", false))

## Marque le site comme découvert (récompense unique). Retourne true s'il était nouveau.
func discover(site_id: String, silent: bool = false) -> bool:
	if not _sites.has(site_id) or bool(_sites[site_id]["found"]):
		return false
	_sites[site_id]["found"] = true
	var pos: Vector3 = _sites[site_id]["pos"]
	reveal(pos.x, pos.z, REVEAL_RADIUS * 1.6)
	if not silent:
		var progression := InteractionManager.get_progression()
		if progression != null:
			progression.call("add_stat", "stat_discovered", 1)
			progression.call("add_xp_for", "discover")
		var sfx := InteractionManager.get_sfx()
		if sfx != null and sfx.has_method("play_event"):
			sfx.call("play_event", "chime")
		_toast(tr("TOAST_DISCOVERED") % tr(String(_sites[site_id]["name"])))
	_dirty = true
	site_discovered.emit(site_id)
	_save()
	return true

# --- Autel des reliques ----------------------------------------------------------------------

## Offre une relique : accorde la bénédiction suivante. Retourne son numéro, 0 si impossible.
func offer_relic() -> int:
	if blessings >= MAX_BLESSINGS:
		return 0
	var inventory := InteractionManager.get_inventory()
	if inventory == null or not bool(inventory.call("remove_item", "item_relic", 1)):
		return 0
	blessings += 1
	_dirty = true
	_save()
	blessing_gained.emit(blessings)
	return blessings

## Endurance : faim et soif s'usent moins vite.
func drain_factor() -> float:
	return ENDURANCE_FACTOR if blessings >= 1 else 1.0

## Chemins anciens : le voyage rapide ne coûte plus rien.
func travel_is_free() -> bool:
	return blessings >= 2

## Fortune : chance de butin en plus.
func loot_bonus() -> float:
	return FORTUNE_BONUS if blessings >= 3 else 0.0

# --- Voyage rapide ---------------------------------------------------------------------------------------

## Retourne "" si le voyage est possible, sinon la clé de traduction du refus.
func can_travel(site_id: String) -> String:
	if not is_discovered(site_id):
		return "TOAST_TRAVEL_UNKNOWN"
	var progression := InteractionManager.get_progression()
	if progression != null and not bool(progression.call("meets_level", TRAVEL_LEVEL)):
		return "TOAST_TRAVEL_LEVEL"
	var survival := InteractionManager.get_survival()
	if survival != null and not travel_is_free() and (float(survival.call("get_hunger")) < TRAVEL_HUNGER or float(survival.call("get_thirst")) < TRAVEL_THIRST):
		return "TOAST_TRAVEL_TIRED"
	return ""

func fast_travel(site_id: String, player: Node3D) -> String:
	var error := can_travel(site_id)
	if error != "":
		return error
	if player == null or not is_instance_valid(player):
		return "TOAST_TRAVEL_UNKNOWN"
	var site: Dictionary = _sites[site_id]
	var pos: Vector3 = site["pos"]
	if player.has_method("dismount") and player.has_method("is_mounted") and bool(player.call("is_mounted")):
		player.call("dismount")
	player.global_position = pos + Vector3(2.5, 1.5, 2.5)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	var survival := InteractionManager.get_survival()
	if survival != null and not travel_is_free():
		survival.call("consume", TRAVEL_HUNGER, TRAVEL_THIRST)
	var progression := InteractionManager.get_progression()
	if progression != null:
		progression.call("add_stat", "stat_travels", 1)
	reveal(pos.x, pos.z)
	return ""

# --- Boucle ------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_timer += delta
	_save_timer += delta
	if _save_timer > 15.0:
		_save_timer = 0.0
		if _dirty:
			_save()
	if _timer < CHECK_SECONDS:
		return
	_timer = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	reveal(player.global_position.x, player.global_position.z)
	for site_id in _sites.keys():
		if bool(_sites[site_id]["found"]):
			continue
		var pos: Vector3 = _sites[site_id]["pos"]
		if Vector2(pos.x - player.global_position.x, pos.z - player.global_position.z).length() <= DISCOVER_DISTANCE:
			discover(site_id)

func _toast(message: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 2.6)

# --- Sauvegarde ----------------------------------------------------------------------------------------------------

func _load() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var saved: PackedByteArray = config.get_value("fog", "cells", PackedByteArray())
	if saved.size() == GRID * GRID:
		_cells = saved
	_pending_found = config.get_value("sites", "found", [])
	_looted = config.get_value("sites", "looted", [])
	blessings = int(config.get_value("altar", "blessings", 0))
	for site_id in _pending_found:
		if _sites.has(site_id):
			_sites[site_id]["found"] = true

## Sites déjà découverts lors d'une partie précédente (appliqués à l'enregistrement du site).
var _pending_found: Array = []
var _looted: Array = []

func is_looted(site_id: String) -> bool:
	return _looted.has(site_id)

func mark_looted(site_id: String) -> void:
	if not _looted.has(site_id):
		_looted.append(site_id)
		_dirty = true
		_save()

func apply_saved_discoveries() -> void:
	for site_id in _pending_found:
		if _sites.has(site_id):
			_sites[site_id]["found"] = true

func _save() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	config.set_value("fog", "cells", _cells)
	config.set_value("sites", "found", get_discovered_ids())
	config.set_value("sites", "looted", _looted)
	config.set_value("altar", "blessings", blessings)
	config.save(SAVE_PATH)
	_dirty = false

## API de test : repart de zéro, sans disque ni brouillard dévoilé.
func clear_for_test() -> void:
	_autosave = false
	_cells = PackedByteArray()
	_cells.resize(GRID * GRID)
	_sites.clear()
	_pending_found = []
	_looted = []
	blessings = 0
