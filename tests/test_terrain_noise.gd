extends SceneTree
## Terrain allégé : le shader lit ses bruits dans une texture précalculée (plus de sinus par
## pixel), la texture est raccordable, importée sans perte avec mipmaps et branchée sur le
## matériau du terrain.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var code := FileAccess.get_file_as_string("res://assets/landscapes/shaders/canyon_terrain.gdshader")
	if code.contains("sin(dot(") or code.contains("float hash("):
		errors.append("le shader du terrain ne doit plus calculer de hachage à base de sinus")
	if not code.contains("uniform sampler2D noise_tex"):
		errors.append("le shader lit ses bruits dans noise_tex")
	var material := load("res://assets/landscapes/materials/canyon_terrain.tres") as ShaderMaterial
	var texture := material.get_shader_parameter("noise_tex") as Texture2D
	if texture == null:
		errors.append("la texture de bruit est branchée sur le matériau")
	else:
		var image := texture.get_image()
		if image.get_width() != 256 or image.get_height() != 256:
			errors.append("texture de bruit 256 x 256")
		if not image.has_mipmaps():
			errors.append("la texture de bruit a des mipmaps (pas de scintillement au loin)")
		if image.is_compressed():
			errors.append("la texture de bruit est importée sans perte (quatre bruits indépendants)")
		else:
			# Raccord : l'écart entre les deux bords vaut l'écart entre deux voisins.
			var seam := 0.0
			var inner := 0.0
			for y in range(0, 256, 4):
				seam += absf(image.get_pixel(0, y).r - image.get_pixel(255, y).r)
				inner += absf(image.get_pixel(1, y).r - image.get_pixel(0, y).r)
			if seam > inner * 2.0 + 0.5:
				errors.append("la texture de bruit doit se raccorder (bord %.2f, voisins %.2f)" % [seam, inner])
	var settings := FileAccess.get_file_as_string("res://assets/landscapes/textures/terrain_noise.png.import")
	for line in ["compress/mode=0", "mipmaps/generate=true", "process/fix_alpha_border=false", "detect_3d/compress_to=0"]:
		if not settings.contains(line):
			errors.append("réglage d'import attendu : %s" % line)
	if errors.is_empty():
		print("TEST_TERRAIN_NOISE: PASS")
		quit(0)
	else:
		for e in errors:
			print("TEST_TERRAIN_NOISE FAIL: " + e)
		quit(1)
