extends SceneTree

## Mouvement du joueur : sol solide (régression du sens des triangles), accélération
## progressive, vitesse proportionnelle au stick, sprint plein régime, endurance,
## saut, boussole, forme du stick, collisions des accessoires.

func _init() -> void:
	await process_frame
	var PlayerScript: GDScript = load("res://scripts/player/player.gd")
	var errors: Array[String] = []

	# --- Forme du stick (fonction statique) ---
	if PlayerScript.shape_stick(Vector2(0.05, 0.0), 0.12, 1.5) != Vector2.ZERO:
		errors.append("stick dans la zone morte doit donner zéro")
	var half: float = PlayerScript.shape_stick(Vector2(0.56, 0.0), 0.12, 1.5).length()
	if half <= 0.0 or half >= 0.56:
		errors.append("courbe du stick : demi-course doit donner moins de 0.56 (got %f)" % half)
	if absf(PlayerScript.shape_stick(Vector2(1.0, 0.0), 0.12, 1.5).length() - 1.0) > 0.001:
		errors.append("plein stick doit donner 1.0")

	# --- Boussole ---
	if CompassStrip.cardinal_key(0.0) != "HUD_DIR_N" or CompassStrip.cardinal_key(90.0) != "HUD_DIR_E" \
			or CompassStrip.cardinal_key(359.0) != "HUD_DIR_N":
		errors.append("points cardinaux incorrects")

	# --- Monde + joueur ---
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var player := world.get_node("Player") as CharacterBody3D
	var landscape := world.get_node("Landscape")

	# Le sol doit être solide vu d'en haut.
	for i in 120:
		await physics_frame
	var ground: float = landscape.terrain_height_at(player.global_position.x, player.global_position.z)
	if not player.is_on_floor():
		errors.append("le joueur devrait se tenir sur le sol")
	if player.global_position.y < ground - 0.5:
		errors.append("le joueur est passé sous le terrain (y=%f, sol=%f)" % [player.global_position.y, ground])

	# Accélération progressive, puis course plein stick (vitesse maximale mesurée
	# sur la phase : un accessoire du décor peut stopper le joueur en fin de course).
	var start: Vector3 = player.global_position
	player.set_joystick_vector(Vector2(0, -1))
	for i in 3:
		await physics_frame
	var early: float = Vector2(player.velocity.x, player.velocity.z).length()
	if early >= player.walk_speed:
		errors.append("l'accélération doit être progressive (v=%f)" % early)
	var fast := 0.0
	for i in 40:
		await physics_frame
		fast = maxf(fast, Vector2(player.velocity.x, player.velocity.z).length())
	if fast < player.walk_speed * 1.2:
		errors.append("plein stick doit déclencher la course (v=%f)" % fast)
	if player.get_stamina() >= 1.0:
		errors.append("la course doit consommer de l'endurance")

	# Demi-stick = marche plus lente.
	player.set_joystick_vector(Vector2.ZERO)
	for i in 40:
		await physics_frame
	player.set_joystick_vector(Vector2(0, -0.5))
	var slow := 0.0
	for i in 40:
		await physics_frame
		slow = maxf(slow, Vector2(player.velocity.x, player.velocity.z).length())
	if slow >= fast * 0.8 or slow < 0.5:
		errors.append("demi-stick doit marcher plus lentement (v=%f vs %f)" % [slow, fast])
	if start.distance_to(player.global_position) < 1.0:
		errors.append("le joueur n'a pas avancé")

	# Arrêt.
	player.set_joystick_vector(Vector2.ZERO)
	for i in 60:
		await physics_frame
	if Vector2(player.velocity.x, player.velocity.z).length() > 0.3:
		errors.append("le joueur doit s'arrêter stick relâché")

	# Saut.
	for i in 30:
		await physics_frame
	var y0: float = player.global_position.y
	player.request_jump()
	var peak: float = y0
	for i in 40:
		await physics_frame
		peak = maxf(peak, player.global_position.y)
	if peak < y0 + 0.5:
		errors.append("le saut doit décoller (%f -> %f)" % [y0, peak])

	# Collision des accessoires.
	if world.get_node("Landscape").get_node_or_null("PropCollision") == null:
		errors.append("PropCollision manquant")

	if errors.is_empty():
		print("TEST_PLAYER_MOVEMENT: PASS")
		quit(0)
	else:
		for e in errors:
			printerr("TEST_PLAYER_MOVEMENT FAIL: ", e)
		quit(1)
