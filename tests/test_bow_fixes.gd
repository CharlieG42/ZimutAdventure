extends SceneTree
## Correctifs de retour utilisateur : visée à l'arc (viseur sans déplacer le personnage,
## bouton Tirer/Viser), gibier réellement tuable (mêlée + détection de proximité de la
## flèche), caméra plus réactive.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var inventory := root.get_node("Inventory")
	inventory.call("clear_for_test")

	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var player := world.get_node("Player") as CharacterBody3D
	inventory.call("add_item", "tool_hunting_bow", 1)
	inventory.call("equip", "tool_hunting_bow")
	inventory.call("add_item", "arrow", 10)
	var camera := player.get_node("CameraPivot/Camera3D") as Camera3D
	var pivot := player.get_node("CameraPivot") as Node3D

	# --- A. En visée, le viseur (pivot caméra) bouge SANS tourner le personnage ---
	player.call("set_aim_override", true)
	for i in 5:
		await physics_frame
	if not bool(player.call("is_aiming")):
		errors.append("set_aim_override(true) devrait activer la visée avec l'arc équipé")
	var yaw_before: float = player.rotation.y
	player.call("_rotate_look", Vector2(0.8, 0.0))
	await create_timer(0.1).timeout
	await process_frame
	if absf(player.rotation.y - yaw_before) > 0.001:
		errors.append("en visée, le personnage ne doit pas tourner (yaw %f -> %f)" % [yaw_before, player.rotation.y])
	if absf(pivot.rotation.y) < 0.1:
		errors.append("en visée, le pivot caméra doit tourner (viseur), yaw=%f" % pivot.rotation.y)
	# En visée, la boussole suit le viseur.
	var expected_heading := fposmod(-rad_to_deg(player.rotation.y + pivot.rotation.y), 360.0)
	if absf(wrapf(float(player.call("get_heading_degrees")) - expected_heading, -180.0, 180.0)) > 1.0:
		errors.append("en visée, la boussole indique le cap du viseur")
	# Fin de visée : le personnage prend le cap visé, la caméra ne revient pas en arrière.
	var aimed_yaw: float = player.rotation.y + pivot.rotation.y
	player.call("set_aim_override", false)
	await create_timer(0.2).timeout
	if absf(wrapf(player.rotation.y - aimed_yaw, -PI, PI)) > 0.05 or absf(pivot.rotation.y) > 0.01:
		errors.append("fin de visée : le personnage se tourne vers l'endroit visé (yaw %f, visé %f, pivot %f)" % [player.rotation.y, aimed_yaw, pivot.rotation.y])
	yaw_before = player.rotation.y
	player.call("_rotate_look", Vector2(0.8, 0.0))
	if absf(player.rotation.y - yaw_before) < 0.1:
		errors.append("hors visée, la souris doit tourner le personnage")
	await create_timer(0.6).timeout
	if absf(pivot.rotation.y) > 0.05:
		errors.append("hors visée, le pivot caméra doit revenir à 0 (yaw=%f)" % pivot.rotation.y)

	# --- A. En visée, le déplacement est bloqué (le personnage reste en place) ---
	player.call("set_aim_override", true)
	for i in 5:
		await physics_frame
	player.call("set_joystick_vector", Vector2(1.0, 0.0))
	for i in 20:
		await physics_frame
	var speed_aim := Vector2(player.velocity.x, player.velocity.z).length()
	if speed_aim > 0.5:
		errors.append("en visée le personnage ne doit pas avancer (vitesse %f)" % speed_aim)
	player.call("set_joystick_vector", Vector2.ZERO)
	player.call("set_aim_override", false)
	for i in 5:
		await physics_frame

	# --- A. Bouton Tirer : appui bref = flèche avec charge minimale ---
	var arrows_before: int = int(inventory.call("count_of", "arrow"))
	player.call("begin_attack")
	player.call("end_attack")  # relâché immédiatement
	await process_frame
	if int(inventory.call("count_of", "arrow")) != arrows_before - 1:
		errors.append("un appui bref sur Tirer doit consommer une flèche")
	var arrows: Array = get_nodes_in_group("arrow_stuck")
	var last_arrow: RigidBody3D = null
	for node in world.get_children():
		if node is RigidBody3D and node.get("linear_velocity") != null:
			last_arrow = node
	if last_arrow == null:
		errors.append("aucune flèche trouvée après le tir")
	else:
		var min_speed: float = lerpf(26.0, 38.0, 0.25)
		if last_arrow.linear_velocity.length() < min_speed - 0.5:
			errors.append("tir bref : vitesse trop faible (%f < %f)" % [last_arrow.linear_velocity.length(), min_speed])

	# --- B. Mêlée sur un animal passif : il meurt et lâche de la viande ---
	var prey: CharacterBody3D = null
	for animal in world.get_node("Animals").get_children():
		prey = animal
		break
	if prey == null:
		errors.append("aucun animal dans Animals")
	else:
		var fwd := -camera.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		prey.global_position = player.global_position + fwd * 2.0 + Vector3(0.0, 0.3, 0.0)
		prey.set("_dead", false)
		inventory.call("equip", "tool_stone_axe")
		player.set("_melee_cooldown", 0.0)
		var meat_before: int = int(inventory.call("count_of", "item_raw_meat"))
		var ok: bool = bool(player.call("try_melee"))
		if not ok or prey.get("_dead") != true:
			errors.append("la hache doit tuer le gibier (ok=%s dead=%s)" % [str(ok), str(prey.get("_dead"))])
		var corpse := prey.get_node_or_null("Carcass")
		if corpse != null:
			corpse.call("harvest")
		if int(inventory.call("count_of", "item_raw_meat")) <= meat_before:
			errors.append("le gibier tué à la hache doit lâcher de la viande")

		# --- B. Tir réel centré sur le gibier à 10 m : la flèche touche ---
		inventory.call("equip", "tool_hunting_bow")
		prey.call("_respawn")  # remet couche + groupe huntable après le test de mêlée
		await physics_frame
		prey.global_position = player.global_position + fwd * 10.0 + Vector3(0.0, 0.3, 0.0)
		player.set("_pitch", 0.0)
		player.set("_pitch_smooth", 0.0)
		player.rotation.y = atan2(-fwd.x, -fwd.z)
		player.set("_pivot_yaw", 0.0)
		for i in 10:
			await physics_frame
		player.call("shoot_arrow", 1.0)
		var hit: bool = false
		for i in 180:
			await physics_frame
			if prey.get("_dead") == true:
				hit = true
				break
		if not hit:
			errors.append("tir centré à 10 m sur le gibier : la flèche doit toucher")
		# --- B. Proximité : une flèche passant à 0.8 m du point visé tue quand même ---
		prey.call("_respawn")
		await physics_frame
		var near := (load("res://scenes/interaction/arrow.tscn") as PackedScene).instantiate() as RigidBody3D
		world.add_child(near)
		var aim_point: Vector3 = prey.call("get_aim_point") if prey.has_method("get_aim_point") else prey.global_position + Vector3(0.0, 0.6, 0.0)
		near.global_position = aim_point + Vector3(0.8, 0.2, 0.0)
		near.linear_velocity = Vector3(0.0, -5.0, 0.0)
		for i in 6:
			await physics_frame
		if prey.get("_dead") != true:
			errors.append("proximité : une flèche à 0.8 m du point visé doit tuer")

	# --- C. Caméra : réglages réactifs ---
	if float(player.get("look_smoothing")) < 25.0:
		errors.append("look_smoothing trop faible (%f)" % float(player.get("look_smoothing")))
	if float(player.get("camera_joystick_speed")) < 4.0:
		errors.append("camera_joystick_speed trop faible (%f)" % float(player.get("camera_joystick_speed")))
	# la caméra suit vite : après un grand delta de pitch, l'écart se réduit vite
	player.set("_pitch", 0.5)
	player.set("_pitch_smooth", -0.5)
	await create_timer(0.6).timeout
	if absf(float(player.get("_pitch_smooth")) - 0.5) > 0.05:
		errors.append("le pitch lissé doit rattraper vite (reste %f)" % absf(float(player.get("_pitch_smooth")) - 0.5))

	# --- HUD : boutons Viser / Tirer ---
	var hud: Node = get_first_node_in_group("hud")
	var aim_button: Button = hud.get_node("Overlay/ActionPad/AimButton")
	if aim_button == null:
		errors.append("AimButton manquant dans le HUD")
	else:
		aim_button.button_pressed = true
		await create_timer(0.2).timeout
		for i in 5:
			await physics_frame
		if not bool(player.call("is_aiming")):
			errors.append("le bouton Viser doit activer la visée (set_aim_override)")
		# Ranger l'arc relâche le bouton « Viser » (et la visée).
		aim_button.button_pressed = true
		inventory.call("unequip")
		hud.call("_refresh_attack_button")
		if aim_button.button_pressed or bool(player.get("_aim_override")):
			errors.append("ranger l'arc doit relâcher le bouton Viser")
		inventory.call("equip", "tool_hunting_bow")
		await create_timer(0.1).timeout

	if errors.is_empty():
		print("TEST_BOW_FIXES: PASS")
		quit(0)
	else:
		for e in errors:
			printerr("TEST_BOW_FIXES FAIL: ", e)
		quit(1)
