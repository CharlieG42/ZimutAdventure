extends SceneTree
## Panneau du coffre : sélection objet par objet (sac <-> coffre) via les boutons des
## lignes, « tout déposer / tout reprendre », outils exclus, disposition paysage
## (2 colonnes) / portrait (empilées), fermeture par ui_cancel et par le journal.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	var inventory := root.get_node_or_null("Inventory")
	if inventory == null:
		inventory = load("res://scripts/autoload/inventory.gd").new()
		inventory.name = "Inventory"
		root.add_child(inventory)
	inventory.call("clear_for_test")

	var hud_scene := load("res://scenes/ui/hud.tscn") as PackedScene
	if hud_scene == null:
		printerr("TEST_CHEST_PANEL FAIL: hud.tscn missing")
		quit(1)
	var hud := hud_scene.instantiate() as CanvasLayer
	root.add_child(hud)
	await process_frame
	await process_frame

	var panel: Control = hud.get("chest_panel")
	if panel == null:
		printerr("TEST_CHEST_PANEL FAIL: chest_panel absent du HUD")
		quit(1)
	var chest: Node = load("res://scripts/interaction/chest.gd").create()
	root.add_child(chest)
	await process_frame

	inventory.call("add_item", "item_wood", 5)
	inventory.call("add_item", "item_stone", 3)
	inventory.call("add_item", "tool_stone_axe", 1)

	hud.call("open_chest_panel", chest)
	await process_frame
	if not panel.visible:
		errors.append("le panneau devrait être visible après open_chest_panel")

	var bag_list: Container = panel.get("_bag_list")
	var stock_list: Container = panel.get("_stock_list")
	# Sac : 2 lignes (bois, pierre) — l'outil est exclu ; coffre : liste « vide ».
	if bag_list.get_child_count() != 2:
		errors.append("sac : 2 lignes attendues (bois + pierre), got %d" % bag_list.get_child_count())
	if stock_list.get_child_count() != 1:
		errors.append("coffre vide : 1 ligne « vide » attendue, got %d" % stock_list.get_child_count())

	# Bouton « Déposer » de la ligne bois : transfère tout le stack (5).
	var wood_row := _find_row(bag_list, "ITEM_ITEM_WOOD")
	if wood_row == null:
		errors.append("ligne bois introuvable dans le sac")
	else:
		var btn := _row_button(wood_row)
		if btn == null:
			errors.append("bouton de transfert absent sur la ligne bois")
		else:
			btn.pressed.emit()
			await process_frame
			if inventory.call("count_of", "item_wood") != 0 or int(chest.call("total_stored")) != 5:
				errors.append("bouton déposer : 5 bois devraient être rangés, sac=%d stock=%d" % [inventory.call("count_of", "item_wood"), int(chest.call("total_stored"))])
	if bag_list.get_child_count() != 1:
		errors.append("après dépôt du bois, 1 ligne restante dans le sac, got %d" % bag_list.get_child_count())

	# « Tout déposer » : la pierre part aussi, l'outil reste.
	panel.call("_on_store_all")
	await process_frame
	if int(chest.call("total_stored")) != 8 or inventory.call("count_of", "item_stone") != 0:
		errors.append("tout déposer : stock devrait valoir 8, got %d" % int(chest.call("total_stored")))
	if inventory.call("count_of", "tool_stone_axe") != 1:
		errors.append("l'outil doit rester dans le sac")

	# Bouton « Reprendre » de la ligne bois du coffre : rend tout le stack (5).
	var wood_stock_row := _find_row(stock_list, "ITEM_ITEM_WOOD")
	if wood_stock_row == null:
		errors.append("ligne bois introuvable dans le coffre")
	else:
		_row_button(wood_stock_row).pressed.emit()
		await process_frame
		if inventory.call("count_of", "item_wood") != 5 or int(chest.call("total_stored")) != 3:
			errors.append("bouton reprendre : 5 bois devraient revenir, sac=%d stock=%d" % [inventory.call("count_of", "item_wood"), int(chest.call("total_stored"))])

	# « Tout reprendre ».
	panel.call("_on_take_all")
	await process_frame
	if int(chest.call("total_stored")) != 0 or inventory.call("count_of", "item_stone") != 3:
		errors.append("tout reprendre : coffre vide et pierre rendue, stock=%d pierre=%d" % [int(chest.call("total_stored")), inventory.call("count_of", "item_stone")])

	# Disposition : paysage = 2 colonnes côte à côte, portrait = empilées.
	panel.call("_fit_to_viewport", Vector2(1920, 1080))
	await process_frame
	var wide_box: Control = panel.get("_wide_box")
	var tall_box: Control = panel.get("_tall_box")
	var bag_col: Control = panel.get("_bag_col")
	if not wide_box.visible or tall_box.visible:
		errors.append("paysage 1920x1080 : la boîte horizontale devrait être visible")
	if bag_col.get_parent() != wide_box:
		errors.append("paysage : les colonnes devraient être dans la boîte horizontale")
	panel.call("_fit_to_viewport", Vector2(390, 844))
	await process_frame
	if wide_box.visible or not tall_box.visible:
		errors.append("portrait 390x844 : la boîte verticale devrait être visible")
	if bag_col.get_parent() != tall_box:
		errors.append("portrait : les colonnes devraient être dans la boîte verticale")
	panel.call("_fit_to_viewport")

	# Fermeture par ui_cancel.
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	panel.call("_unhandled_key_input", ev)
	if panel.visible:
		errors.append("ui_cancel devrait fermer le panneau")

	# Le journal se ferme mutuellement avec le panneau du coffre.
	hud.call("open_chest_panel", chest)
	await process_frame
	hud.call("_on_journal_pressed")
	await process_frame
	if panel.visible:
		errors.append("ouvrir le journal devrait fermer le panneau du coffre")
	var journal: Control = hud.get("journal_panel")
	if journal == null or not journal.visible:
		errors.append("le journal devrait être ouvert")

	if errors.is_empty():
		print("TEST_CHEST_PANEL: PASS")
		quit(0)
	else:
		for e in errors: printerr("TEST_CHEST_PANEL FAIL: " + e)
		quit(1)

## Ligne dont le libellé contient `key` (clé de traduction de l'item).
func _find_row(list: Container, key: String) -> Control:
	var needle := tr(key)
	for child in list.get_children():
		if child is HBoxContainer:
			for sub in (child as HBoxContainer).get_children():
				if sub is Label and needle in (sub as Label).text:
					return child as Control
	return null

func _row_button(row: Control) -> Button:
	for sub in row.get_children():
		if sub is Button:
			return sub as Button
	return null
