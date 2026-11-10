class_name CampfireInteractable
extends Interactable

const STAGES := 4

@export var wood_item_id: String = "item_wood"
@export var wood_per_stage: int = 1
@export var fire_light_energy: float = 2.2

## Recettes du feu, dans l'ordre de priorité : {ingrédients} -> plat.
const COOK_RECIPES := [
	{"in": {"item_raw_meat": 1}, "out": "item_cooked_meat", "toast": "TOAST_MEAT_COOKED"},
	{"in": {"item_milk": 1, "item_vegetables": 1}, "out": "item_soup", "toast": "TOAST_COOKED"},
	{"in": {"item_wheat": 2}, "out": "item_bread", "toast": "TOAST_COOKED"},
	{"in": {"item_egg": 1}, "out": "item_boiled_egg", "toast": "TOAST_COOKED"},
	{"in": {"item_fish_big": 1}, "out": "item_grilled_fish_big", "toast": "TOAST_FISH_GRILLED"},
	{"in": {"item_fish": 1}, "out": "item_grilled_fish", "toast": "TOAST_FISH_GRILLED"},
	{"in": {"item_vegetables": 1}, "out": "item_roast_vegetables", "toast": "TOAST_COOKED"},
]

signal changed(fire)

var _stage: int = 0
var _light: OmniLight3D
var _mesh: MeshInstance3D
var _flicker_t: float = 0.0

func _ready() -> void:
	add_to_group("campfire")
	prompt_text = "ACTION_STOKE_FIRE"
	_light = get_node_or_null("FireLight") as OmniLight3D
	_mesh = get_node_or_null("Flames") as MeshInstance3D
	# Particules texturées (Kenney CC0) : flammes + fumée + braises au-dessus du cercle.
	VfxParticles.campfire(self, Vector3(0.0, 0.3, 0.0))
	_refresh()

func get_prompt() -> String:
	if _stage >= STAGES and not _current_recipe().is_empty():
		return "ACTION_COOK"
	return "ACTION_REST" if _stage >= STAGES else prompt_text

## Première recette réalisable avec le contenu du sac (vide si aucune).
func _current_recipe() -> Dictionary:
	var inv := InteractionManager.get_inventory()
	if inv == null:
		return {}
	for recipe in COOK_RECIPES:
		var ok := true
		for item_id in recipe["in"]:
			if not inv.has_item(item_id, int(recipe["in"][item_id])):
				ok = false
				break
		if ok:
			return recipe
	return {}

func _on_interact(interactor: Node3D) -> void:
	if _stage >= STAGES:
		if not _current_recipe().is_empty():
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
	changed.emit(self)
	var sfx := InteractionManager.get_sfx()
	if sfx != null:
		sfx.play(load("res://assets/audio/pickup/collect.wav"), -4.0, 0.8)
	_notify(interactor, "TOAST_FIRE_STOKED")

## Cuisine un plat : chaque interaction prépare une portion de la première recette possible.
func _cook(interactor: Node3D) -> void:
	var inventory := InteractionManager.get_inventory()
	var recipe := _current_recipe()
	if inventory == null or recipe.is_empty():
		_notify(interactor, "TOAST_NEED_MEAT")
		return
	for item_id in recipe["in"]:
		inventory.remove_item(item_id, int(recipe["in"][item_id]))
	inventory.add_item(String(recipe["out"]), 1)
	var progression := InteractionManager.get_progression()
	if progression != null:
		progression.call("add_stat", "stat_cooked", 1)
		if String(recipe["out"]).contains("fish"):
			progression.call("add_stat", "stat_fish_cooked", 1)
		progression.call("add_xp_for", "cook")
	_notify(interactor, String(recipe["toast"]))

func get_state() -> Dictionary:
	return {"stage": _stage}

func apply_state(state: Dictionary) -> void:
	_stage = clampi(int(state.get("stage", 0)), 0, STAGES)
	_refresh()

## Un feu bien nourri tient les prédateurs à distance et éclaire le camp.
func is_lit() -> bool:
	return _stage >= 2

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

## Flicker du feu : somme de sinus (léger, pas de dépendance) sur la lumière et les VFX.
func _process(delta: float) -> void:
	if _stage <= 0:
		return
	_flicker_t += delta
	var n := sin(_flicker_t * 11.3) * 0.5 + sin(_flicker_t * 23.7 + 1.7) * 0.3 + sin(_flicker_t * 5.1 + 0.4) * 0.2
	if _light != null:
		_light.light_energy = fire_light_energy * _stage / float(STAGES) * (1.0 + 0.16 * n)
	var ratio := clampf(maxf(0.4, _stage / float(STAGES)) * (1.0 + 0.22 * n), 0.0, 1.0)
	for p in get_children():
		if p is GPUParticles3D:
			p.amount_ratio = ratio

func _refresh() -> void:
	var lit := _stage > 0
	var scale_factor := maxf(0.4, _stage / float(STAGES))
	if _light != null:
		_light.light_energy = fire_light_energy * _stage / float(STAGES)
		_light.visible = lit
	if _mesh != null:
		_mesh.visible = lit
		_mesh.scale = Vector3.ONE * scale_factor
	# VFX : intensité des flammes/fumée/braises selon l'alimentation du feu.
	for p in get_children():
		if p is GPUParticles3D:
			p.emitting = lit
			p.amount_ratio = scale_factor
