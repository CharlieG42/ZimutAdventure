extends Node

signal item_added(item_id: String, amount: int)
signal item_removed(item_id: String, amount: int)
signal equipped_changed(item_id: String)

## Outils qui peuvent être équipés (un seul à la fois, dans la barre d'outils du HUD).
const TOOLS := ["tool_stone_axe", "tool_sickle", "tool_hunting_bow"]

const SAVE_PATH := "user://inventory.cfg"

var _items: Dictionary = {}
var _autosave: bool = true
var _equipped: String = ""

func _ready() -> void:
	_load()

func add_item(item_id: String, amount: int = 1) -> void:
	_items[item_id] = int(_items.get(item_id, 0)) + amount
	item_added.emit(item_id, amount)
	# Premier outil obtenu : équipé d'office, pour que le joueur voie tout de suite à quoi il sert.
	if TOOLS.has(item_id) and _equipped == "":
		equip(item_id)
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
	if config.load(SAVE_PATH) != OK:
		return
	for key in config.get_section_keys("items"):
		_items[key] = config.get_value("items", key, 0)
	var saved_tool := String(config.get_value("state", "equipped", ""))
	if TOOLS.has(saved_tool) and has_item(saved_tool, 1):
		_equipped = saved_tool

func _save() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	for key in _items:
		config.set_value("items", key, int(_items[key]))
	config.set_value("state", "equipped", _equipped)
	config.save(SAVE_PATH)

func clear_for_test() -> void:
	_autosave = false
	_items.clear()
	_equipped = ""
