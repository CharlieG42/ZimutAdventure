extends Node
## Carnet d'observation : faune, flore et paysages du canyon. Une entrée se note toute seule
## quand le joueur la regarde d'assez près (au centre de l'écran), ou à l'arrivée en un lieu.
## Chaque observation rapporte de l'expérience ; des paliers offrent des récompenses.
## Sauvegarde dans user://notebook.cfg.

signal entry_observed(entry_id: String, count: int)

const SAVE_PATH := "user://notebook.cfg"
const CHECK_SECONDS := 0.4
## Cône de regard : l'objet doit être à moins de ~35° du centre de l'écran.
const VIEW_DOT := 0.82

const CATEGORIES := ["fauna", "flora", "landscape"]
## source : "animal" (nœud avec `species` dans un groupe), "kind" (décor du paysage),
## "group" (nœuds d'un groupe), "item" (objet obtenu), "landmark" (lieu atteint).
const ENTRIES := {
	"deer": {"category": "fauna", "source": "animal", "group": "huntable", "species": "deer", "range": 24.0},
	"rabbit": {"category": "fauna", "source": "animal", "group": "huntable", "species": "rabbit", "range": 16.0},
	"coyote": {"category": "fauna", "source": "animal", "group": "predators", "species": "coyote", "range": 26.0},
	"wolf": {"category": "fauna", "source": "animal", "group": "predators", "species": "wolf", "range": 26.0},
	"cow": {"category": "fauna", "source": "animal", "group": "domestic", "species": "cow", "range": 20.0},
	"sheep": {"category": "fauna", "source": "animal", "group": "domestic", "species": "sheep", "range": 18.0},
	"goat": {"category": "fauna", "source": "animal", "group": "domestic", "species": "goat", "range": 18.0},
	"chicken": {"category": "fauna", "source": "animal", "group": "domestic", "species": "chicken", "range": 12.0},
	"horse": {"category": "fauna", "source": "animal", "group": "domestic", "species": "horse", "range": 22.0},
	"dog": {"category": "fauna", "source": "animal", "group": "domestic", "species": "dog", "range": 16.0},
	"fish": {"category": "fauna", "source": "item", "items": ["item_fish", "item_fish_big"]},
	"pine": {"category": "flora", "source": "kind", "kind": "pine", "range": 12.0},
	"cactus": {"category": "flora", "source": "kind", "kind": "cactus", "range": 10.0},
	"agave": {"category": "flora", "source": "kind", "kind": "agave", "range": 8.0},
	"shrub": {"category": "flora", "source": "kind", "kind": "shrub", "range": 8.0},
	"flowers": {"category": "flora", "source": "kind", "kind": "flowers", "range": 7.0},
	"berries": {"category": "flora", "source": "group", "group": "berries", "range": 10.0},
	"hoodoo": {"category": "landscape", "source": "kind", "kind": "hoodoo", "range": 45.0},
	"arch": {"category": "landscape", "source": "kind", "kind": "arch", "range": 40.0},
	"butte": {"category": "landscape", "source": "kind", "kind": "butte", "range": 60.0},
	"river": {"category": "landscape", "source": "landmark", "landmark": "river"},
	"pinewood": {"category": "landscape", "source": "landmark", "landmark": "forest"},
	"plateau": {"category": "landscape", "source": "landmark", "landmark": "mesa"},
	"source": {"category": "landscape", "source": "landmark", "landmark": "source"},
}
## Paliers : nombre d'observations -> récompense.
const MILESTONES := {
	6: {"arrow": 6},
	12: {"item_cooked_meat": 2, "item_berries": 4},
	18: {"item_wool": 2, "item_pelt": 2},
	24: {"item_relic": 1},
}

var _observed: Array = []
var _autosave: bool = DisplayServer.get_name() != "headless"
var _timer: float = 0.0

func _ready() -> void:
	_load()
	var inventory := InteractionManager.get_inventory()
	if inventory != null and inventory.has_signal("item_added"):
		inventory.connect("item_added", _on_item_added)
	var exploration := InteractionManager.get_exploration()
	if exploration != null and exploration.has_signal("landmark_reached"):
		exploration.connect("landmark_reached", _on_landmark_reached)
		# Lieux atteints avant que le carnet n'existe : notés sans fanfare.
		for entry_id in ENTRIES:
			var entry: Dictionary = ENTRIES[entry_id]
			if String(entry["source"]) == "landmark" and bool(exploration.call("is_landmark_reached", String(entry["landmark"]))) \
					and not _observed.has(entry_id):
				_observed.append(entry_id)

# --- API ------------------------------------------------------------------------------

func is_observed(entry_id: String) -> bool:
	return _observed.has(entry_id)

func get_count() -> int:
	return _observed.size()

func get_total() -> int:
	return ENTRIES.size()

func get_entries_in_category(category: String) -> Array:
	var ids: Array = []
	for entry_id in ENTRIES:
		if String(ENTRIES[entry_id]["category"]) == category:
			ids.append(entry_id)
	return ids

## Vecteur (observées, total) d'une catégorie.
func get_category_progress(category: String) -> Vector2i:
	var ids := get_entries_in_category(category)
	var seen := 0
	for entry_id in ids:
		if _observed.has(entry_id):
			seen += 1
	return Vector2i(seen, ids.size())

## Prochain palier à atteindre (0 s'il n'y en a plus) et sa récompense.
func get_next_milestone() -> int:
	var keys := MILESTONES.keys()
	keys.sort()
	for count in keys:
		if int(count) > _observed.size():
			return int(count)
	return 0

func get_milestone_reward(count: int) -> Dictionary:
	return MILESTONES.get(count, {})

static func name_key(entry_id: String) -> String:
	return "NOTE_" + entry_id.to_upper()

static func description_key(entry_id: String) -> String:
	return "NOTE_" + entry_id.to_upper() + "_DESC"

static func hint_key(entry_id: String) -> String:
	return "NOTE_" + entry_id.to_upper() + "_HINT"

## Note une entrée. Retourne true si elle est nouvelle.
func observe(entry_id: String) -> bool:
	if not ENTRIES.has(entry_id) or _observed.has(entry_id):
		return false
	_observed.append(entry_id)
	var count := _observed.size()
	var progression := InteractionManager.get_progression()
	if progression != null:
		progression.call("add_stat", "stat_observations", 1)
		progression.call("add_xp_for", "observe")
	var message := tr("TOAST_OBSERVED") % [tr(name_key(entry_id)), count, ENTRIES.size()]
	var reward: Dictionary = MILESTONES.get(count, {})
	if not reward.is_empty():
		var inventory := InteractionManager.get_inventory()
		var parts: PackedStringArray = []
		for item_id in reward:
			if inventory != null:
				inventory.call("add_item", item_id, int(reward[item_id]))
			parts.append("%d× %s" % [int(reward[item_id]), tr("ITEM_" + String(item_id).to_upper())])
		message += "\n" + tr("TOAST_NOTEBOOK_REWARD") % ", ".join(parts)
	var sfx := InteractionManager.get_sfx()
	if sfx != null and sfx.has_method("play_event"):
		sfx.call("play_event", "chime")
	_toast(message)
	entry_observed.emit(entry_id, count)
	_save()
	return true

# --- Détection --------------------------------------------------------------------------

func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_SECONDS:
		return
	_timer = 0.0
	if _observed.size() >= ENTRIES.size():
		return
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null:
		return
	var landscape := get_tree().get_first_node_in_group("landscape")
	for entry_id in ENTRIES:
		if _observed.has(entry_id):
			continue
		if can_see_entry(entry_id, camera.global_position, -camera.global_basis.z, landscape):
			observe(entry_id)
			return

## Vrai si, depuis `eye` en regardant `forward`, l'entrée est visible d'assez près.
func can_see_entry(entry_id: String, eye: Vector3, forward: Vector3, landscape: Node) -> bool:
	var entry: Dictionary = ENTRIES[entry_id]
	var reach := float(entry.get("range", 0.0))
	match String(entry["source"]):
		"animal":
			for node in get_tree().get_nodes_in_group(String(entry["group"])):
				if node is Node3D and str(node.get("species")) == String(entry["species"]) \
						and _in_view(eye, forward, (node as Node3D).global_position + Vector3(0, 0.6, 0), reach):
					return true
		"group":
			for node in get_tree().get_nodes_in_group(String(entry["group"])):
				if node is Node3D and _in_view(eye, forward, (node as Node3D).global_position + Vector3(0, 0.5, 0), reach):
					return true
		"kind":
			if landscape == null or not landscape.has_method("get_kind_positions"):
				return false
			var positions: PackedVector2Array = landscape.call("get_kind_positions", String(entry["kind"]))
			var lift := 4.0 if String(entry["category"]) == "landscape" else 0.8
			for p in positions:
				if absf(p.x - eye.x) > reach or absf(p.y - eye.z) > reach:
					continue
				var y := float(landscape.call("terrain_height_at", p.x, p.y)) + lift
				if _in_view(eye, forward, Vector3(p.x, y, p.y), reach):
					return true
	return false

static func _in_view(eye: Vector3, forward: Vector3, target: Vector3, reach: float) -> bool:
	var to := target - eye
	var distance := to.length()
	if distance > reach:
		return false
	if distance < 0.5:
		return true
	return forward.normalized().dot(to / distance) >= VIEW_DOT

func _on_item_added(item_id: String, _amount: int) -> void:
	for entry_id in ENTRIES:
		if String(ENTRIES[entry_id]["source"]) == "item" and item_id in ENTRIES[entry_id]["items"]:
			observe(entry_id)

func _on_landmark_reached(landmark_id: String) -> void:
	for entry_id in ENTRIES:
		if String(ENTRIES[entry_id]["source"]) == "landmark" and String(ENTRIES[entry_id]["landmark"]) == landmark_id:
			observe(entry_id)

func _toast(message: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_toast"):
		hud.call("show_toast", message, 3.0)

# --- Sauvegarde ----------------------------------------------------------------------------

func _load() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for entry_id in config.get_value("notebook", "observed", []):
		if ENTRIES.has(entry_id) and not _observed.has(entry_id):
			_observed.append(entry_id)

func _save() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	config.set_value("notebook", "observed", _observed)
	config.save(SAVE_PATH)

## API de test : carnet vide, sans disque.
func clear_for_test() -> void:
	_autosave = false
	_observed.clear()
