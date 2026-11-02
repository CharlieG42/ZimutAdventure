class_name StorageChest
extends Interactable
## Coffre de camp : une interaction dépose tout ce qui peut l'être (ressources, nourriture, peaux...),
## la suivante, sac vide de ces objets, reprend tout. Les outils, flèches et capes restent sur soi.

signal changed(chest)

const NEVER_STORED := ["arrow", "armor_fur_cloak"]
const SOLID_LAYER := 1

var stock: Dictionary = {}

static func create() -> Area3D:
	var area := Area3D.new()
	area.set_script(load("res://scripts/interaction/chest.gd"))
	area.collision_layer = 4
	area.collision_mask = 0
	area.name = "Chest"
	return area

func _ready() -> void:
	add_to_group("structures")
	add_to_group("chests")
	_build()

# --- Logique ------------------------------------------------------------------------------

func _is_storable(item_id: String) -> bool:
	var inventory_script = load("res://scripts/autoload/inventory.gd")
	return not (inventory_script.TOOLS as Array).has(item_id) and not NEVER_STORED.has(item_id)

## Objets du sac que le coffre peut recevoir.
func storable_in_bag() -> Dictionary:
	var result := {}
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return result
	var all: Dictionary = inventory.get_all()
	for item_id in all:
		var count := int(all[item_id])
		if count > 0 and _is_storable(String(item_id)):
			result[item_id] = count
	return result

func get_prompt() -> String:
	if not storable_in_bag().is_empty():
		return "ACTION_CHEST_STORE"
	return "ACTION_CHEST_TAKE" if not stock.is_empty() else "ACTION_CHEST_EMPTY"

func _on_interact(_interactor: Node3D) -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return
	var to_store := storable_in_bag()
	if not to_store.is_empty():
		var total := 0
		for item_id in to_store:
			var count := int(to_store[item_id])
			if inventory.remove_item(String(item_id), count):
				stock[item_id] = int(stock.get(item_id, 0)) + count
				total += count
		_toast(tr("TOAST_CHEST_STORED") % total)
	elif not stock.is_empty():
		var total := 0
		for item_id in stock:
			inventory.add_item(String(item_id), int(stock[item_id]))
			total += int(stock[item_id])
		stock.clear()
		_toast(tr("TOAST_CHEST_TAKEN") % total)
	else:
		_toast(tr("TOAST_CHEST_EMPTY"))
		return
	changed.emit(self)

func total_stored() -> int:
	var total := 0
	for item_id in stock:
		total += int(stock[item_id])
	return total

func get_state() -> Dictionary:
	return {"stock": stock.duplicate()}

func apply_state(state: Dictionary) -> void:
	stock = (state.get("stock", {}) as Dictionary).duplicate()

func _toast(message: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 1.8)

# --- Modèle ----------------------------------------------------------------------------------

func _build() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.29, 0.15)
	wood.roughness = 0.95
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.25, 0.16, 0.09)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.5, 0.5, 0.52)
	metal.metallic = 0.5
	metal.roughness = 0.5
	_box(Vector3(1.1, 0.55, 0.7), Vector3(0.0, 0.28, 0.0), wood)
	var lid := _box(Vector3(1.16, 0.2, 0.76), Vector3(0.0, 0.64, 0.0), dark)
	lid.rotation_degrees.x = -4.0
	for x in [-0.4, 0.4]:
		_box(Vector3(0.1, 0.62, 0.78), Vector3(x, 0.32, 0.0), metal)
	_box(Vector3(0.14, 0.18, 0.06), Vector3(0.0, 0.5, 0.38), metal)
	# Collision pleine (couche 1) et zone de visée (couche 4, portée par l'Area3D).
	var body := StaticBody3D.new()
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	body.position = Vector3(0.0, 0.4, 0.0)
	var solid := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.1, 0.8, 0.7)
	solid.shape = shape
	body.add_child(solid)
	add_child(body)
	var trigger := CollisionShape3D.new()
	var trigger_shape := BoxShape3D.new()
	trigger_shape.size = Vector3(1.8, 1.4, 1.4)
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
