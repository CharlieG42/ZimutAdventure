extends SceneTree
## Zones du monde (plaine, pinède, mesas, berges) et rivière : tracé continu, jamais perchée,
## décor réparti par zone et hors de l'eau, point d'eau le long des berges, annonce des zones.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var landscape := (load("res://scripts/world/landscape_manager.gd") as GDScript).new() as Node3D
	root.add_child(landscape)
	await process_frame

	# --- Rivière : sous l'eau tout du long, en pente douce, et les abords ne sont pas plus bas.
	var x_min: float = landscape.get("RIVER_X_MIN")
	var x_max: float = landscape.get("RIVER_X_MAX")
	var bank: float = landscape.get("RIVER_BANK")
	var last_level := INF
	var x := x_min
	while x <= x_max:
		var z: float = landscape.call("river_center_z", x)
		var level: float = landscape.call("water_level_at", x)
		if not bool(landscape.call("is_water", x, z)):
			errors.append("le milieu du lit doit être de l'eau (x=%.0f)" % x)
		var bed: float = landscape.call("terrain_height_at", x, z)
		if bed > level - 0.3:
			errors.append("le lit doit être sous l'eau (x=%.0f, lit=%.2f, eau=%.2f)" % [x, bed, level])
		if level - bed > 1.6:
			errors.append("la rivière doit rester un gué (x=%.0f, profondeur=%.2f)" % [x, level - bed])
		if level > last_level + 0.001:
			errors.append("l'eau ne remonte pas le courant (x=%.0f)" % x)
		last_level = level
		for side in [-1.0, 1.0]:
			var shore: float = landscape.call("terrain_height_at", x, z + side * (bank + 12.0))
			if shore < level:
				errors.append("rivière perchée : sol à %.2f sous l'eau à %.2f (x=%.0f)" % [shore, level, x])
		x += 10.0

	# --- Zones : le départ est une plaine sèche ; chaque zone existe ; les poids somment à 1.
	var start: Vector2 = landscape.get("START_POINT")
	if String(landscape.call("zone_at", start.x, start.y)) != "desert":
		errors.append("le départ doit être dans la plaine")
	if bool(landscape.call("is_water", start.x, start.y, 20.0)):
		errors.append("le départ doit être au sec")
	var seen := {}
	for gx in range(-220, 221, 20):
		for gz in range(-220, 221, 20):
			var weights: Array = landscape.call("zone_weights", float(gx), float(gz))
			var total := 0.0
			for w in weights:
				total += float(w)
				if float(w) < -0.001:
					errors.append("poids de zone négatif en (%d, %d)" % [gx, gz])
			if absf(total - 1.0) > 0.01:
				errors.append("les poids de zone doivent sommer à 1 en (%d, %d) : %.2f" % [gx, gz, total])
			seen[String(landscape.call("zone_at", float(gx), float(gz)))] = true
	for zone in ["desert", "forest", "badlands", "river"]:
		if not seen.has(zone):
			errors.append("zone absente de la carte : %s" % zone)
		if String(landscape.call("zone_name_key", zone)).is_empty():
			errors.append("zone sans nom : %s" % zone)
	# Les mesas forment un vrai relief, la pinède des collines.
	if float(landscape.call("terrain_height_at", 130.0, 135.0)) < 8.0:
		errors.append("le plateau des mesas doit dominer la plaine")

	# --- Décor : rien dans l'eau, les pins en pinède, pas de cactus sous les pins.
	for t in landscape.get("prop_placements"):
		var origin: Vector3 = (t as Transform3D).origin
		if bool(landscape.call("is_water", origin.x, origin.z)):
			errors.append("élément de décor dans l'eau en %s" % origin)
			break
	var in_forest := 0
	for i in 200:
		var p: Vector3 = landscape.call("_random_ground_position", false, "pine")
		if float((landscape.call("zone_weights", p.x, p.z) as Array)[1]) > 0.5:
			in_forest += 1
	if in_forest < 120:
		errors.append("les pins doivent pousser surtout en pinède (%d/200)" % in_forest)
	for i in 100:
		var p: Vector3 = landscape.call("_random_ground_position", false, "cactus")
		if float((landscape.call("zone_weights", p.x, p.z) as Array)[1]) > 0.95:
			errors.append("pas de cactus au cœur de la pinède")
			break

	# --- Surface de l'eau et point d'eau.
	var surface := landscape.get_node_or_null("River/Surface") as MeshInstance3D
	if surface == null or surface.mesh == null or surface.mesh.get_surface_count() != 1:
		errors.append("la surface de la rivière manque")
	var water := landscape.get_node_or_null("River/RiverWater")
	if water == null or not water.is_in_group("water"):
		errors.append("le point d'eau de la rivière manque")
	else:
		var mid_z: float = landscape.call("river_center_z", 0.0)
		var level: float = landscape.call("water_level_at", 0.0)
		var script := water.get_script() as GDScript
		if not bool(script.call("is_reachable", landscape, Vector3(0.0, level, mid_z))):
			errors.append("on doit pouvoir boire dans la rivière")
		if not bool(script.call("is_reachable", landscape, Vector3(0.0, level + 0.5, mid_z + 6.0))):
			errors.append("on doit pouvoir boire depuis la berge")
		if bool(script.call("is_reachable", landscape, Vector3(start.x, 0.0, start.y))):
			errors.append("pas d'eau à boire au camp de départ")

	# --- Annonce des zones : silencieuse au départ, puis après deux relevés identiques.
	var announcer := (load("res://scripts/world/zone_announcer.gd") as GDScript).new() as Node
	root.add_child(announcer)
	announcer.set_process(false)
	announcer.call("observe", "desert", landscape)
	if bool(announcer.call("observe", "desert", landscape)):
		errors.append("la zone de départ ne s'annonce pas")
	if bool(announcer.call("observe", "forest", landscape)):
		errors.append("un seul relevé ne suffit pas à annoncer une zone")
	if not bool(announcer.call("observe", "forest", landscape)) or String(announcer.get("current_zone")) != "forest":
		errors.append("deux relevés identiques annoncent la nouvelle zone")

	announcer.free()
	landscape.free()
	if errors.is_empty():
		print("TEST_ZONES_RIVER: PASS")
		quit(0)
	else:
		for e in errors:
			print("TEST_ZONES_RIVER FAIL: " + e)
		quit(1)
