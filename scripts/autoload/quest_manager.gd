extends Node
## Journal de quêtes : objectifs de collecte et de fabrication.
##
## La progression est CUMULATIVE (tout ce que le joueur a ramassé ou fabriqué depuis
## le début) : dépenser ses pierres pour fabriquer ne fait donc pas perdre une quête.
## Elle est sauvegardée dans user://quests.cfg. Une quête peut dépendre d'une autre
## (`requires`) : elle reste cachée (LOCKED) tant que la précédente n'est pas terminée.

signal quest_state_changed(quest_id: String, state: String)
signal quest_progress_changed(quest_id: String, have: int, goal: int)

enum State { LOCKED, ACTIVE, COMPLETED }

const SAVE_PATH := "user://quests.cfg"

## id -> titre, description, objet suivi, quantité, quête requise (optionnelle).
## `reward` : ressources offertes à la fin de la quête (elles aident à enchaîner les
## suivantes). `goal_item` est un id d'inventaire : une ressource ramassée (item_stone) ou un
## objet fabriqué (tool_stone_axe : CraftManager le dépose dans le sac).
const QUESTS := {
	"quest_first_stone": {
		"title": "QUEST_FIRST_STONE_TITLE",
		"description": "QUEST_FIRST_STONE_DESC",
		"goal_item": "item_stone",
		"goal_count": 3,
		"reward": {"item_wood": 2},
	},
	"quest_warm_fire": {
		"title": "QUEST_WARM_FIRE_TITLE",
		"description": "QUEST_WARM_FIRE_DESC",
		"goal_item": "item_wood",
		"goal_count": 4,
		"reward": {"item_stone": 2},
	},
	"quest_builder": {
		"title": "QUEST_BUILDER_TITLE",
		"description": "QUEST_BUILDER_DESC",
		"goal_item": "tool_stone_axe",
		"goal_count": 1,
		"requires": "quest_first_stone",
		"reward": {"item_wood": 3},
	},
	"quest_hunter": {
		"title": "QUEST_HUNTER_TITLE",
		"description": "QUEST_HUNTER_DESC",
		"goal_item": "tool_hunting_bow",
		"goal_count": 1,
		"requires": "quest_builder",
		"reward": {"item_wood": 5, "item_stone": 4},
	},
	"quest_shelter": {
		"title": "QUEST_SHELTER_TITLE",
		"description": "QUEST_SHELTER_DESC",
		"goal_item": "building_shelter",
		"goal_count": 1,
		"requires": "quest_hunter",
	},
}

var _states: Dictionary = {}
var _collected: Dictionary = {}
var _autosave: bool = true
# Les tests headless comptent exactement le contenu du sac : le vrai QuestManager (autoload)
# n'y ajoute donc pas de récompenses, sauf demande explicite (enable_rewards_for_test).
var _grant_rewards: bool = DisplayServer.get_name() != "headless"

func _ready() -> void:
	_load()
	var inventory := InteractionManager.get_inventory()
	if inventory != null:
		inventory.connect("item_added", _on_item_added)
	_unlock_available()
	_evaluate_all(false)

# --- État ----------------------------------------------------------------------

func set_state(quest_id: String, state: int) -> void:
	_states[quest_id] = state
	quest_state_changed.emit(quest_id, state_name(state))
	_save()

func state_of(quest_id: String) -> int:
	return int(_states.get(quest_id, State.LOCKED))

func state_name(state: int) -> String:
	match state:
		State.ACTIVE:
			return "active"
		State.COMPLETED:
			return "completed"
	return "locked"

func activate(quest_id: String) -> void:
	if QUESTS.has(quest_id) and state_of(quest_id) == State.LOCKED:
		set_state(quest_id, State.ACTIVE)

func get_active() -> Array:
	return _ids_in_state(State.ACTIVE)

func get_completed() -> Array:
	return _ids_in_state(State.COMPLETED)

func get_locked() -> Array:
	return _ids_in_state(State.LOCKED)

func _ids_in_state(state: int) -> Array:
	var ids: Array = []
	for quest_id in QUESTS:
		if state_of(quest_id) == state:
			ids.append(quest_id)
	return ids

func get_title(quest_id: String) -> String:
	if QUESTS.has(quest_id):
		return QUESTS[quest_id].get("title", quest_id)
	return quest_id

func get_description(quest_id: String) -> String:
	if QUESTS.has(quest_id):
		return QUESTS[quest_id].get("description", "")
	return ""

## Récompense {id d'objet: quantité} (vide si aucune).
func get_reward(quest_id: String) -> Dictionary:
	if QUESTS.has(quest_id):
		return (QUESTS[quest_id].get("reward", {}) as Dictionary).duplicate()
	return {}

func get_goal_item(quest_id: String) -> String:
	if QUESTS.has(quest_id):
		return String(QUESTS[quest_id].get("goal_item", ""))
	return ""

## Progression (objets cumulés, objectif). Le sac compte aussi : un joueur qui avait
## déjà des objets avant l'arrivée des quêtes n'a pas à les ramasser de nouveau.
func get_progress(quest_id: String) -> Vector2i:
	if not QUESTS.has(quest_id):
		return Vector2i.ZERO
	var quest: Dictionary = QUESTS[quest_id]
	var item_id: String = quest.get("goal_item", "")
	var goal := int(quest.get("goal_count", 1))
	var have := int(_collected.get(item_id, 0))
	var inventory := InteractionManager.get_inventory()
	if inventory != null:
		have = maxi(have, int(inventory.call("count_of", item_id)))
	return Vector2i(mini(have, goal), goal)

## Quête prioritaire à suivre (la première active), "" si aucune.
func get_tracked() -> String:
	var active := get_active()
	return String(active[0]) if not active.is_empty() else ""

# --- Évolution -------------------------------------------------------------------

func _on_item_added(item_id: String, amount: int) -> void:
	_collected[item_id] = int(_collected.get(item_id, 0)) + amount
	_evaluate_all(true)

func _evaluate_all(announce: bool) -> void:
	for quest_id in QUESTS:
		if state_of(quest_id) != State.ACTIVE:
			continue
		var progress := get_progress(quest_id)
		quest_progress_changed.emit(quest_id, progress.x, progress.y)
		if progress.x >= progress.y:
			set_state(quest_id, State.COMPLETED)
			if announce:
				_announce(quest_id)
	_unlock_available()
	_save()

func _unlock_available() -> void:
	for quest_id in QUESTS:
		if state_of(quest_id) != State.LOCKED:
			continue
		var required: String = QUESTS[quest_id].get("requires", "")
		if required == "" or state_of(required) == State.COMPLETED:
			set_state(quest_id, State.ACTIVE)

func _announce(quest_id: String) -> void:
	var reward := get_reward(quest_id) if _grant_rewards else {}
	var inventory := InteractionManager.get_inventory()
	var parts: PackedStringArray = []
	for item_id in reward:
		if inventory != null:
			inventory.call("add_item", item_id, int(reward[item_id]))
		parts.append("%d× %s" % [int(reward[item_id]), tr("ITEM_" + String(item_id).to_upper())])
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		var message: String = tr("TOAST_QUEST_DONE") % tr(get_title(quest_id))
		if not parts.is_empty():
			message += "\n" + tr("QUEST_REWARD") % ", ".join(parts)
		hud.show_toast(message, 3.5)

# --- Sauvegarde --------------------------------------------------------------------

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for quest_id in config.get_section_keys("states"):
		if QUESTS.has(quest_id):
			_states[quest_id] = int(config.get_value("states", quest_id, 0))
	for item_id in config.get_section_keys("collected"):
		_collected[item_id] = int(config.get_value("collected", item_id, 0))

func _save() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	for quest_id in _states:
		config.set_value("states", quest_id, int(_states[quest_id]))
	for item_id in _collected:
		config.set_value("collected", item_id, int(_collected[item_id]))
	config.save(SAVE_PATH)

## API de test : active les récompenses (désactivées en headless).
func enable_rewards_for_test() -> void:
	_grant_rewards = true

## API de test : repart de zéro, sans écrire sur le disque.
func clear_for_test() -> void:
	_autosave = false
	_states.clear()
	_collected.clear()
