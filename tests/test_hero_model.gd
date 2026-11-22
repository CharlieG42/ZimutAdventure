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
	player.set("use_legacy_hero", true)
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
			# Poses procédurales : course, saut, hache, arc et selle déplacent réellement les os.
			var layer := hero.get("pose_layer") as SkeletonModifier3D
			if layer == null:
				errors.append("hero: couche de poses manquante")
			else:
				# Les poses n'existent que pendant la mise à jour du squelette : on les lit
				# par des attaches d'os (main droite, pied gauche).
				var foot := BoneAttachment3D.new()
				foot.bone_name = "mixamorig_LeftFoot"
				sk.add_child(foot)
				await process_frame
				await process_frame
				var rest_hand_y := (hero.call("hand_transform") as Transform3D).origin.y
				var rest_foot_y := foot.global_position.y
				for step in 60:
					hero.call("update_motion", 8.0, true, true)
					hero.call("advance_poses", 0.05)
				if float(layer.get("run")) < 0.9:
					errors.append("hero: la course doit activer sa pose (run=%.2f)" % float(layer.get("run")))
				hero.call("update_motion", 0.0, false, true)
				for step in 60:
					hero.call("advance_poses", 0.05)
				if float(layer.get("run")) > 0.05 or float(layer.get("idle")) < 0.9:
					errors.append("hero: à l'arrêt, respiration seule")
				for step in 60:
					hero.call("update_motion", 3.0, true, false)
					hero.call("advance_poses", 0.05)
				if float(layer.get("air")) < 0.9:
					errors.append("hero: le saut doit activer sa pose")
				hero.call("update_motion", 0.0, false, true)
				hero.call("play_chop")
				hero.call("advance_poses", 0.1)
				if float(layer.get("chop")) <= 0.0 or not bool(hero.call("is_chopping")):
					errors.append("hero: le coup de hache doit jouer")
				for step in 20:
					hero.call("advance_poses", 0.05)
				if float(layer.get("chop")) >= 0.0:
					errors.append("hero: le coup de hache doit se terminer")
				hero.call("set_bow", true, 1.0)
				for step in 60:
					hero.call("advance_poses", 0.05)
				if float(hero.call("get_aim_weight")) < 0.9 or float(layer.get("draw")) < 0.9:
					errors.append("hero: la visée doit lever et bander l'arc")
				await process_frame
				await process_frame
				var aimed_y := (hero.call("hand_transform") as Transform3D).origin.y
				if aimed_y - rest_hand_y < 0.1:
					errors.append("hero: le bras de l'arc doit se lever (%.2f m)" % (aimed_y - rest_hand_y))
				hero.call("set_bow", false, 0.0)
				hero.call("set_riding", true)
				for step in 60:
					hero.call("update_motion", 6.0, true, true)
					hero.call("advance_poses", 0.05)
				if ap.is_playing() or float(layer.get("run")) > 0.05:
					errors.append("hero: en selle, ni marche ni course")
				await process_frame
				await process_frame
				if foot.global_position.y - rest_foot_y < 0.05:
					errors.append("hero: en selle, les jambes doivent se plier (%.2f m)" % (foot.global_position.y - rest_foot_y))
				foot.queue_free()
				hero.call("set_riding", false)
				hero.call("update_motion", 0.0, false, true)
				for step in 60:
					hero.call("advance_poses", 0.05)
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
