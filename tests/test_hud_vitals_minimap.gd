extends SceneTree
## Barres vitales latérales, mini-carte et invite « Ramasser » qui disparaît après usage.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	await process_frame
	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame

	var vitals: Control = hud.get_node("Overlay/Vitals")
	var minimap: Control = hud.get_node("Overlay/MiniMap")
	_check(vitals != null and vitals.visible, "les jauges sont visibles même pleines")
	vitals.call("set_value", "thirst", 0.1)
	_check(vitals.call("is_low", "thirst") and not vitals.call("is_low", "hunger"), "soif basse détectée seule")
	vitals.call("set_value", "energy", 0.5)
	_check(is_equal_approx(float(vitals.call("get_value", "energy")), 0.5), "énergie mémorisée")
	_check(minimap != null and minimap.visible, "mini-carte visible")
	_check(hud.get_node_or_null("SafeArea/VBox/BottomBar/MapButton") == null, "plus de bouton Carte dans la barre du bas")
	var map_panel: Control = hud.get_node("MapPanel")
	_check(not map_panel.visible, "carte fermée au départ")
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = Vector2(80, 80)
	minimap._gui_input(tap)
	_check(map_panel.visible, "toucher la mini-carte ouvre la carte")
	await process_frame
	_check(not minimap.visible, "la mini-carte s'efface carte ouverte")
	map_panel.close()
	await process_frame
	_check(minimap.visible, "la mini-carte revient à la fermeture")
	var center: Vector2 = minimap.call("world_to_local", 0.0, 0.0)
	_check(center.distance_to(Vector2(85, 85)) < 0.01, "sans joueur, l'origine est au centre")

	# Invite : visible quand un objet est interactif, masquée dès qu'il est consommé.
	var item := Interactable.new()
	item.one_shot = true
	root.add_child(item)
	hud.call("_on_focus_changed", item)
	var button: Button = hud.get_node("Overlay/ActionPad/InteractButton")
	var prompt: Label = hud.get_node("Overlay/CenterPrompt")
	_check(prompt.visible and button.visible, "invite affichée pour un objet utilisable")
	item.interact(null)
	await process_frame
	await process_frame
	_check(not prompt.visible and not button.visible, "invite masquée une fois l'objet utilisé")

	# Objet détruit.
	var item2 := Interactable.new()
	root.add_child(item2)
	hud.call("_on_focus_changed", item2)
	item2.free()
	await process_frame
	await process_frame
	_check(not prompt.visible and not button.visible, "invite masquée si l'objet disparaît")

	print("FAIL" if _failures > 0 else "PASS", " test_hud_vitals_minimap")
	quit(1 if _failures > 0 else 0)
