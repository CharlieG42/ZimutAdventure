extends SceneTree
## Poids du sac allégé (vêtements portés exclus, capacité qui grandit avec le niveau) et
## amélioration des vêtements (niveaux, coût, niveau requis, effets, sauvegarde).

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
	var progression := root.get_node("Progression")
	var survival := root.get_node("SurvivalManager")
	inventory.call("clear_for_test")
	progression.call("clear_for_test", true)
	_check(is_equal_approx(float(inventory.call("capacity")), 40.0), "capacité de base 40 kg")
	inventory.call("add_item", "item_wood", 40)
	inventory.call("add_item", "item_stone", 20)
	_check(float(inventory.call("total_weight")) <= 36.0, "40 bois + 20 pierres tiennent dans le sac (%.1f kg)" % float(inventory.call("total_weight")))
	inventory.call("add_item", "gear_backpack", 1)
	_check(inventory.call("is_worn", "gear_backpack"), "sac à dos porté")
	_check(is_equal_approx(float(inventory.call("capacity")), 65.0), "sac à dos niveau 1 : +25 kg")
	var weight_worn: float = inventory.call("total_weight")
	inventory.call("take_off", "back")
	_check(float(inventory.call("total_weight")) > weight_worn, "un vêtement porté ne pèse pas dans le sac")
	inventory.call("wear", "gear_backpack")
	progression.call("add_xp", 3000)
	var level: int = progression.call("get_level")
	_check(float(inventory.call("capacity")) >= 65.0 + float(mini(level - 1, 30)) - 0.01, "+1 kg par niveau (niveau %d)" % level)

	# Amélioration : niveau requis, coût, effet.
	progression.call("clear_for_test", true)
	inventory.call("add_item", "item_pelt", 10)
	_check(inventory.call("upgrade_gear", "gear_backpack") == "TOAST_UPGRADE_LEVEL", "niveau de joueur 4 requis")
	progression.call("add_xp", 100000)
	var wood_before: int = inventory.call("count_of", "item_wood")
	_check(inventory.call("upgrade_gear", "gear_backpack") == "", "sac à dos amélioré au niveau 2")
	_check(inventory.call("gear_level", "gear_backpack") == 2, "niveau 2")
	_check(int(inventory.call("count_of", "item_wood")) == wood_before - 4, "coût prélevé (4 bois)")
	_check(float(inventory.call("worn_stat", "capacity")) == 45.0, "sac à dos niveau 2 : +45 kg")
	inventory.call("add_item", "item_wool", 5)
	_check(inventory.call("upgrade_gear", "gear_backpack") == "", "niveau 3")
	_check(inventory.call("upgrade_gear", "gear_backpack") == "TOAST_MAX_LEVEL", "niveau maximum")

	# Cape améliorée : moins de dégâts.
	inventory.call("add_item", "armor_fur_cloak", 1)
	var health_before: float = survival.call("get_health")
	survival.call("damage", 0.2)
	var lost_l1: float = health_before - float(survival.call("get_health"))
	inventory.call("add_item", "item_pelt", 3)
	inventory.call("add_item", "item_wool", 2)
	_check(inventory.call("upgrade_gear", "armor_fur_cloak") == "", "cape niveau 2")
	health_before = survival.call("get_health")
	survival.call("damage", 0.2)
	var lost_l2: float = health_before - float(survival.call("get_health"))
	_check(lost_l2 < lost_l1 - 0.005, "cape niveau 2 : encore moins de dégâts (%.3f < %.3f)" % [lost_l2, lost_l1])
	_check(is_equal_approx(float(inventory.call("worn_stat", "heat")), 8.5), "cape niveau 2 : +8,5 °C")

	# Fenêtre : texte d'effet et bouton.
	var panel := CharacterPanel.new()
	root.add_child(panel)
	await process_frame
	_check(panel.call("effect_text", "armor_fur_cloak", 3).contains("10"), "effet du niveau 3 affiché")
	panel.call("open")
	panel.set("_selected_slot", "head")
	inventory.call("add_item", "gear_straw_hat", 1)
	panel.call("refresh")
	var button := panel.find_child("Upgrade_gear_straw_hat", true, false) as Button
	_check(button != null and button.disabled, "bouton Améliorer grisé sans blé")
	inventory.call("add_item", "item_wheat", 4)
	panel.call("refresh")
	button = panel.find_child("Upgrade_gear_straw_hat", true, false) as Button
	_check(button != null and not button.disabled, "bouton actif avec le blé")
	button.pressed.emit()
	_check(inventory.call("gear_level", "gear_straw_hat") == 2 and is_equal_approx(float(inventory.call("worn_stat", "thirst")), 0.3), "chapeau niveau 2 : soif −30 %")
	print("TEST_GEAR_WEIGHT: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
