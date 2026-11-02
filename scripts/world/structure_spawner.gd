extends Node3D
## Gère les constructions posées par le joueur : placement sur le terrain, sauvegarde
## dans user://structures.cfg et rechargement au lancement.

const SAVE_PATH := "user://structures.cfg"
const MAX_SLOPE := 1.2
const MAX_STRUCTURES := 40

## id d'objet de l'inventaire -> type de construction.
const PLACEABLE := {
	"furniture_camp_bed": "camp_bed",
	"building_campfire": "campfire",
	"furniture_chest": "chest",
	"building_palisade": "palisade",
	"building_shelter": "shelter",
	"building_farm_plot": "farm_plot",
	"building_pen": "pen",
	"furniture_wool_bed": "wool_bed",
}

var _landscape: Node3D
# Les tests headless ne lisent ni n'écrivent la sauvegarde du joueur.
var _autosave: bool = DisplayServer.get_name() != "headless"
var _records: Array = []

func _ready() -> void:
	add_to_group("structure_spawner")
	_landscape = get_node_or_null("../Landscape") as Node3D
	_load()

func is_placeable(item_id: String) -> bool:
	return PLACEABLE.has(item_id)

## Pose une construction devant `origin`. Retourne "" si réussi, sinon la clé de
## traduction de l'erreur. `yaw` : orientation (l'avant de la construction est +Z).
func place(item_id: String, origin: Vector3, yaw: float) -> String:
	if not PLACEABLE.has(item_id):
		return "TOAST_CANNOT_PLACE"
	if get_child_count() >= MAX_STRUCTURES:
		return "TOAST_TOO_MANY"
	var ground := _ground_height(origin.x, origin.z)
	if ground < -50.0:
		return "TOAST_CANNOT_PLACE"
	for offset in [Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
		var h := _ground_height(origin.x + offset.x, origin.z + offset.y)
		if absf(h - ground) > MAX_SLOPE:
			return "TOAST_TOO_STEEP"
	if PLACEABLE[item_id] == "pen":
		for offset in [Vector2(4.5, 4.5), Vector2(-4.5, 4.5), Vector2(4.5, -4.5), Vector2(-4.5, -4.5)]:
			if absf(_ground_height(origin.x + offset.x, origin.z + offset.y) - ground) > MAX_SLOPE * 1.6:
				return "TOAST_TOO_STEEP"
	var position := Vector3(origin.x, ground, origin.z)
	var node := _spawn(PLACEABLE[item_id], position, yaw)
	_records.append({"item": item_id, "pos": position, "yaw": yaw, "node": node})
	_save()
	var progression := InteractionManager.get_progression()
	if progression != null:
		progression.call("add_xp_for", "build")
		if PLACEABLE[item_id] == "pen":
			progression.call("add_stat", "stat_pens", 1)
	if node is Pen:
		(node as Pen).gather_nearby()
	return ""

func _spawn(kind: String, position: Vector3, yaw: float) -> Node3D:
	var structure: Node3D
	match kind:
		"farm_plot":
			structure = FarmPlot.create()
		"pen":
			structure = Pen.create()
		"chest":
			structure = StorageChest.create()
		"palisade":
			structure = Palisade.create()
		"campfire":
			structure = (load("res://scenes/interaction/campfire.tscn") as PackedScene).instantiate()
		_:
			structure = PlacedStructure.create(kind)
	structure.position = position
	structure.rotation.y = yaw
	add_child(structure)
	if structure.has_signal("changed"):
		structure.connect("changed", _on_plot_changed)
	return structure

func _on_plot_changed(_plot: Node) -> void:
	_save()

func _ground_height(x: float, z: float) -> float:
	if _landscape != null and _landscape.has_method("terrain_height_at"):
		return float(_landscape.call("terrain_height_at", x, z))
	return 0.0

func _load() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for entry in config.get_value("structures", "list", []):
		if not (entry is Dictionary) or not PLACEABLE.has(String(entry.get("item", ""))):
			continue
		var position: Vector3 = entry.get("pos", Vector3.ZERO)
		var yaw := float(entry.get("yaw", 0.0))
		var node := _spawn(PLACEABLE[entry["item"]], position, yaw)
		if node.has_method("apply_state"):
			node.call("apply_state", entry)
		_records.append({"item": entry["item"], "pos": position, "yaw": yaw, "node": node})

func _save() -> void:
	if not _autosave:
		return
	var saved: Array = []
	for record in _records:
		var entry := {"item": record["item"], "pos": record["pos"], "yaw": record["yaw"]}
		var node: Object = record.get("node")
		if node != null and is_instance_valid(node) and node.has_method("get_state"):
			entry.merge(node.call("get_state"))
		saved.append(entry)
	var config := ConfigFile.new()
	config.set_value("structures", "list", saved)
	config.save(SAVE_PATH)

## API de test : ne touche pas au disque.
func disable_saving_for_test() -> void:
	_autosave = false
