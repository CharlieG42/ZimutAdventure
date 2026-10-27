extends Node

signal item_added(item_id: String, amount: int)
signal item_removed(item_id: String, amount: int)

const SAVE_PATH := "user://inventory.cfg"

var _items: Dictionary = {}
var _autosave: bool = true

func _ready() -> void:
	_load()

func add_item(item_id: String, amount: int = 1) -> void:
	_items[item_id] = int(_items.get(item_id, 0)) + amount
	item_added.emit(item_id, amount)
	_save()

func remove_item(item_id: String, amount: int = 1) -> bool:
	if count_of(item_id) < amount:
		return false
	_items[item_id] = int(_items[item_id]) - amount
	if int(_items[item_id]) <= 0:
		_items.erase(item_id)
	item_removed.emit(item_id, amount)
	_save()
	return true

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

func _save() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	for key in _items:
		config.set_value("items", key, int(_items[key]))
	config.save(SAVE_PATH)

func clear_for_test() -> void:
	_autosave = false
	_items.clear()
