extends SceneTree
## Défilement du journal : glissement partout, seuil de clic, inertie.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	await process_frame
	var scroll := KineticScroll.new()
	scroll.size = Vector2(300, 200)
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var clicked := [0]
	for i in 20:
		var card := PanelContainer.new()
		var button := Button.new()
		button.text = "Carte %d" % i
		button.custom_minimum_size = Vector2(0, 56)
		button.pressed.connect(func(): clicked[0] += 1)
		card.add_child(button)
		list.add_child(card)
	await process_frame
	await process_frame

	_check(scroll.get_v_scroll_bar().max_value > 400.0, "contenu plus haut que la zone")
	scroll.simulate_drag(150.0, 90.0)
	_check(scroll.scroll_vertical >= 55, "glisser vers le haut fait défiler (%d)" % scroll.scroll_vertical)
	var before := scroll.scroll_vertical
	scroll.simulate_drag(90.0, 150.0)
	_check(scroll.scroll_vertical < before, "glisser vers le bas remonte")

	# Un petit mouvement (< seuil) n'est pas un glissement.
	var pos := scroll.scroll_vertical
	scroll.simulate_drag(100.0, 104.0)
	_check(scroll.scroll_vertical == pos, "mouvement sous le seuil : pas de défilement")

	# Inertie : une vitesse restante continue de faire défiler après le relâchement.
	scroll.scroll_vertical = 0
	scroll._velocity = 1500.0
	for i in 10:
		await process_frame
	_check(scroll.scroll_vertical > 0, "l'inertie prolonge le défilement (%d)" % scroll.scroll_vertical)
	scroll.scroll_vertical = 0
	scroll._velocity = 1500.0
	for i in 400:
		await process_frame
	_check(absf(scroll._velocity) < 1.0, "l'inertie finit par s'arrêter")

	print("FAIL" if _failures > 0 else "PASS", " test_kinetic_scroll")
	quit(1 if _failures > 0 else 0)
