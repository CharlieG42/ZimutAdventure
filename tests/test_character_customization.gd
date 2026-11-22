extends SceneTree
## Personnage low-poly : profil sauvegardé, homme / femme, vêtements selon les objets fabriqués,
## animations, écran de création.

func _count_meshes(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for ch in n.get_children():
		c += _count_meshes(ch)
	return c

func _make_hero(profile: CharacterProfile) -> Node3D:
	var hero := Node3D.new()
	hero.set_script(load("res://scripts/player/lowpoly_hero.gd"))
	hero.set("profile", profile)
	hero.call("load_model")
	root.add_child(hero)
	return hero

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	CharacterProfile.clear_saved()
	if CharacterProfile.exists():
		errors.append("aucun profil ne doit exister au départ")

	# --- Profil ---------------------------------------------------------------------------
	var p := CharacterProfile.default_for("female")
	p.skin = 3
	p.hair_style = 3
	p.hair_color = 4
	p.tunic = 2
	p.eyes = 3
	p.beard = 2
	p.save()
	if not CharacterProfile.exists():
		errors.append("le profil doit être sauvegardé")
	var back := CharacterProfile.load_saved()
	if back.gender != "female" or back.skin != 3 or back.hair_style != 3 or back.hair_color != 4 or back.tunic != 2 or back.eyes != 3:
		errors.append("profil relu différent : %s" % str(back.to_dict()))
	if back.beard != 0:
		errors.append("une femme n'a pas de barbe")
	if false:
		errors.append("profil relu différent : %s" % str(back.to_dict()))
	var wild := CharacterProfile.from_dict({"gender": "robot", "skin": 99, "hair_style": -4})
	if wild.gender != "male" or wild.skin != CharacterProfile.SKIN_TONES.size() - 1 or wild.hair_style != 0:
		errors.append("valeurs hors limites à ramener dans la plage")

	# --- Homme et femme ---------------------------------------------------------------------
	var man := _make_hero(CharacterProfile.default_for("male"))
	var woman := _make_hero(CharacterProfile.default_for("female"))
	if float(woman.call("body_height")) >= float(man.call("body_height")):
		errors.append("la femme est plus petite que l'homme")
	var m_before := _count_meshes(man)
	man.call("set_gear", ["gear_straw_hat", "gear_hide_boots", "gear_backpack", "armor_fur_cloak", "inconnu"])
	if _count_meshes(man) <= m_before:
		errors.append("les vêtements doivent ajouter des pièces")
	if (man.get("gear") as Array).has("inconnu") or (man.get("gear") as Array).size() != 4:
		errors.append("seuls les vêtements connus sont portés : %s" % str(man.get("gear")))
	man.call("set_gear", [])
	if _count_meshes(man) != m_before:
		errors.append("sans vêtement, retour au corps nu")
	man.call("set_held_tool", "tool_knife")
	if not (man.find_child("Held", true, false) as Node3D).visible:
		errors.append("le couteau doit être visible en main")
	for tool_id in ["tool_stone_axe", "tool_sickle", "tool_hoe", "tool_watering_can", "tool_fishing_rod", "tool_hunting_bow"]:
		man.call("set_held_tool", tool_id)
		if (man.find_child("Held", true, false) as Node3D).get_child_count() == 0:
			errors.append("outil sans modèle : %s" % tool_id)
	# Changer de profil reconstruit le personnage (couleur de tunique).
	var other := CharacterProfile.default_for("male")
	other.tunic = 3
	woman.call("set_profile", other)
	if float(woman.call("body_height")) < float(man.call("body_height")) - 0.001:
		errors.append("changer de genre change la silhouette")

	# Toutes les coiffures et barbes se construisent ; les yeux clignent.
	for style in CharacterProfile.HAIR_STYLES.size():
		for beard in CharacterProfile.BEARDS.size():
			var variant := CharacterProfile.default_for("male")
			variant.hair_style = style
			variant.beard = beard
			var h := _make_hero(variant)
			if _count_meshes(h) < 60:
				errors.append("personnage trop pauvre (style %d barbe %d)" % [style, beard])
			h.free()
	var blinker := _make_hero(CharacterProfile.default_for("female"))
	var lids: Array = blinker.get("_eyelids")
	if lids.size() != 2:
		errors.append("deux paupières attendues")
	blinker.set("_next_blink", 0.0)
	blinker.call("advance_poses", 0.01)
	if (lids[0] as Node3D).scale.y < 0.5:
		errors.append("le personnage doit cligner des yeux")

	# --- Animations -------------------------------------------------------------------------
	var hero := _make_hero(CharacterProfile.default_for("male"))
	var hip_l: Node3D = hero.get("_leg")["l"]["hip"]
	hero.call("update_motion", 0.0, false, true)
	for i in 10:
		hero.call("advance_poses", 0.05)
	var idle_x := hip_l.rotation.x
	if not bool(hero.call("is_resting")):
		errors.append("à l'arrêt, le personnage est au repos")
	hero.call("update_motion", 3.0, true, true)
	var swung := 0.0
	for i in 30:
		hero.call("advance_poses", 0.05)
		swung = maxf(swung, absf(hip_l.rotation.x - idle_x))
	if swung < 0.3:
		errors.append("la marche doit balancer les jambes (%.2f)" % swung)
	hero.call("update_motion", 0.0, false, true)
	for i in 40:
		hero.call("advance_poses", 0.05)
	hero.call("play_chop")
	var arm_r: Node3D = hero.get("_arm")["r"]["shoulder"]
	var raised := 0.0
	for i in 12:
		hero.call("advance_poses", 0.03)
		raised = minf(raised, arm_r.rotation.x)
	if raised > -1.5:
		errors.append("le coup de hache doit lever le bras (%.2f)" % raised)
	hero.call("set_bow", true, 1.0)
	for i in 30:
		hero.call("advance_poses", 0.05)
	if float(hero.call("get_aim_weight")) < 0.9 or arm_r.rotation.x > -1.2:
		errors.append("la visée doit tendre le bras droit")
	hero.call("set_bow", false, 0.0)
	hero.call("set_riding", true)
	for i in 30:
		hero.call("advance_poses", 0.05)
	if hip_l.rotation.x > -0.9:
		errors.append("à cheval, les cuisses sont vers l'avant (%.2f)" % hip_l.rotation.x)
	hero.call("set_riding", false)
	hero.call("update_motion", 3.0, true, false)
	for i in 20:
		hero.call("advance_poses", 0.05)
	if float(hero.get("_air_w")) < 0.8:
		errors.append("en l'air, la pose de saut s'active")

	# --- Fabrication de vêtements ---------------------------------------------------------------
	var craft: Node = root.get_node("CraftManager")
	var clothes: Array = craft.call("get_recipes_in_category", "clothes")
	for id in ["gear_straw_hat", "gear_hide_boots", "gear_backpack", "armor_fur_cloak"]:
		if not clothes.has(id):
			errors.append("recette de vêtement absente : %s" % id)
	for key in ["CHAR_BEARD_FULL", "CHAR_EYES", "CHAR_HAIR_BRAID", "CRAFT_STRAW_HAT", "ITEM_GEAR_BACKPACK", "CAT_CLOTHES", "CHAR_TITLE", "CHAR_HAIR_BUN"]:
		if tr(key) == key:
			errors.append("traduction manquante : %s" % key)

	# --- Écran de création ------------------------------------------------------------------------
	var creator := CharacterCreator.new()
	root.add_child(creator)
	await process_frame
	var confirmed: Array = []
	creator.confirmed.connect(func(pr): confirmed.append(pr))
	creator.open(CharacterProfile.default_for("male"), true)
	await process_frame
	if not creator.visible or not paused:
		errors.append("l'écran de création s'ouvre et met le jeu en pause")
	creator.call("_set_gender", "female")
	if creator.profile.gender != "female" or creator.profile.hair_style != 1:
		errors.append("choisir Femme propose la coiffure par défaut")
	creator.profile.skin = 4
	creator.call("_on_done")
	await process_frame
	if confirmed.is_empty() or creator.visible or paused:
		errors.append("valider ferme l'écran, relance le jeu et confirme")
	elif CharacterProfile.load_saved().skin != 4 or CharacterProfile.load_saved().gender != "female":
		errors.append("la validation sauvegarde le profil")
	CharacterProfile.clear_saved()

	if errors.is_empty():
		print("TEST_CHARACTER_CUSTOMIZATION: PASS")
		quit(0)
	else:
		for e in errors: printerr("TEST_CHARACTER_CUSTOMIZATION FAIL: " + e)
		quit(1)
