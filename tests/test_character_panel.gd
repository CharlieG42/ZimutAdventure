extends SceneTree
## Fenêtre Personnage : vêtements par emplacement, porter / retirer, effets, sauvegarde.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	await process_frame
	var inventory := root.get_node("Inventory")
	var survival := root.get_node("SurvivalManager")
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	paused = false
	inventory.call("clear_for_test")
	var hud := world.get_node("HUD")
	var panel: CharacterPanel = hud.get("character_panel")
	_check(panel != null and hud.get("character_button") != null, "fenêtre et bouton Personnage présents")

	# Premier vêtement d'un emplacement : porté d'office.
	inventory.call("add_item", "gear_straw_hat", 1)
	_check(inventory.call("is_worn", "gear_straw_hat"), "chapeau porté d'office")
	inventory.call("add_item", "armor_fur_cloak", 1)
	inventory.call("add_item", "gear_hide_boots", 1)
	_check(inventory.call("get_worn") == ["gear_straw_hat", "armor_fur_cloak", "gear_hide_boots"], "trois emplacements remplis")

	hud.call("open_character_panel")
	await process_frame
	_check(panel.visible, "la fenêtre s'ouvre")
	_check(panel.call("preview_hero") != null, "aperçu 3D du personnage")
	var slots := ["head", "torso", "body", "hands", "legs", "feet", "back"]
	_check(slots.all(func(slot): return panel.find_child("Slot_" + slot, true, false) != null), "7 emplacements autour du personnage")
	(panel.find_child("Slot_head", true, false) as Button).pressed.emit()
	_check(panel.call("selected_slot") == "head", "emplacement Tête choisi")
	var hat_icon := panel.find_child("Slot_head", true, false).get_node("Icon") as ItemIcon
	_check(hat_icon.item_id == "gear_straw_hat" and hat_icon.modulate.a > 0.9, "icône du chapeau porté")
	var shirt_icon := panel.find_child("Slot_torso", true, false).get_node("Icon") as ItemIcon
	_check(shirt_icon.modulate.a < 0.5, "emplacement Chemise vide : icône estompée")
	var take_off := panel.find_child("Wear_gear_straw_hat", true, false) as Button
	_check(take_off != null and take_off.text == tr("ACTION_TAKE_OFF"), "bouton Retirer pour le chapeau")
	take_off.pressed.emit()
	await process_frame
	_check(not inventory.call("is_worn", "gear_straw_hat") and inventory.call("has_item", "gear_straw_hat", 1), "chapeau retiré, toujours dans le sac")
	var wear := panel.find_child("Wear_gear_straw_hat", true, false) as Button
	_check(wear != null and wear.text == tr("ACTION_WEAR"), "le bouton devient Porter")
	wear.pressed.emit()
	await process_frame
	_check(inventory.call("is_worn", "gear_straw_hat"), "chapeau remis")
	var preview: Node3D = panel.call("preview_hero")
	_check(preview.get("gear").has("gear_straw_hat"), "l'aperçu porte le chapeau")

	# Nouveaux vêtements : chemise, pantalon, gants (emplacements propres, chaleur).
	inventory.call("add_item", "gear_wool_shirt", 1)
	inventory.call("add_item", "gear_leather_gloves", 1)
	_check(inventory.call("worn_in", "torso") == "gear_wool_shirt" and inventory.call("worn_in", "hands") == "gear_leather_gloves", "chemise et gants portés")
	var context: Dictionary = survival.call("current_context") if survival.has_method("current_context") else {}
	var cold := {"season": "winter", "hour": 3.0, "weather": "clear", "altitude": 0.0}
	var with_gear := cold.duplicate()
	with_gear["gear_heat"] = 3.5
	_check(float(survival.call("felt_temperature", with_gear)) > float(survival.call("felt_temperature", cold)) + 3.0, "les vêtements de laine réchauffent")
	_check(preview.get("gear").has("gear_leather_gloves"), "l'aperçu porte les gants")

	# Effets : la cape protège seulement si elle est portée.
	survival.call("reset_for_test") if survival.has_method("reset_for_test") else null
	inventory.call("take_off", "body")
	var before: float = survival.call("get_health")
	survival.call("damage", 0.1)
	var lost_without: float = before - float(survival.call("get_health"))
	inventory.call("wear", "armor_fur_cloak")
	before = survival.call("get_health")
	survival.call("damage", 0.1)
	var lost_with: float = before - float(survival.call("get_health"))
	_check(lost_with < lost_without * 0.8, "cape portée : moins de dégâts (%.3f < %.3f)" % [lost_with, lost_without])

	# Le vêtement donné ou jeté n'est plus porté.
	inventory.call("remove_item", "gear_hide_boots", 1)
	_check(inventory.call("worn_in", "feet") == "", "bottes retirées quand elles quittent le sac")
	hud.call("open_character_panel")
	_check(not panel.visible, "le bouton referme la fenêtre")
	print("TEST_CHARACTER_PANEL: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
