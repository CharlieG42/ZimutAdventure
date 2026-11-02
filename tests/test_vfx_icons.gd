extends SceneTree
## VFX texturés (Kenney CC0) et icônes d'items : textures présentes, particules du feu
## de camp pilotées par le stage, icônes PNG chargeables et branchées dans le HUD.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	# --- Textures de particules ---
	for t in ["flame_02", "smoke_03", "spark_01", "circle_02", "flare_01"]:
		if VfxParticles.tex(t) == null:
			errors.append("texture particule manquante : %s" % t)

	# --- Fabriques de particules ---
	var host := Node3D.new()
	root.add_child(host)
	var fire := VfxParticles.campfire(host, Vector3.ZERO)
	if fire == null or not (fire is GPUParticles3D):
		errors.append("campfire() doit renvoyer un GPUParticles3D")
	var gpu_count := 0
	for c in host.get_children():
		if c is GPUParticles3D:
			gpu_count += 1
	if gpu_count != 3:
		errors.append("feu de camp : 3 émetteurs attendus (flammes/fumée/braises), got %d" % gpu_count)
	var puff := VfxParticles.dust_puff(host, Vector3.ZERO, Color(0.7, 0.6, 0.45))
	if puff == null or not puff.one_shot or not puff.emitting:
		errors.append("dust_puff doit être one-shot et émis immédiatement")
	var shards := VfxParticles.rock_shards(host, Vector3.ZERO, Color(0.5, 0.5, 0.5))
	if shards == null or shards.amount < 6:
		errors.append("rock_shards : au moins 6 éclats")
	host.free()

	# --- Feu de camp de la scène : VFX pilotés par le stage ---
	var fire_scene := (load("res://scenes/interaction/campfire.tscn") as PackedScene).instantiate()
	root.add_child(fire_scene)
	await process_frame
	var fire_gpu := 0
	var all_off := true
	for c in fire_scene.get_children():
		if c is GPUParticles3D:
			fire_gpu += 1
			if (c as GPUParticles3D).emitting:
				all_off = false
	if fire_gpu < 3:
		errors.append("campfire.tscn : %d émetteurs VFX (<3)" % fire_gpu)
	if not all_off:
		errors.append("feu éteint (stage 0) : les particules devraient être inactives")
	fire_scene.call("apply_state", {"stage": 4})
	await process_frame
	var any_on := false
	for c in fire_scene.get_children():
		if c is GPUParticles3D and (c as GPUParticles3D).emitting:
			any_on = true
	if not any_on:
		errors.append("feu alimenté (stage 4) : les particules devraient émettre")
	fire_scene.free()

	# --- Icônes d'items : toutes les ids connues ont une PNG ---
	var expected := ["item_berries", "item_stone", "item_wood", "item_wheat", "item_egg", "item_boiled_egg",
		"item_fish", "item_fish_big", "item_grilled_fish", "item_grilled_fish_big", "item_seeds", "item_grain_seeds",
		"item_raw_meat", "item_cooked_meat", "item_bread", "item_soup", "item_milk", "item_pelt", "item_relic",
		"item_vegetables", "item_roast_vegetables", "item_wool",
		"tool_stone_axe", "tool_sickle", "tool_hoe", "tool_watering_can", "tool_hunting_bow", "tool_fishing_rod"]
	for id in expected:
		var t: Texture2D = load("res://assets/ui/icons/items/%s.png" % id)
		if t == null:
			errors.append("icône manquante : %s" % id)
		elif t.get_size().x < 128:
			errors.append("icône trop petite : %s (%s)" % [id, str(t.get_size())])

	# --- Intégration HUD : hotbar avec icônes PNG, sac du journal avec icônes ---
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in range(6):
		await process_frame
	var hud := world.get_node("HUD")
	var inventory := root.get_node("Inventory")
	inventory.call("clear_for_test")
	inventory.call("add_item", "tool_stone_axe", 1)
	inventory.call("add_item", "tool_hunting_bow", 1)
	inventory.call("add_item", "item_berries", 3)
	inventory.call("add_item", "item_wood", 2)
	var hotbar: Control = hud.get_node("Overlay/Hotbar")
	hotbar.call("refresh")
	await process_frame
	var icon_count := 0
	for slot in hotbar.get_children():
		for c in slot.get_children():
			if c is ItemIcon and (c as ItemIcon).texture != null:
				icon_count += 1
	if icon_count < 2:
		errors.append("hotbar : %d slots avec icône PNG (<2)" % icon_count)

	# Journal ouvert : lignes du sac avec icône.
	var journal: Control = hud.get_node("InventoryCenter/JournalPanel")
	journal.call("toggle")
	await process_frame
	var panel := journal.get_node_or_null("Panel") as Control
	if panel == null:
		panel = journal
	var found := [0]
	_walk_count(panel, found)
	if found[0] < 2:
		errors.append("journal/sac : %d icônes ItemIcon trouvées (<2)" % found[0])
	journal.call("toggle")

	if errors.is_empty():
		print("TEST_VFX_ICONS: PASS (%d icônes hotbar, %d dans le sac)" % [icon_count, found[0]])
		quit(0)
	else:
		for e in errors:
			printerr("TEST_VFX_ICONS FAIL: ", e)
		quit(1)

func _walk_count(node: Node, counter: Array) -> void:
	if node is ItemIcon and (node as ItemIcon).texture != null:
		counter[0] += 1
	for c in node.get_children():
		_walk_count(c, counter)
