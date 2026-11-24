class_name StorageChest
extends Interactable
## Coffre de camp : l'interaction ouvre le panneau de transfert (choix objet par objet,
## voir ChestPanel). Hors HUD (tests headless), l'interaction reste tout-ou-rien :
## dépose tout ce qui peut l'être (ressources, nourriture, peaux...), puis reprend tout.
## Les outils, flèches et capes restent sur soi.

signal changed(chest)

const NEVER_STORED := ["arrow", "armor_fur_cloak", "gear_straw_hat", "gear_hide_boots", "gear_backpack", "gear_wool_shirt", "gear_wool_trousers", "gear_leather_gloves"]
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
	return "ACTION_CHEST_OPEN"

## Dépose jusqu'à `amount` exemplaires de `item_id` (sac -> coffre) ; renvoie le nombre déposé.
func store_item(item_id: String, amount: int) -> int:
	var inventory := InteractionManager.get_inventory()
	if inventory == null or amount <= 0 or not _is_storable(item_id):
		return 0
	var movable := mini(amount, int(inventory.call("count_of", item_id)))
	if movable <= 0:
		return 0
	if not inventory.remove_item(item_id, movable):
		return 0
	stock[item_id] = int(stock.get(item_id, 0)) + movable
	changed.emit(self)
	return movable

## Reprend jusqu'à `amount` exemplaires de `item_id` (coffre -> sac) ; renvoie le nombre repris.
func take_item(item_id: String, amount: int) -> int:
	var inventory := InteractionManager.get_inventory()
	if inventory == null or amount <= 0:
		return 0
	var available := int(stock.get(item_id, 0))
	var movable := mini(amount, available)
	if movable <= 0:
		return 0
	inventory.add_item(item_id, movable)
	var left := available - movable
	if left <= 0:
		stock.erase(item_id)
	else:
		stock[item_id] = left
	changed.emit(self)
	return movable

## Dépose tout ce qui est rangeable ; renvoie le nombre d'objets déposés.
func store_all() -> int:
	var bag := storable_in_bag()
	var total := 0
	for item_id in bag:
		total += store_item(String(item_id), int(bag[item_id]))
	return total

## Reprend tout le contenu ; renvoie le nombre d'objets repris.
func take_all() -> int:
	var total := 0
	for item_id in stock.keys():
		total += take_item(String(item_id), int(stock[item_id]))
	return total

func _on_interact(_interactor: Node3D) -> void:
	var tree := get_tree()
	var hud := tree.get_first_node_in_group("hud") if tree != null else null
	if hud != null and hud.has_method("open_chest_panel"):
		hud.call("open_chest_panel", self)
		return
	# Sans HUD (tests headless) : repli tout-ou-rien historique.
	if not storable_in_bag().is_empty():
		_toast(tr("TOAST_CHEST_STORED") % store_all())
	elif not stock.is_empty():
		_toast(tr("TOAST_CHEST_TAKEN") % take_all())
	else:
		_toast(tr("TOAST_CHEST_EMPTY"))

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
