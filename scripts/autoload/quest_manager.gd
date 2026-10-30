extends Node
## Journal de quêtes : suivi d'objectifs simples (collecte, interaction).

signal quest_state_changed(quest_id: String, state: String)

enum State { LOCKED, ACTIVE, COMPLETED }

const QUESTS := {
	"quest_first_stone": {
		"title": "QUEST_FIRST_STONE_TITLE",
		"description": "QUEST_FIRST_STONE_DESC",
		"goal_item": "item_stone",
		"goal_count": 3,
	},
	"quest_warm_fire": {
		"title": "QUEST_WARM_FIRE_TITLE",
		"description": "QUEST_WARM_FIRE_DESC",
		"goal_item": "item_wood",
		"goal_count": 4,
	},
	"quest_builder": {
		"title": "QUEST_BUILDER_TITLE",
		"description": "QUEST_BUILDER_DESC",
		"goal_item": "item_plank",
		"goal_count": 2,
	},
}

var _states: Dictionary = {}

func _ready() -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory != null:
		inventory.connect("item_added", _on_item_added)
	for quest_id in QUESTS:
		if state_of(quest_id) == State.LOCKED:
			set_state(quest_id, State.ACTIVE)
	_evaluate_all()

func set_state(quest_id: String, state: int) -> void:
	_states[quest_id] = state
	quest_state_changed.emit(quest_id, state_name(state))

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
	var active: Array = []
	for quest_id in QUESTS:
		if state_of(quest_id) == State.ACTIVE:
			active.append(quest_id)
	return active

func get_completed() -> Array:
	var completed: Array = []
	for quest_id in QUESTS:
		if state_of(quest_id) == State.COMPLETED:
			completed.append(quest_id)
	return completed

func get_title(quest_id: String) -> String:
	if QUESTS.has(quest_id):
		return QUESTS[quest_id].get("title", quest_id)
	return quest_id

func get_description(quest_id: String) -> String:
	if QUESTS.has(quest_id):
		return QUESTS[quest_id].get("description", "")
	return ""

func _on_item_added(item_id: String, _amount: int) -> void:
	_evaluate_all()

## Une quête de collecte est complétée quand l'inventaire contient le compte demandé.
func _evaluate_all() -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return
	for quest_id in QUESTS:
		if state_of(quest_id) != State.ACTIVE:
			continue
		var quest: Dictionary = QUESTS[quest_id]
		if inventory.has_item(quest.get("goal_item", ""), int(quest.get("goal_count", 1))):
			set_state(quest_id, State.COMPLETED)

## API de test : activer toutes les quêtes sans l'autoload d'inventaire branché.
func clear_for_test() -> void:
	_states.clear()
