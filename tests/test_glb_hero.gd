extends SceneTree
## Personnage GLB modulaire (V5) : chargement homme / femme, recoloration par profil,
## pièces affichées selon coiffure et équipement, poses os par os, repère de la main.

func _visible_names(hero: Node3D) -> Array:
	var names: Array = []
	for m in hero.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).visible:
			names.append(String(m.name))
	return names

func _make(profile: CharacterProfile) -> Node3D:
	var hero := Node3D.new()
	hero.set_script(load("res://scripts/player/glb_hero.gd"))
	hero.set("profile", profile)
	root.add_child(hero)
	hero.call("load_model")
	return hero

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var man := _make(CharacterProfile.default_for("male"))
	var woman := _make(CharacterProfile.default_for("female"))
	if man.get("skeleton") == null or woman.get("skeleton") == null:
		errors.append("les GLB doivent se charger (squelette absent)")
		print("FAIL: ", errors)
		quit(1)
		return
	if float(woman.call("body_height")) >= float(man.call("body_height")):
		errors.append("la femme doit être plus petite que l'homme")
	var m_names := _visible_names(man)
	for n in ["Body_Head", "Tunic", "Pants", "Shoes", "Hair_Short"]:
		if not m_names.has(n):
			errors.append("homme : %s attendu" % n)
	if m_names.has("Fur_Cape") or m_names.has("Straw_Hat_Crown") or m_names.has("High_Boots"):
		errors.append("sans objet fabriqué, aucun accessoire")
	var w_names := _visible_names(woman)
	for n in ["Female_Dress_Skirt", "Body_LowerLegs", "Shoes"]:
		if not w_names.has(n):
			errors.append("femme : %s attendu" % n)
	# Équipement : bottes remplacent les chaussures et cachent les jambes nues.
	woman.call("set_gear", ["gear_hide_boots", "armor_fur_cloak", "gear_straw_hat", "gear_backpack", "inconnu"])
	w_names = _visible_names(woman)
	if not w_names.has("High_Boots") or w_names.has("Shoes") or w_names.has("Body_LowerLegs"):
		errors.append("bottes : High_Boots remplace Shoes et les mollets nus")
	for n in ["Fur_Cape", "Straw_Hat_Crown", "Backpack"]:
		if not w_names.has(n):
			errors.append("équipement : %s attendu" % n)
	woman.call("set_gear", [])
	if _visible_names(woman).has("Fur_Cape"):
		errors.append("sans équipement, la cape disparaît")
	# Profil : couleurs et coiffures.
	var p := CharacterProfile.default_for("male")
	p.hair_style = 4
	p.beard = 2
	p.tunic = 3
	man.call("set_profile", p)
	m_names = _visible_names(man)
	if m_names.has("Hair_Short") or not m_names.has("Beard"):
		errors.append("chauve + barbe : pas de cheveux, barbe visible")
	var tunic_mesh := man.find_child("Tunic", true, false) as MeshInstance3D
	var mat := tunic_mesh.get_surface_override_material(0) as StandardMaterial3D
	if mat == null or not mat.albedo_color.is_equal_approx(CharacterProfile.TUNIC_COLORS[3]):
		errors.append("la tunique doit prendre la couleur du profil")
	for style in CharacterProfile.HAIR_STYLES.size():
		for gender in ["male", "female"]:
			var q := CharacterProfile.default_for(gender)
			q.hair_style = style
			woman.call("set_profile", q)
	# Changer de genre recharge le bon modèle.
	woman.call("set_profile", CharacterProfile.default_for("female"))
	var skeleton_before = woman.get("skeleton")
	woman.call("set_profile", CharacterProfile.default_for("male"))
	if woman.get("skeleton") == skeleton_before or not _visible_names(woman).has("Tunic"):
		errors.append("changer de genre recharge le modèle")
	# Poses : marche, outil en main, hache, arc.
	man.call("set_held_tool", "tool_stone_axe")
	var held := man.find_child("Held", true, false) as Node3D
	if held == null or held.get_child_count() == 0:
		errors.append("hache absente de la main")
	man.call("update_motion", 2.6, true, true)
	var head_id: int = man.get("skeleton").find_bone("mixamorig_LeftUpLeg")
	var angles: Array[float] = []
	for i in 40:
		man.call("advance_poses", 0.03)
		angles.append(man.get("skeleton").get_bone_global_pose(head_id).basis.get_euler().x)
	var lo: float = angles.min()
	var hi: float = angles.max()
	if hi - lo < 0.3:
		errors.append("la jambe doit se balancer à la marche (%f)" % (hi - lo))
	var hand_rest: Vector3 = man.call("hand_transform").origin
	man.call("play_chop")
	var top := -INF
	for i in 12:
		man.call("advance_poses", 0.03)
		top = maxf(top, (man.call("hand_transform") as Transform3D).origin.y)
	if top < hand_rest.y + 0.3:
		errors.append("le coup de hache doit lever la main (%f -> %f)" % [hand_rest.y, top])
	man.call("update_motion", 0.0, false, true)
	man.call("set_held_tool", "tool_hunting_bow")
	man.call("set_bow", true, 1.0)
	for i in 40:
		man.call("advance_poses", 0.03)
	if float(man.call("get_aim_weight")) < 0.9:
		errors.append("la visée doit s'établir")
	var hand: Transform3D = man.call("hand_transform")
	if hand.origin.z < 0.15:
		errors.append("à l'arc, la main droite part vers l'avant (%s)" % str(hand.origin))
	if errors.is_empty():
		print("PASS test_glb_hero")
		quit(0)
	else:
		for e in errors:
			print("FAIL: ", e)
		quit(1)
