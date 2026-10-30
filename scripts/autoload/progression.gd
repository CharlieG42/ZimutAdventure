extends Node
## Niveau du personnage : l'expérience (XP) vient de la collecte, de la fabrication, de la
## chasse, de la coupe d'arbres, de la cueillette et surtout des quêtes. Chaque niveau
## apporte des bonus (endurance, butin) et débloque des recettes (`level` dans CraftManager).
## Compteurs d'actions (`stat_*`) : ils servent d'objectifs aux quêtes (arbres coupés, etc.).

signal xp_changed(level: int, xp: int, needed: int)
signal level_up(level: int)
signal stat_changed(stat: String, value: int)

const SAVE_PATH := "user://progression.cfg"
const MAX_LEVEL := 20
## XP gagnée par action.
const XP := {
	"collect": 2,
	"craft": 12,
	"chop": 14,
	"harvest": 8,
	"hunt": 30,
	"quest": 40,
}
## Bonus par niveau au-delà du niveau 1.
const STAMINA_REGEN_PER_LEVEL := 0.06
const BONUS_LOOT_PER_LEVEL := 0.06

var level: int = 1
var _xp: int = 0
var _stats: Dictionary = {}
## Pas de sauvegarde en headless : les tests ne doivent pas se polluer d'un run à l'autre.
var _autosave: bool = DisplayServer.get_name() != "headless"
## Les tests headless fabriquent sans condition de niveau (comme les récompenses de quêtes).
var _enforce_levels: bool = DisplayServer.get_name() != "headless"

func _ready() -> void:
	_load()
	var inventory := InteractionManager.get_inventory()
	if inventory != null:
		inventory.connect("item_added", _on_item_added)
	var craft := get_node_or_null("/root/CraftManager")
	if craft != null:
		craft.connect("crafted", _on_crafted)

# --- Niveau --------------------------------------------------------------------------

## XP nécessaire pour passer du niveau `for_level` au suivant.
static func xp_needed(for_level: int) -> int:
	return 45 + 30 * (maxi(for_level, 1) - 1)

func get_level() -> int:
	return level

func get_xp() -> int:
	return _xp

func get_xp_needed() -> int:
	return xp_needed(level)

func get_xp_fraction() -> float:
	if level >= MAX_LEVEL:
		return 1.0
	return clampf(float(_xp) / float(get_xp_needed()), 0.0, 1.0)

func add_xp(amount: int) -> void:
	if amount <= 0 or level >= MAX_LEVEL:
		return
	_xp += amount
	while level < MAX_LEVEL and _xp >= xp_needed(level):
		_xp -= xp_needed(level)
		level += 1
		level_up.emit(level)
		_announce_level(level)
	if level >= MAX_LEVEL:
		_xp = 0
	xp_changed.emit(level, _xp, get_xp_needed())
	_save()

func add_xp_for(action: String) -> void:
	add_xp(int(XP.get(action, 0)))

# --- Bonus et conditions ---------------------------------------------------------------

func stamina_regen_multiplier() -> float:
	return 1.0 + STAMINA_REGEN_PER_LEVEL * float(level - 1)

## Chance (0..1) d'obtenir une unité de plus en récoltant (coupe, cueillette, rochers).
func bonus_loot_chance() -> float:
	return clampf(BONUS_LOOT_PER_LEVEL * float(level - 1), 0.0, 0.8)

## Quantité finale d'une récolte : `base` plus, éventuellement, 1 unité de bonus.
func roll_loot(base: int) -> int:
	return base + (1 if randf() < bonus_loot_chance() else 0)

func meets_level(required: int) -> bool:
	return not _enforce_levels or level >= required

## Texte (clé de traduction) des bonus du niveau, pour l'annonce de montée de niveau.
func perk_text(for_level: int) -> String:
	return "PERK_STAMINA_LOOT" if for_level > 1 else ""

# --- Compteurs -------------------------------------------------------------------------

func add_stat(stat: String, amount: int = 1) -> void:
	_stats[stat] = int(_stats.get(stat, 0)) + amount
	stat_changed.emit(stat, int(_stats[stat]))
	_save()

func get_stat(stat: String) -> int:
	return int(_stats.get(stat, 0))

# --- Sources d'XP ------------------------------------------------------------------------

func _on_item_added(item_id: String, _amount: int) -> void:
	# Seules les ressources brutes rapportent un peu : ni outils fabriqués, ni récompenses.
	if item_id.begins_with("item_"):
		add_xp_for("collect")

func _on_crafted(_recipe_id: String) -> void:
	add_xp_for("craft")

func _announce_level(new_level: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		var message: String = tr("TOAST_LEVEL_UP") % new_level
		var perk := perk_text(new_level)
		if perk != "":
			message += "\n" + tr(perk) % [int(round(STAMINA_REGEN_PER_LEVEL * 100.0)), int(round(BONUS_LOOT_PER_LEVEL * 100.0))]
		hud.show_toast(message, 3.5)

# --- Sauvegarde --------------------------------------------------------------------------

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	level = clampi(int(config.get_value("progress", "level", 1)), 1, MAX_LEVEL)
	_xp = maxi(int(config.get_value("progress", "xp", 0)), 0)
	for key in config.get_section_keys("stats"):
		_stats[key] = int(config.get_value("stats", key, 0))

func _save() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	config.set_value("progress", "level", level)
	config.set_value("progress", "xp", _xp)
	for key in _stats:
		config.set_value("stats", key, int(_stats[key]))
	config.save(SAVE_PATH)

## API de test : repart de zéro, sans écrire sur le disque ; `enforce` active les niveaux requis.
func clear_for_test(enforce: bool = false) -> void:
	_autosave = false
	level = 1
	_xp = 0
	_stats.clear()
	_enforce_levels = enforce
