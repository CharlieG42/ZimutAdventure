extends Interactable
## Dépouille d'un animal abattu : le joueur s'approche et la dépèce pour récupérer
## sa viande (et sa peau). Posée en enfant de l'animal, elle disparaît avec lui.

## Une fois dépecée (ou si le temps passe), la dépouille s'efface.
signal harvested

var species: String = ""
## Butin : { id d'item : quantité }.
var loot: Dictionary = {}
var _done: bool = false

static func attach(animal: Node3D, animal_species: String, items: Dictionary) -> Node:
	var area := Area3D.new()
	area.set_script(load("res://scripts/world/carcass.gd"))
	area.set("species", animal_species)
	area.set("loot", items)
	area.set("prompt_text", "ACTION_BUTCHER")
	area.collision_layer = 4
	area.collision_mask = 0
	area.name = "Carcass"
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.7
	shape.shape = sphere
	shape.position = Vector3(0.0, 0.5, 0.0)
	area.add_child(shape)
	animal.add_child(area)
	return area

func can_interact() -> bool:
	return enabled and not _done

func _on_interact(_interactor: Node3D) -> void:
	harvest()

## Verse le butin dans le sac. Renvoie vrai si la dépouille vient d'être dépecée.
func harvest() -> bool:
	if _done:
		return false
	_done = true
	enabled = false
	var inventory := InteractionManager.get_inventory()
	var parts: Array[String] = []
	for item_id in loot:
		var amount: int = int(loot[item_id])
		if amount <= 0:
			continue
		if inventory != null:
			inventory.add_item(item_id, amount)
		parts.append("%s ×%d" % [tr("ITEM_" + String(item_id).to_upper()), amount])
	var tree := get_tree()
	var hud := tree.get_first_node_in_group("hud") as Node if tree != null else null
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(tr("TOAST_BUTCHER") % ", ".join(parts))
	harvested.emit()
	return true
