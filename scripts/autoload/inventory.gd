extends Node

signal item_added(item_id: String, amount: int)
signal item_removed(item_id: String, amount: int)
signal equipped_changed(item_id: String)
## Vêtements portés : un par emplacement (tête, corps, pieds, dos).
signal worn_changed()

## Outils qui peuvent être équipés (un seul à la fois, dans la barre d'outils du HUD).
const TOOLS := ["tool_stone_axe", "tool_sickle", "tool_hoe", "tool_watering_can", "tool_hunting_bow", "tool_fishing_rod", "tool_knife"]

const SAVE_NAME := "inventory.cfg"

# --- Poids du sac ---------------------------------------------------------------------
## Poids (kg) par objet ; un objet inconnu compte DEFAULT_WEIGHT kg.
const DEFAULT_WEIGHT := 0.5
const WEIGHTS := {
	"item_wood": 1.0, "item_stone": 2.0, "item_pelt": 1.5, "item_wool": 0.5,
	"item_berries": 0.3, "item_vegetables": 0.5, "item_wheat": 1.0, "item_seeds": 0.2,
	"item_grain_seeds": 0.2, "item_raw_meat": 0.8, "item_cooked_meat": 0.6,
	"item_fish": 0.8, "item_fish_big": 1.5, "item_grilled_fish": 0.6, "item_grilled_fish_big": 1.2,
	"item_egg": 0.1, "item_boiled_egg": 0.2, "item_milk": 1.0, "item_bread": 0.5,
	"item_soup": 1.0, "item_roast_vegetables": 0.5, "item_relic": 0.5, "arrow": 0.05,
	"tool_stone_axe": 2.5, "tool_sickle": 1.5, "tool_hoe": 2.0, "tool_watering_can": 2.0,
	"tool_hunting_bow": 1.5, "tool_fishing_rod": 1.5, "tool_knife": 0.5,
	"gear_straw_hat": 0.3, "gear_wool_shirt": 1.0, "gear_wool_trousers": 1.0,
	"gear_leather_gloves": 0.4, "gear_hide_boots": 0.8, "armor_fur_cloak": 3.0, "gear_backpack": 1.0,
	"building_campfire": 5.0, "building_shelter": 12.0, "building_pen": 15.0,
	"building_palisade": 8.0, "building_farm_plot": 6.0,
	"furniture_chest": 10.0, "furniture_camp_bed": 6.0, "furniture_wool_bed": 8.0,
}
## Capacité du sac (kg) : de base, et avec le sac à dos porté.
const BASE_CAPACITY := 30.0
const BACKPACK_BONUS := 20.0
## Au-delà de ce taux de remplissage, la vitesse baisse ; à 120 %, minimum.
const COMFORT_FRACTION := 0.6
const FULL_FRACTION := 1.2

static func item_weight(item_id: String) -> float:
	return float(WEIGHTS.get(item_id, DEFAULT_WEIGHT))

## Facteur de vitesse selon le taux de remplissage : 1.0 à l'aise, 0.5 sac plein à craquer.
static func speed_factor(fraction: float) -> float:
	if fraction <= COMFORT_FRACTION:
		return 1.0
	if fraction >= FULL_FRACTION:
		return 0.5
	return lerpf(1.0, 0.5, (fraction - COMFORT_FRACTION) / (FULL_FRACTION - COMFORT_FRACTION))

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

# --- Poids -----------------------------------------------------------------------------

func total_weight() -> float:
	var total := 0.0
	for item_id in _items:
		total += item_weight(String(item_id)) * float(_items[item_id])
	return total

## Capacité actuelle du sac (kg) : le sac à dos porté ajoute BACKPACK_BONUS.
func capacity() -> float:
	return BASE_CAPACITY + (BACKPACK_BONUS if is_worn("gear_backpack") else 0.0)

func weight_fraction() -> float:
	var cap := capacity()
	return total_weight() / cap if cap > 0.0 else 0.0

func is_overloaded() -> bool:
	return weight_fraction() > 1.0

## Facteur de vitesse appliqué au joueur selon la charge actuelle.
func get_speed_factor() -> float:
	return speed_factor(weight_fraction())

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
