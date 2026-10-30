class_name CampfireInteractable
extends Interactable

const STAGES := 4

@export var wood_item_id: String = "item_wood"
@export var wood_per_stage: int = 1
@export var fire_light_energy: float = 2.2

var _stage: int = 0
var _light: OmniLight3D
var _mesh: MeshInstance3D

func _ready() -> void:
	add_to_group("campfire")
	prompt_text = "ACTION_STOKE_FIRE"
	_light = get_node_or_null("FireLight") as OmniLight3D
	_mesh = get_node_or_null("Flames") as MeshInstance3D
	_refresh()

func get_prompt() -> String:
	if _stage >= STAGES and _has_raw_meat():
		return "ACTION_COOK"
	return "ACTION_REST" if _stage >= STAGES else prompt_text

## Cuisson possible seulement sur un feu plein, avec de la viande crue sur soi.
func _has_raw_meat() -> bool:
	var inv := InteractionManager.get_inventory()
	return inv != null and inv.has_item("item_raw_meat", 1)

func _on_interact(interactor: Node3D) -> void:
	if _stage >= STAGES:
		if _has_raw_meat():
			_cook(interactor)
		else:
			_rest(interactor)
		return
	var inventory := InteractionManager.get_inventory()
	if inventory == null or not inventory.has_item(wood_item_id, wood_per_stage):
		_notify(interactor, "TOAST_NEED_WOOD")
		return
	inventory.remove_item(wood_item_id, wood_per_stage)
	_stage = mini(_stage + 1, STAGES)
	_refresh()
	var sfx := InteractionManager.get_sfx()
	if sfx != null:
		sfx.play(load("res://assets/audio/pickup/collect.wav"), -4.0, 0.8)
	_notify(interactor, "TOAST_FIRE_STOKED")

## Cuit la viande crue portée : chaque interaction convertit une viande.
func _cook(interactor: Node3D) -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory == null or not inventory.remove_item("item_raw_meat", 1):
		_notify(interactor, "TOAST_NEED_MEAT")
		return
	inventory.add_item("item_cooked_meat", 1)
	_notify(interactor, "TOAST_MEAT_COOKED")

func _rest(interactor: Node3D) -> void:
	if interactor is CharacterBody3D and interactor.has_method("restore_stamina"):
		interactor.restore_stamina()
	_notify(interactor, "TOAST_RESTED")

func _notify(interactor: Node3D, key: String) -> void:
	var tree := get_tree()
	if tree != null:
		var hud := tree.get_first_node_in_group("hud") as Node
		if hud != null and hud.has_method("show_toast"):
			hud.show_toast(tr(key))

func _refresh() -> void:
	if _light != null:
		_light.light_energy = fire_light_energy * _stage / float(STAGES)
		_light.visible = _stage > 0
	if _mesh != null:
		_mesh.visible = _stage > 0
		var scale_factor := maxf(0.4, _stage / float(STAGES))
		_mesh.scale = Vector3.ONE * scale_factor
