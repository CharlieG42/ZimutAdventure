extends SceneTree
## Bundle atmosphère : nuages sur le ciel (sky_cover), flare solaire, flicker du feu
## de camp, vignette + grain animé dans le HUD.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	# --- Textures d'atmosphère ---
	var clouds: Texture2D = load("res://assets/vfx/sky/cloud_cover.png")
	var vignette: Texture2D = load("res://assets/vfx/overlays/vignette.png")
	var grain: Texture2D = load("res://assets/vfx/overlays/grain.png")
	if clouds == null or clouds.get_size().x < 512:
		errors.append("cloud_cover.png manquante ou trop petite")
	if vignette == null or vignette.get_size().x < 512:
		errors.append("vignette.png manquante ou trop petite")
	if grain == null or grain.get_size().x < 64:
		errors.append("grain.png manquante ou trop petite")
	if vignette != null:
		var img := vignette.get_image()
		var center_a := img.get_pixel(512, 512).a
		var corner_a := img.get_pixel(4, 4).a
		if center_a > 8:
			errors.append("vignette : le centre devrait être transparent (a=%d)" % int(center_a * 255))
		if corner_a < 0.15:
			errors.append("vignette : les coins devraient être assombris (a=%d)" % int(corner_a * 255))

	# --- Scène monde : ciel nuageux + flare solaire ---
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in range(6):
		await process_frame
	var env_node := world.get_node("WorldEnvironment") as WorldEnvironment
	var sky_mat = env_node.environment.sky.sky_material
	if sky_mat is ProceduralSkyMaterial:
		if (sky_mat as ProceduralSkyMaterial).sky_cover == null:
			errors.append("sky_cover (nuages) non branché sur le ProceduralSkyMaterial")
	else:
		errors.append("le ciel n'est plus un ProceduralSkyMaterial : %s" % sky_mat)
	var flare := world.get_node_or_null("SunFlare") as SunFlare
	if flare == null:
		errors.append("nœud SunFlare manquant")
	elif flare.texture == null:
		errors.append("SunFlare sans texture")
	# Logique de visibilité (statique, déterministe).
	if not SunFlare.flare_visible(Vector3.UP, Vector3.UP, true):
		errors.append("flare devrait être visible quand la caméra vise le soleil")
	if SunFlare.flare_visible(Vector3.UP, Vector3.DOWN, true):
		errors.append("flare ne devrait pas être visible dos au soleil")
	if SunFlare.flare_visible(Vector3.UP, Vector3.UP, false):
		errors.append("flare ne devrait pas être visible la nuit (soleil éteint)")
	# Le soleil est bien dans le groupe "sun" (bind_world).
	if get_nodes_in_group("sun").is_empty():
		errors.append("aucun nœud dans le groupe 'sun'")

	# --- HUD : vignette (alpha) + grain animé ---
	var hud := world.get_node("HUD") as CanvasLayer
	var fx := hud.get_node_or_null("FxLayer") as CanvasLayer
	if fx == null:
		errors.append("FxLayer manquant dans le HUD")
	else:
		var vig := fx.get_node_or_null("Vignette") as TextureRect
		var gr := fx.get_node_or_null("Grain") as TextureRect
		if vig == null or vig.texture == null:
			errors.append("Vignette manquante ou sans texture")
		else:
			# Mélange normal (alpha) : le mode MUL de Godot ignore l'alpha et noircit tout l'écran.
			var mat := vig.material as CanvasItemMaterial
			if mat != null and mat.blend_mode != CanvasItemMaterial.BLEND_MODE_MIX:
				errors.append("Vignette : blend MIX attendu (MUL ignore l'alpha et assombrit l'écran, got %d)" % mat.blend_mode)
		if gr == null or gr.texture == null:
			errors.append("Grain manquant ou sans texture")
		else:
			var p0: Vector2 = gr.position
			var moved := false
			for i in range(20):
				await process_frame
				if gr.position != p0:
					moved = true
					break
			if not moved:
				errors.append("le grain devrait être animé (position jamais changée)")

	# --- Feu de camp : flicker de la lumière quand allumé ---
	var fire := (load("res://scenes/interaction/campfire.tscn") as PackedScene).instantiate()
	root.add_child(fire)
	await process_frame
	fire.call("apply_state", {"stage": 4})
	await process_frame
	var light := fire.get_node("FireLight") as OmniLight3D
	var samples: Array[float] = []
	for i in range(45):
		await process_frame
		samples.append(light.light_energy)
	var vmin := samples[0]
	var vmax := samples[0]
	for v in samples:
		vmin = minf(vmin, v); vmax = maxf(vmax, v)
	if vmax - vmin < 0.15:
		errors.append("flicker : énergie lumineuse constante (%f..%f)" % [vmin, vmax])
	var base := 2.2  # fire_light_energy par défaut
	if vmin < base * 0.6 or vmax > base * 1.6:
		errors.append("flicker hors bornes : %f..%f (base ~%f)" % [vmin, vmax, base])
	fire.free()

	if errors.is_empty():
		print("TEST_ATMOSPHERE: PASS")
		quit(0)
	else:
		for e in errors:
			printerr("TEST_ATMOSPHERE FAIL: ", e)
		quit(1)
