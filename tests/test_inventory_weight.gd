extends SceneTree
## Poids du sac : poids par objet, capacité (40 kg + niveau ; sac à dos porté = +25 kg), facteur de
## vitesse selon la charge, surcharge (> 100 %) qui bloque la course, affichage HUD.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	var inventory := root.get_node_or_null("Inventory")
	if inventory == null:
		inventory = load("res://scripts/autoload/inventory.gd").new()
		inventory.name = "Inventory"
		root.add_child(inventory)
	inventory.call("clear_for_test")
	var progression := root.get_node_or_null("Progression")
	if progression != null:
		progression.call("clear_for_test", true)
	var script := load("res://scripts/autoload/inventory.gd") as GDScript

	# Poids par objet et poids inconnu par défaut.
	if absf(script.item_weight("item_stone") - 0.8) > 0.001:
		errors.append("item_stone devrait peser 0,8 kg, got %f" % script.item_weight("item_stone"))
	if absf(script.item_weight("item_qqchose_inconnu") - 0.5) > 0.001:
		errors.append("poids par défaut devrait être 0.5 kg")

	inventory.call("add_item", "item_stone", 10)
	if absf(float(inventory.call("total_weight")) - 8.0) > 0.001:
		errors.append("10 pierres = 8 kg, got %f" % float(inventory.call("total_weight")))
	if absf(float(inventory.call("capacity")) - 40.0) > 0.001:
		errors.append("capacité de base = 40 kg, got %f" % float(inventory.call("capacity")))
	if absf(float(inventory.call("weight_fraction")) - 0.2) > 0.001:
		errors.append("fraction = 8/40 = 0.2, got %f" % float(inventory.call("weight_fraction")))

	# Courbe du facteur de vitesse : à l'aise jusqu'à 60 %, minimum 0.5 à 120 %.
	if absf(script.speed_factor(0.2) - 1.0) > 0.001 or absf(script.speed_factor(0.6) - 1.0) > 0.001:
		errors.append("speed_factor devrait valoir 1.0 jusqu'à 60 %%")
	if absf(script.speed_factor(1.2) - 0.5) > 0.001:
		errors.append("speed_factor devrait valoir 0.5 à 120 %%, got %f" % script.speed_factor(1.2))
	var mid := float(script.speed_factor(0.9))
	if not (mid > 0.5 and mid < 1.0):
		errors.append("speed_factor(0.9) devrait être entre 0.5 et 1.0, got %f" % mid)

	# Le sac à dos porté (auto-porté au premier exemplaire) augmente la capacité.
	inventory.call("add_item", "gear_backpack", 1)
	if absf(float(inventory.call("capacity")) - 65.0) > 0.001:
		errors.append("sac à dos porté : capacité 65 kg, got %f" % float(inventory.call("capacity")))

	# Surcharge : 100 pierres (80 kg) sur 65 kg (le sac à dos porté ne pèse rien).
	inventory.call("add_item", "item_stone", 90)
	if absf(float(inventory.call("total_weight")) - 80.0) > 0.01:
		errors.append("poids total attendu 80 kg, got %f" % float(inventory.call("total_weight")))
	if not bool(inventory.call("is_overloaded")):
		errors.append("80/65 kg devrait être une surcharge")
	if absf(float(inventory.call("get_speed_factor")) - 0.5) > 0.001:
		errors.append("surcharge : facteur de vitesse 0.5, got %f" % float(inventory.call("get_speed_factor")))

	# Le joueur applique le facteur et bloque la course en surcharge ; le HUD affiche le poids.
	var player_text := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	if not player_text.contains("get_speed_factor") or not player_text.contains("_overloaded"):
		errors.append("player.gd devrait appliquer get_speed_factor et gérer _overloaded")
	var hud_text := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	if not hud_text.contains("_update_weight_label"):
		errors.append("hud.gd devrait afficher le poids du sac (_update_weight_label)")

	for lang in ["fr", "en"]:
		var csv := FileAccess.get_file_as_string("res://locales/translations.%s.csv" % lang)
		for key in ["HUD_WEIGHT", "TOAST_OVERLOADED", "GEAR_EFFECT_BACKPACK"]:
			if not csv.contains(key + ","):
				errors.append("%s : clé %s manquante" % [lang, key])

	if errors.is_empty():
		print("TEST_INVENTORY_WEIGHT: PASS")
		quit(0)
	else:
		for e in errors: printerr("TEST_INVENTORY_WEIGHT FAIL: " + e)
		quit(1)
