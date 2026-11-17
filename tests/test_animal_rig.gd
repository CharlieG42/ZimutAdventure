extends SceneTree
## Animaux en vrais modèles animés (Quaternius, CC0) : chaque espèce prévue charge son
## modèle à la bonne taille, possède ses animations et les choisit selon le déplacement ;
## chute puis relève ; teinte du coyote ; pas d'ombre portée ; les autres espèces gardent
## leur modèle construit en code.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var holder := Node3D.new()
	root.add_child(holder)
	var models: Dictionary = AnimalRig.MODELS

	for kind in models:
		var rig := AnimalRig.create(kind, 1.0, 1.0, 11)
		if rig == null:
			errors.append("%s : modèle introuvable" % kind)
			continue
		holder.add_child(rig)
		for role in ["idle", "walk", "death"]:
			if not rig.has_role(role):
				errors.append("%s : animation « %s » manquante" % [kind, role])
		# Hauteur : mesurée sur le squelette après mise à l'échelle (variantes comprises).
		var heights: Array = [float(models[kind]["height"])]
		heights.append_array(models[kind].get("variant_heights", []))
		var top := 0.0
		for i in rig.skeleton.get_bone_count():
			var p := (rig.global_transform.affine_inverse() * rig.skeleton.global_transform * rig.skeleton.get_bone_global_rest(i)).origin
			top = maxf(top, p.y)
		var measured := top * 1.05
		var ok := false
		for h in heights:
			if absf(measured - float(h)) < float(h) * 0.06:
				ok = true
		if not ok:
			errors.append("%s : hauteur %.2f m au lieu de %s" % [kind, measured, str(heights)])
		for mesh in rig.find_children("*", "MeshInstance3D", true, false):
			if (mesh as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				errors.append("%s : pas d'ombre portée (un disque au sol la remplace)" % kind)
				break
		# Choix de l'animation selon la vitesse.
		rig.update_motion(0.0, false, 0.1)
		if not rig.get_current_role().begins_with("idle"):
			errors.append("%s : au repos à l'arrêt (%s)" % [kind, rig.get_current_role()])
		rig.update_motion(1.2, false, 0.1)
		if rig.get_current_role() != "walk":
			errors.append("%s : marche à 1,2 m/s (%s)" % [kind, rig.get_current_role()])
		if rig.has_role("run"):
			rig.update_motion(8.0, false, 0.1)
			if rig.get_current_role() != "run" and rig.get_clip("run") != rig.get_clip("walk"):
				errors.append("%s : galop à 8 m/s (%s)" % [kind, rig.get_current_role()])
		rig.update_motion(0.0, true, 0.1)
		if rig.get_current_role() != "eat":
			errors.append("%s : broute à l'arrêt (%s)" % [kind, rig.get_current_role()])
		# Les boucles bouclent, la chute non.
		var walk := rig.animation_player.get_animation(rig.get_clip("walk"))
		if walk.loop_mode != Animation.LOOP_LINEAR:
			errors.append("%s : la marche doit boucler" % kind)
		if rig.play_death() <= 0.0 or not rig.is_dead():
			errors.append("%s : la chute dure un instant" % kind)
		rig.update_motion(3.0, false, 0.1)
		if rig.get_current_role() != "death":
			errors.append("%s : à terre, l'animal ne repart pas" % kind)
		rig.revive()
		if rig.is_dead() or not rig.get_current_role().begins_with("idle"):
			errors.append("%s : se relève au repos" % kind)

	# Le coyote n'a plus la robe orange du renard.
	var coyote := AnimalRig.create("coyote", 1.0, 1.0, 3)
	holder.add_child(coyote)
	for mesh in coyote.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var material := mi.get_surface_override_material(i) as BaseMaterial3D
			if material != null and material.resource_name == "Main":
				var c := material.albedo_color
				if c.r - c.b > 0.35:
					errors.append("le coyote doit être fauve grisé, pas orange (%s)" % c)

	# Intégration : un cerf, un loup, un cheval ont leur modèle animé ; une poule non.
	var cases := [["res://scenes/world/passive_animal.tscn", "deer", true], ["res://scenes/world/predator.tscn", "wolf", true],
			["res://scenes/world/domestic_animal.tscn", "horse", true], ["res://scenes/world/domestic_animal.tscn", "chicken", false],
			["res://scenes/world/passive_animal.tscn", "rabbit", false]]
	for c in cases:
		var animal := (load(c[0]) as PackedScene).instantiate()
		animal.set("species", c[1])
		holder.add_child(animal)
		await process_frame
		var has_rig: bool = animal.get("_rig") != null
		if has_rig != bool(c[2]):
			errors.append("%s : modèle animé attendu = %s" % [c[1], str(c[2])])
		if has_rig and animal.get_node_or_null("GroundShadow") == null:
			errors.append("%s : disque d'ombre au sol" % c[1])
		animal.queue_free()
	await process_frame

	holder.queue_free()
	if errors.is_empty():
		print("TEST_ANIMAL_RIG: PASS")
		quit(0)
	else:
		for e in errors:
			print("TEST_ANIMAL_RIG FAIL: " + e)
		quit(1)
