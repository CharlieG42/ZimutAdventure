extends SceneTree
## Bundle « vivant » : vent sur la végétation basse (shader + uniform global player_pos)
## et traces de pas du joueur (pose au sol, alternance, fondu, pool plafonné).

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	# --- Texture d'empreinte ---
	var fp: Texture2D = load("res://assets/vfx/overlays/footprint.png")
	if fp == null or fp.get_size().x < 64:
		errors.append("footprint.png manquante ou trop petite")
	elif fp.get_image() != null:
		var img := fp.get_image()
		var a_max := 0
		for y in range(0, img.get_height(), 8):
			for x in range(0, img.get_width(), 8):
				a_max = maxi(a_max, int(img.get_pixel(x, y).a * 255.0))
		if a_max < 200:
			errors.append("footprint.png : alpha max trop faible (%d)" % a_max)

	# --- Shader de vent ---
	if load("res://assets/vfx/shaders/wind_sway.gdshader") == null:
		errors.append("wind_sway.gdshader manquant")

	# --- Monde : MultiMesh d'herbe/buissons en matériau shader de vent ---
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in range(8):
		await process_frame
	var windy := 0
	var props := world.get_node_or_null("Landscape/Props")
	if props == null:
		errors.append("Landscape/Props manquant")
	else:
		for c in props.get_children():
			if c is MultiMeshInstance3D:
				var mm: MultiMesh = (c as MultiMeshInstance3D).multimesh
				var mesh: Mesh = mm.mesh if mm != null else null
				if mesh != null and mesh.get_surface_count() > 0:
					var m0: Material = mesh.surface_get_material(0)
					if m0 is ShaderMaterial and (m0 as ShaderMaterial).shader != null:
						var p = (m0 as ShaderMaterial).get_shader_parameter("wind_strength")
						if p != null and float(p) > 0.0:
							windy += 1
	if windy < 2:
		errors.append("moins de 2 MultiMesh au vent (%d) — herbe/buissons/fleurs attendus" % windy)
	# Uniforme global player_pos : déclaré dans le shader et posable via RenderingServer.
	var shader_txt := ""
	var f := FileAccess.open("res://assets/vfx/shaders/wind_sway.gdshader", FileAccess.READ)
	if f != null:
		shader_txt = f.get_as_text()
		f.close()
	if "global uniform vec3 player_pos" not in shader_txt:
		errors.append("wind_sway.gdshader ne déclare pas 'global uniform vec3 player_pos'")
	if not ProjectSettings.has_setting("shader_globals/player_pos"):
		errors.append("player_pos n'est pas déclaré dans [shader_globals] de project.godot")
	# Le landscape pose l'uniforme chaque frame (contrat source ; en headless le dummy
	# renderer ne compile pas les shaders, donc pas de roundtrip RenderingServer).
	var lm_txt := ""
	var f2 := FileAccess.open("res://scripts/world/landscape_manager.gd", FileAccess.READ)
	if f2 != null:
		lm_txt = f2.get_as_text()
		f2.close()
	if "global_shader_parameter_set(\"player_pos\"" not in lm_txt:
		errors.append("landscape_manager.gd ne pose pas l'uniforme global player_pos")

	# --- Traces de pas : API testable directement ---
	var footprints := world.get_node_or_null("Footprints") as Footprints
	if footprints == null:
		errors.append("nœud Footprints manquant dans la scène")
	else:
		footprints.set_process(false)  # test déterministe : on pilote à la main
		footprints.set("_last_pos", Vector3.ZERO)
		footprints.try_spawn(Vector3(0, 0, 0), 0.0, true, 2.0)   # amorce
		footprints.try_spawn(Vector3(0.2, 0, 0), 0.0, true, 2.0)   # trop proche
		if footprints.mark_count() != 0:
			errors.append("pas de trace sous le seuil de distance (%d)" % footprints.mark_count())
		footprints.try_spawn(Vector3(1.0, 0, 0), 0.0, true, 2.0)   # 1 m -> 1 trace
		footprints.try_spawn(Vector3(2.0, 0, 0), 0.0, true, 2.0)
		if footprints.mark_count() != 2:
			errors.append("2 déplacements de 1 m -> 2 traces attendues, got %d" % footprints.mark_count())
		footprints.try_spawn(Vector3(3.0, 0, 0), 0.0, false, 2.0)  # dans les airs : rien
		if footprints.mark_count() != 2:
			errors.append("pas de trace en l'air (%d)" % footprints.mark_count())
		# Pool plafonné.
		for i in range(80):
			footprints.try_spawn(Vector3(10.0 + i, 0, 0), 0.0, true, 2.0)
		if footprints.mark_count() > 48:
			errors.append("pool non plafonné : %d > 48" % footprints.mark_count())
		# Fondu puis disparition.
		footprints.age_marks(25.0)
		if footprints.mark_count() != 0:
			errors.append("les traces devraient disparaître après le fondu (%d restantes)" % footprints.mark_count())

	if errors.is_empty():
		print("TEST_VIVANT: PASS (%d multimesh au vent)" % windy)
		quit(0)
	else:
		for e in errors:
			printerr("TEST_VIVANT FAIL: ", e)
		quit(1)
