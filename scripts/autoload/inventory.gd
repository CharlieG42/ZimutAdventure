extends Node

signal item_added(item_id: String, amount: int)
signal item_removed(item_id: String, amount: int)
signal equipped_changed(item_id: String)
## Vêtements portés : un par emplacement (tête, corps, pieds, dos).
signal worn_changed()

## Outils qui peuvent être équipés (un seul à la fois, dans la barre d'outils du HUD).
const TOOLS := ["tool_stone_axe", "tool_sickle", "tool_hoe", "tool_watering_can", "tool_hunting_bow", "tool_fishing_rod", "tool_knife", "tool_pickaxe"]

const SAVE_NAME := "inventory.cfg"

# --- Poids du sac ---------------------------------------------------------------------
## Poids (kg) par objet ; un objet inconnu compte DEFAULT_WEIGHT kg.
const DEFAULT_WEIGHT := 0.5
## Poids revus à la baisse (on atteignait trop vite la limite) ; les vêtements portés ne
## comptent pas (voir total_weight).
const WEIGHTS := {
	"item_wood": 0.5, "item_stone": 0.8, "item_pelt": 0.6, "item_wool": 0.2,
	"item_berries": 0.1, "item_vegetables": 0.3, "item_wheat": 0.4, "item_seeds": 0.05,
	"item_grain_seeds": 0.05, "item_raw_meat": 0.5, "item_cooked_meat": 0.4,
	"item_fish": 0.5, "item_fish_big": 1.0, "item_grilled_fish": 0.4, "item_grilled_fish_big": 0.8,
	"item_egg": 0.05, "item_boiled_egg": 0.05, "item_milk": 0.5, "item_bread": 0.3,
	"item_soup": 0.5, "item_roast_vegetables": 0.3, "item_relic": 0.3, "arrow": 0.02,
	"tool_stone_axe": 1.5, "tool_sickle": 0.8, "tool_hoe": 1.2, "tool_watering_can": 1.2,
	"tool_hunting_bow": 0.8, "tool_fishing_rod": 0.8, "tool_knife": 0.3, "tool_pickaxe": 1.5,
	"item_iron_ore": 1.0, "item_iron_ingot": 0.8, "building_furnace": 8.0,
	"gear_straw_hat": 0.3, "gear_wool_shirt": 0.6, "gear_wool_trousers": 0.6,
	"gear_leather_gloves": 0.3, "gear_hide_boots": 0.6, "armor_fur_cloak": 1.5, "gear_backpack": 0.8,
	"building_campfire": 3.0, "building_shelter": 6.0, "building_pen": 8.0,
	"building_palisade": 3.0, "building_farm_plot": 3.0,
	"furniture_chest": 5.0, "furniture_camp_bed": 3.0, "furniture_wool_bed": 4.0,
}
## Capacité du sac (kg) : de base, + 1 kg par niveau du joueur (jusqu'à +30), + le sac à dos
## porté selon son niveau (voir GEAR_STATS).
const BASE_CAPACITY := 40.0
const CAPACITY_PER_LEVEL := 1.0
const MAX_LEVEL_CAPACITY := 30.0
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

## Amélioration des vêtements (niveaux 1 à 3) : effets par niveau, coût du niveau suivant et
## niveau de joueur requis.
##  heat : °C ressentis · damage : part des dégâts évitée · thirst : part de soif en moins
##  speed : bonus de vitesse · capacity : kg en plus dans le sac
const GEAR_MAX_LEVEL := 3
const GEAR_STATS := {
	"gear_straw_hat": {"thirst": [0.2, 0.3, 0.4]},
	"gear_wool_shirt": {"heat": [2.0, 3.0, 4.5]},
	"armor_fur_cloak": {"heat": [7.0, 8.5, 10.0], "damage": [0.35, 0.45, 0.55]},
	"gear_leather_gloves": {"heat": [1.5, 2.5, 3.5]},
	"gear_wool_trousers": {"heat": [2.0, 3.0, 4.5]},
	"gear_hide_boots": {"speed": [0.08, 0.12, 0.16]},
	"gear_backpack": {"capacity": [25.0, 45.0, 70.0]},
}
const GEAR_UPGRADE_COSTS := {
	"gear_straw_hat": {2: {"item_wheat": 4}, 3: {"item_wheat": 6, "item_wool": 2}},
	"gear_wool_shirt": {2: {"item_wool": 3}, 3: {"item_wool": 4, "item_pelt": 1}},
	"armor_fur_cloak": {2: {"item_pelt": 3, "item_wool": 2}, 3: {"item_pelt": 4, "item_wool": 3, "item_relic": 1}},
	"gear_leather_gloves": {2: {"item_pelt": 2}, 3: {"item_pelt": 3, "item_wool": 1}},
	"gear_wool_trousers": {2: {"item_wool": 3}, 3: {"item_wool": 4, "item_pelt": 1}},
	"gear_hide_boots": {2: {"item_pelt": 2, "item_wood": 2}, 3: {"item_pelt": 3, "item_relic": 1}},
	"gear_backpack": {2: {"item_pelt": 3, "item_wood": 4}, 3: {"item_pelt": 4, "item_wool": 3, "item_wood": 6}},
}
const GEAR_UPGRADE_PLAYER_LEVEL := {2: 4, 3: 8}

var _items: Dictionary = {}
var _autosave: bool = true
var _equipped: String = ""
## emplacement → vêtement porté
var _worn: Dictionary = {}
## vêtement → niveau (1 par défaut)
var _gear_levels: Dictionary = {}

func _ready() -> void:
	_load()

## Relit le sac de la partie choisie (menu de démarrage).
func reload_from_disk() -> void:
	_items.clear()
	_equipped = ""
	_worn.clear()
	_worn.clear()
	_gear_levels.clear()
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

# --- Amélioration des vêtements ----------------------------------------------------------

func gear_level(item_id: String) -> int:
	return int(_gear_levels.get(item_id, 1))

func can_upgrade_gear(item_id: String) -> bool:
	return GEAR.has(item_id) and has_item(item_id, 1) and gear_level(item_id) < GEAR_MAX_LEVEL

func gear_upgrade_cost(item_id: String) -> Dictionary:
	if not GEAR.has(item_id) or gear_level(item_id) >= GEAR_MAX_LEVEL:
		return {}
	return ((GEAR_UPGRADE_COSTS[item_id] as Dictionary)[gear_level(item_id) + 1] as Dictionary).duplicate()

func gear_upgrade_required_level(item_id: String) -> int:
	return int(GEAR_UPGRADE_PLAYER_LEVEL.get(gear_level(item_id) + 1, 1))

## Améliore un vêtement possédé. Renvoie "" ou la clé d'erreur.
func upgrade_gear(item_id: String) -> String:
	if not GEAR.has(item_id) or not has_item(item_id, 1):
		return "TOAST_CANNOT_UPGRADE"
	if gear_level(item_id) >= GEAR_MAX_LEVEL:
		return "TOAST_MAX_LEVEL"
	var progression := get_node_or_null("/root/Progression")
	if progression != null and int(progression.call("get_level")) < gear_upgrade_required_level(item_id):
		return "TOAST_UPGRADE_LEVEL"
	var cost := gear_upgrade_cost(item_id)
	for ingredient in cost:
		if count_of(ingredient) < int(cost[ingredient]):
			return "TOAST_UPGRADE_MISSING"
	for ingredient in cost:
		remove_item(ingredient, int(cost[ingredient]))
	_gear_levels[item_id] = gear_level(item_id) + 1
	worn_changed.emit()
	_save()
	return ""

## Valeur d'un effet pour un vêtement à un niveau donné (0 si sans cet effet).
static func gear_stat_value(item_id: String, stat: String, level: int) -> float:
	var stats: Dictionary = GEAR_STATS.get(item_id, {})
	if not stats.has(stat):
		return 0.0
	var values: Array = stats[stat]
	return float(values[clampi(level, 1, values.size()) - 1])

## Somme d'un effet sur les vêtements portés (à leur niveau).
func worn_stat(stat: String) -> float:
	var total := 0.0
	for item_id in get_worn():
		total += gear_stat_value(item_id, stat, gear_level(item_id))
	return total

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
		var count := int(_items[item_id])
		# Un vêtement porté est sur le dos du personnage, pas dans le sac.
		if is_worn(String(item_id)):
			count -= 1
		total += item_weight(String(item_id)) * float(count)
	return total

## Capacité actuelle du sac (kg) : base + niveau du joueur + sac à dos porté (selon son niveau).
func capacity() -> float:
	var level_bonus := 0.0
	var progression := get_node_or_null("/root/Progression")
	if progression != null:
		level_bonus = minf(MAX_LEVEL_CAPACITY, float(int(progression.call("get_level")) - 1) * CAPACITY_PER_LEVEL)
	return BASE_CAPACITY + level_bonus + worn_stat("capacity")

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
	var levels = config.get_value("state", "gear_levels", {})
	if levels is Dictionary:
		for item_id in levels:
			if GEAR.has(item_id):
				_gear_levels[item_id] = clampi(int(levels[item_id]), 1, GEAR_MAX_LEVEL)
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
	config.set_value("state", "gear_levels", _gear_levels)
	config.save(SaveSlots.file(SAVE_NAME))

func clear_for_test() -> void:
	_autosave = false
	_items.clear()
	_equipped = ""
	_worn.clear()
	_gear_levels.clear()
