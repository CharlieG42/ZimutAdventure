class_name TreasureChest
extends Interactable
## Coffre au trésor d'un site (ruine, grotte) : s'ouvre une seule fois, livre un butin dont une relique.

signal looted(chest)

const SOLID_LAYER := 1

var site_id: String = ""
var loot: Dictionary = {"item_relic": 1}
var opened: bool = false
var _lid: MeshInstance3D

static func create(id: String, contents: Dictionary) -> Area3D:
	var area := Area3D.new()
	area.set_script(load("res://scripts/interaction/treasure_chest.gd"))
	area.collision_layer = 4
	area.collision_mask = 0
	area.name = "Treasure_" + id
	area.set("site_id", id)
	area.set("loot", contents)
	return area

func _ready() -> void:
	add_to_group("treasures")
	_build()
	var exploration := InteractionManager.get_exploration()
	if exploration != null and exploration.has_method("is_looted") and bool(exploration.call("is_looted", site_id)):
		_set_opened(true)

func can_interact() -> bool:
	return enabled and not opened

func get_prompt() -> String:
	return "ACTION_TREASURE_OPEN"

func _on_interact(_interactor: Node3D) -> void:
	open_chest()

func open_chest() -> void:
	if opened:
		return
	var inventory := InteractionManager.get_inventory()
	var names: Array = []
	for item_id in loot:
		if inventory != null:
			inventory.add_item(String(item_id), int(loot[item_id]))
		names.append("%d %s" % [int(loot[item_id]), tr("ITEM_" + String(item_id).to_upper())])
	_set_opened(true)
	var progression := InteractionManager.get_progression()
	if progression != null:
		progression.call("add_xp_for", "treasure")
		progression.call("add_stat", "stat_treasures", 1)
	var exploration := InteractionManager.get_exploration()
	if exploration != null and exploration.has_method("mark_looted"):
		exploration.call("mark_looted", site_id)
	var sfx := InteractionManager.get_sfx()
	if sfx != null and sfx.has_method("play_event"):
		sfx.call("play_event", "treasure")
	_toast(tr("TOAST_TREASURE_FOUND") % ", ".join(names))
	looted.emit(self)

func _set_opened(value: bool) -> void:
	opened = value
	if _lid != null:
		_lid.rotation_degrees.x = -70.0 if value else -4.0
		_lid.position = Vector3(0.0, 0.8 if value else 0.64, -0.28 if value else 0.0)

func _toast(message: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 3.0)

func _build() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.2, 0.1)
	wood.roughness = 0.9
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.85, 0.68, 0.2)
	gold.metallic = 0.8
	gold.roughness = 0.35
	_box(Vector3(1.0, 0.5, 0.64), Vector3(0.0, 0.25, 0.0), wood)
	_lid = _box(Vector3(1.06, 0.18, 0.7), Vector3(0.0, 0.64, 0.0), gold)
	_lid.rotation_degrees.x = -4.0
	for x in [-0.38, 0.38]:
		_box(Vector3(0.08, 0.56, 0.68), Vector3(x, 0.28, 0.0), gold)
	var body := StaticBody3D.new()
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	body.position = Vector3(0.0, 0.35, 0.0)
	var solid := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 0.7, 0.64)
	solid.shape = shape
	body.add_child(solid)
	add_child(body)
	var trigger := CollisionShape3D.new()
	var trigger_shape := BoxShape3D.new()
	trigger_shape.size = Vector3(1.9, 1.4, 1.5)
	trigger.shape = trigger_shape
	trigger.position = Vector3(0.0, 0.6, 0.0)
	add_child(trigger)

func _box(size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	add_child(instance)
	return instance
