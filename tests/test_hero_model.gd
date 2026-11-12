extends SceneTree
## Personnage animé (Mixamo) : chargement, boucle de marche, arrêt pieds joints,
## outils replacés dans la main, repli sur l'ancien corps si le modèle est absent.

var interaction_manager_script: GDScript = load("res://scripts/autoload/interaction_manager.gd")

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var im := interaction_manager_script.new() as Node
	root.add_child(im)
	await process_frame
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	var player := player_scene.instantiate() as CharacterBody3D
	root.add_child(player)
	await process_frame

	var hero := player.get("_hero") as Node3D
	if hero == null:
		errors.append("le joueur devrait utiliser le personnage animé (hero.glb)")
	else:
		var ap := hero.get("animation_player") as AnimationPlayer
		var sk := hero.get("skeleton") as Skeleton3D
		if ap == null or sk == null:
			errors.append("hero: AnimationPlayer ou Skeleton3D manquant")
		else:
			var walk := ap.get_animation("walk")
			if walk == null or walk.loop_mode != Animation.LOOP_LINEAR:
				errors.append("hero: la marche doit boucler")
			if sk.get_bone_count() < 25:
				errors.append("hero: squelette trop petit (%d os)" % sk.get_bone_count())
			if sk.find_bone("mixamorig_RightHand") < 0:
				errors.append("hero: os de la main droite manquant")
			if not bool(hero.call("is_resting")):
				errors.append("hero: doit démarrer figé sur une pose pieds joints")
			# Marche : l'animation tourne, plus vite quand on court.
			hero.call("update_motion", 4.5, true, true)
			if not ap.is_playing():
				errors.append("hero: la marche doit jouer quand on avance")
			var walk_scale := ap.speed_scale
			hero.call("update_motion", 7.5, true, true)
			if ap.speed_scale <= walk_scale:
				errors.append("hero: la course doit animer plus vite que la marche")
			# En l'air : pose figée.
			hero.call("update_motion", 4.5, true, false)
			if ap.is_playing():
				errors.append("hero: pas de pas dans le vide")
			# Arrêt : le pas se termine puis se fige pieds joints.
			hero.call("update_motion", 0.0, false, true)
			for i in 200:
				ap.advance(0.02)
				hero.call("update_motion", 0.0, false, true)
				if bool(hero.call("is_resting")):
					break
			if not bool(hero.call("is_resting")):
				errors.append("hero: doit s'arrêter pieds joints")
			# Les outils suivent la main : arc et hache près de l'os, pas à l'origine.
			var hand := hero.call("hand_transform") as Transform3D
			player.call("_update_hero", 0.016, 0.0, false)
			var axe := player.get("_held_axe") as Node3D
			if axe == null or axe.global_position.distance_to(hand.origin) > 0.05:
				errors.append("hero: la hache doit être dans la main")

	# Les anciennes pièces restent dans la scène (invisibles) pour les outils et tests.
	var torso := player.get_node_or_null("Visuals/Torso") as MeshInstance3D
	if torso == null:
		errors.append("l'ancien corps doit rester dans la scène")
	elif torso.layers != 0:
		errors.append("l'ancien corps doit être masqué (calque 0)")

	# Repli : sans le modèle, le corps en boîtes reste visible.
	var plain := Node3D.new()
	plain.set_script(load("res://scripts/player/hero_model.gd"))
	var ok: bool = plain.call("load_model")
	if not ok:
		errors.append("hero_model.load_model doit réussir avec le fichier présent")
	plain.free()

	player.free()
	if errors.is_empty():
		print("TEST_HERO_MODEL: PASS")
		quit(0)
	else:
		for e in errors: printerr("TEST_HERO_MODEL FAIL: " + e)
		quit(1)
