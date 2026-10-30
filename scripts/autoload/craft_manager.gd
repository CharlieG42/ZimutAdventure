extends Node
## Fabrication et construction : recettes d'outils, meubles, armes et habitations.

signal crafted(recipe_id: String)
signal built(recipe_id: String, position: Vector3)

## Recettes : id -> {nom, ingrédients {id: qté}, catégorie, optionnel scène}
const RECIPES := {
	"tool_stone_axe": {
		"name": "CRAFT_STONE_AXE",
		"category": "tools",
		"ingredients": {"item_stone": 2, "item_wood": 1},
	},
	"tool_hunting_bow": {
		"name": "CRAFT_HUNTING_BOW",
		"category": "weapons",
		"ingredients": {"item_wood": 3},
	},
	"arrow": {
		"name": "CRAFT_ARROWS",
		"category": "weapons",
		"ingredients": {"item_wood": 1, "item_stone": 1},
		"batch": 4,
	},
	"furniture_camp_bed": {
		"name": "CRAFT_CAMP_BED",
		"category": "furniture",
		"ingredients": {"item_wood": 4},
	},
	"building_shelter": {
		"name": "CRAFT_SHELTER",
		"category": "buildings",
		"ingredients": {"item_wood": 8, "item_stone": 4},
	},
}

## Catégories affichées dans le menu de fabrication.
const CATEGORIES := ["tools", "weapons", "furniture", "buildings"]

func get_recipe_name(recipe_id: String) -> String:
	if RECIPES.has(recipe_id):
		return RECIPES[recipe_id].get("name", recipe_id)
	return recipe_id

func get_ingredients(recipe_id: String) -> Dictionary:
	if RECIPES.has(recipe_id):
		return (RECIPES[recipe_id].get("ingredients", {}) as Dictionary).duplicate()
	return {}

func get_recipe_ids() -> Array:
	return RECIPES.keys()

func get_category(recipe_id: String) -> String:
	if RECIPES.has(recipe_id):
		return String(RECIPES[recipe_id].get("category", ""))
	return ""

## Recettes d'une catégorie, dans l'ordre de déclaration.
func get_recipes_in_category(category: String) -> Array:
	var ids: Array = []
	for recipe_id in RECIPES:
		if RECIPES[recipe_id].get("category", "") == category:
			ids.append(recipe_id)
	return ids

## Quantité manquante pour chaque ingrédient (0 = disponible).
func get_missing(recipe_id: String) -> Dictionary:
	var missing := {}
	var inventory := InteractionManager.get_inventory()
	for item_id in get_ingredients(recipe_id):
		var need := int(get_ingredients(recipe_id)[item_id])
		var have := int(inventory.call("count_of", item_id)) if inventory != null else 0
		missing[item_id] = maxi(0, need - have)
	return missing

func can_craft(recipe_id: String) -> bool:
	if not RECIPES.has(recipe_id):
		return false
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return false
	for item_id in RECIPES[recipe_id]["ingredients"]:
		if not inventory.has_item(item_id, int(RECIPES[recipe_id]["ingredients"][item_id])):
			return false
	return true

## Fabrique l'objet : consomme les ingrédients, ajoute l'objet fini à l'inventaire.
func craft(recipe_id: String) -> bool:
	if not can_craft(recipe_id):
		return false
	var inventory := InteractionManager.get_inventory()
	for item_id in RECIPES[recipe_id]["ingredients"]:
		inventory.remove_item(item_id, int(RECIPES[recipe_id]["ingredients"][item_id]))
	var batch := int(RECIPES[recipe_id].get("batch", 1))
	inventory.add_item(recipe_id, batch)
	crafted.emit(recipe_id)
	return true

## Liste des recettes fabriquables en ce moment.
func get_craftable() -> Array:
	var craftable: Array = []
	for recipe_id in RECIPES:
		if can_craft(recipe_id):
			craftable.append(recipe_id)
	return craftable

func _get_inventory() -> Node:
	return InteractionManager.get_inventory()
