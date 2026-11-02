extends SceneTree
## Visée à l'arc (FOV réduit, tir tendu plus rapide, arc visible en main) et clic
## sur la mini-carte (souris capturée en jeu) qui ouvre la carte plein écran.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var player: CharacterBody3D = world.get_node("Player")
	var hud := world.get_node("HUD")
	var inventory := root.get_node("Inventory")
	inventory.call("clear_for_test")
	inventory.call("add_item", "tool_hunting_bow", 1)
	inventory.call("add_item", "arrow", 4)
	if not inventory.call("equip", "tool_hunting_bow"):
		errors.append("équipement de l'arc impossible")

	# Outil tenu en main : l'arc équipé est visible dans la main droite.
	for i in 5:
		await physics_frame
	var bow_node := player.visuals.get_node_or_null("Torso/ArmR/HeldBow") as Node3D
	var axe_node := player.visuals.get_node_or_null("Torso/ArmR/HeldAxe") as Node3D
	if bow_node == null or not bow_node.visible:
		errors.append("l'arc équipé devrait être visible en main")
	if axe_node != null and axe_node.visible:
		errors.append("la hache ne devrait pas être visible quand l'arc est équipé")

	# Visée maintenue (clic droit) : flag + FOV réduit.
	Input.action_press("aim")
	for i in 30:
		await physics_frame
	if not bool(player.get("_aiming")):
		errors.append("visée non active avec le bouton droit maintenu")
	if player.camera.fov > 60.0:
		errors.append("FOV de visée non réduit (fov=%f)" % player.camera.fov)

	# Tir en visée : flèche consommée, vitesse = aim_arrow_speed.
	var before: int = inventory.call("count_of", "arrow")
	player.call("try_shoot_arrow")
	if inventory.call("count_of", "arrow") != before - 1:
		errors.append("le tir devrait consommer une flèche")
	var arrow := _last_arrow(world)
	if arrow == null:
		errors.append("aucune flèche tirée")
	else:
		var speed: float = (arrow as RigidBody3D).linear_velocity.length()
		if absf(speed - 30.0) > 0.6:
			errors.append("tir visé devrait être à 30 m/s (got %f)" % speed)

	# Hors visée : vitesse de base.
	Input.action_release("aim")
	for i in 30:
		await physics_frame
	if bool(player.get("_aiming")):
		errors.append("la visée devrait se couper au relâchement")
	player.call("try_shoot_arrow")
	arrow = _last_arrow(world)
	if arrow != null:
		var speed: float = (arrow as RigidBody3D).linear_velocity.length()
		if absf(speed - 26.0) > 2.5:  # dispersion légère acceptée
			errors.append("tir non visé devrait être ~26 m/s (got %f)" % speed)

	# Clic sur la mini-carte (souris capturée) : la carte plein écran s'ouvre.
	var minimap: Control = hud.get_node("Overlay/MiniMap")
	var map_panel: Control = hud.get_node("MapPanel")
	var center := minimap.get_global_rect().get_center()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = center
	ev.global_position = center
	hud._unhandled_input(ev)
	if not map_panel.visible:
		errors.append("clic sur la mini-carte : la carte ne s'ouvre pas")
	hud._on_map_pressed()
	if map_panel.visible:
		errors.append("la carte devrait se fermer au second appui")

	# Cactus générés : 5 variantes chargées, saguaros de plus d'1 m.
	var cacti: Array = GlbPropLibrary.get_variant_meshes("cactus")
	if cacti.size() != 5:
		errors.append("cactus : %d/5 variantes" % cacti.size())
	var tall := 0
	for m in cacti:
		if (m as Mesh).get_aabb().size.y > 1.5:
			tall += 1
	if tall < 2:
		errors.append("au moins 2 saguaros > 1,5 m attendus (%d)" % tall)

	if errors.is_empty():
		print("TEST_AIM_MINIMAP: PASS")
		quit(0)
	else:
		for e in errors:
			printerr("TEST_AIM_MINIMAP FAIL: ", e)
		quit(1)

func _last_arrow(world: Node) -> Node:
	var found: Node = null
	for c in world.get_children():
		# Duck-typing (évite de charger la classe Arrow à la compilation du test).
		if c is RigidBody3D and c.has_method("pickup"):
			found = c
	return found
