extends Node

signal item_added(item_id: String, amount: int)
signal item_removed(item_id: String, amount: int)
signal equipped_changed(item_id: String)
## Vêtements portés : un par emplacement (tête, corps, pieds, dos).
signal worn_changed()

## Outils qui peuvent être équipés (un seul à la fois, dans la barre d'outils du HUD).
const TOOLS := ["tool_stone_axe", "tool_sickle", "tool_hoe", "tool_watering_can", "tool_hunting_bow", "tool_fishing_rod", "tool_knife"]

const SAVE_NAME := "inventory.cfg"

## Emplacements de vêtements, dans l'ordre de la fenêtre Personnage.
const GEAR_SLOTS := ["head", "torso", "body", "hands", "legs", "feet", "back"]
## Vêtement → emplacement (« body » = cape, par-dessus la chemise « torso »).
const GEAR := {
	"gear_straw_hat": "head",
	"gear_wool_shirt": "torso",
	"armor_fur_cloak": "body",
	"gear_leather_gloves": "hands",
	"gear_wool_trousers": "legs",
	"gear_hide_boots": "feet",
	"gear_backpack": "back",
}

var _items: Dictionary = {}
var _autosave: bool = true
var _equipped: String = ""
## emplacement → vêtement porté
var _worn: Dictionary = {}

func _ready() -> void:
	_load()

## Relit le sac de la partie choisie (menu de démarrage).
func reload_from_disk() -> void:
	_items.clear()
	_equipped = ""
	_worn.clear()
	_worn.clear()
	_load()

func add_item(item_id: String, amount: int = 1) -> void:
	_items[item_id] = int(_items.get(item_id, 0)) + amount
	item_added.emit(item_id, amount)
	# Premier outil obtenu : équipé d'office, pour que le joueur voie tout de suite à quoi il sert.
	if TOOLS.has(item_id) and _equipped == "":
		equip(item_id)
	# Premier vêtement d'un emplacement : porté d'office.
	if GEAR.has(item_id) and not _worn.has(GEAR[item_id]):
		_worn[GEAR[item_id]] = item_id
		worn_changed.emit()
	_save()

func remove_item(item_id: String, amount: int = 1) -> bool:
	if count_of(item_id) < amount:
		return false
	_items[item_id] = int(_items[item_id]) - amount
	if int(_items[item_id]) <= 0:
		_items.erase(item_id)
	item_removed.emit(item_id, amount)
	if _equipped == item_id and count_of(item_id) <= 0:
		unequip()
	if GEAR.has(item_id) and count_of(item_id) <= 0 and _worn.get(GEAR[item_id]) == item_id:
		_worn.erase(GEAR[item_id])
		worn_changed.emit()
	_save()
	return true

## Équipe un outil possédé. Renvoie false si ce n'est pas un outil ou s'il manque.
func equip(item_id: String) -> bool:
	if not TOOLS.has(item_id) or not has_item(item_id, 1):
		return false
	_equipped = item_id
	equipped_changed.emit(_equipped)
	_save()
	return true

func unequip() -> void:
	if _equipped == "":
		return
	_equipped = ""
	equipped_changed.emit("")
	_save()

# --- Vêtements -------------------------------------------------------------------------

## Porte un vêtement possédé (il remplace celui du même emplacement). false sinon.
func wear(item_id: String) -> bool:
	if not GEAR.has(item_id) or not has_item(item_id, 1):
		return false
	_worn[GEAR[item_id]] = item_id
	worn_changed.emit()
	_save()
	return true

## Retire le vêtement d'un emplacement (il reste dans le sac).
func take_off(slot: String) -> void:
	if not _worn.has(slot):
		return
	_worn.erase(slot)
	worn_changed.emit()
	_save()

func is_worn(item_id: String) -> bool:
	return GEAR.has(item_id) and _worn.get(GEAR[item_id], "") == item_id

func worn_in(slot: String) -> String:
	return String(_worn.get(slot, ""))

func get_worn() -> Array:
	var worn: Array = []
	for slot in GEAR_SLOTS:
		if _worn.has(slot):
			worn.append(_worn[slot])
	return worn

## Vêtements possédés pour un emplacement.
func owned_gear(slot: String) -> Array:
	var owned: Array = []
	for item_id in GEAR:
		if GEAR[item_id] == slot and has_item(item_id, 1):
			owned.append(item_id)
	return owned

func get_equipped() -> String:
	return _equipped

func is_equipped(item_id: String) -> bool:
	return _equipped != "" and _equipped == item_id

## Outils possédés, dans l'ordre de la barre d'outils.
func get_owned_tools() -> Array:
	var owned: Array = []
	for tool_id in TOOLS:
		if has_item(tool_id, 1):
			owned.append(tool_id)
	return owned

func count_of(item_id: String) -> int:
	return int(_items.get(item_id, 0))

func has_item(item_id: String, amount: int = 1) -> bool:
	return count_of(item_id) >= amount

func get_all() -> Dictionary:
	return _items.duplicate()

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SaveSlots.file(SAVE_NAME)) != OK:
		return
	for key in config.get_section_keys("items"):
		_items[key] = config.get_value("items", key, 0)
	var saved_tool := String(config.get_value("state", "equipped", ""))
	if TOOLS.has(saved_tool) and has_item(saved_tool, 1):
		_equipped = saved_tool
	if config.has_section_key("state", "worn"):
		for item_id in config.get_value("state", "worn", []):
			if GEAR.has(item_id) and has_item(item_id, 1):
				_worn[GEAR[item_id]] = item_id
	else:
		# Anciennes parties : tout vêtement possédé était porté.
		for item_id in GEAR:
			if has_item(item_id, 1):
				_worn[GEAR[item_id]] = item_id

func _save() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	for key in _items:
		config.set_value("items", key, int(_items[key]))
	config.set_value("state", "equipped", _equipped)
	config.set_value("state", "worn", get_worn())
	config.save(SaveSlots.file(SAVE_NAME))

func clear_for_test() -> void:
	_autosave = false
	_items.clear()
	_equipped = ""
	_worn.clear()
