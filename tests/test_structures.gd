extends SceneTree
## Constructions posables : placement sur le terrain, refus sur les pentes, repos et
## sommeil (la nuit seulement), repères de carte.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	var clock := root.get_node_or_null("DayNightCycle")
	if clock == null:
		clock = (load("res://scripts/autoload/day_night_cycle.gd") as GDScript).new()
		clock.name = "DayNightCycle"
		root.add_child(clock)
	clock.set("enabled", false)

	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 5:
		await process_frame
	var spawner := world.get_node("Structures")
	var landscape := world.get_node("Landscape")
	var player := world.get_node("Player") as CharacterBody3D

	if not spawner.call("is_placeable", "furniture_camp_bed") or spawner.call("is_placeable", "item_wood"):
		errors.append("seuls le lit et l'abri sont posables")

	# Terrain correct : on retrouve la construction au sol, dans le groupe « structures ».
	var spot := Vector3(player.global_position.x + 6.0, 0.0, player.global_position.z)
	var result: String = spawner.call("place", "furniture_camp_bed", spot, 0.0)
	if result != "":
		errors.append("le lit devrait se poser sur ce terrain plat : %s" % result)
	await process_frame
	var beds := get_nodes_in_group("structures")
	if beds.size() != 1:
		errors.append("une construction attendue, %d trouvée(s)" % beds.size())
	else:
		var bed := beds[0] as Node3D
		var ground: float = landscape.terrain_height_at(bed.global_position.x, bed.global_position.z)
		if absf(bed.global_position.y - ground) > 0.01:
			errors.append("le lit doit reposer sur le sol")
		if bed.find_children("*", "StaticBody3D", false, false).is_empty():
			errors.append("le lit doit avoir une collision pleine")
		if (bed as Interactable).get_prompt() != "ACTION_REST_BED":
			errors.append("invite du lit incorrecte")
		# Repos : l'endurance est rétablie.
		player.set("stamina", 0.2)
		(bed as Interactable).interact(player)
		if float(player.get("stamina")) < 0.99:
			errors.append("le lit doit rétablir l'endurance")

	# Falaise : refus d'une pose sur une pente trop forte.
	var steep := ""
	for x in range(180, 250, 5):
		steep = spawner.call("place", "furniture_camp_bed", Vector3(x, 0, 0), 0.0)
		if steep == "TOAST_TOO_STEEP":
			break
	if steep != "TOAST_TOO_STEEP":
		errors.append("la pose doit être refusée sur les falaises du bord (dernier résultat : %s)" % steep)

	# Abri : on ne dort que la nuit, et on se réveille à 7 h.
	var shelter_result: String = spawner.call("place", "building_shelter", spot + Vector3(0, 0, 8), 0.0)
	if shelter_result != "":
		errors.append("l'abri devrait se poser : %s" % shelter_result)
	var shelter: Node3D = null
	for node in get_nodes_in_group("structures"):
		if (node as Interactable).get_prompt() == "ACTION_SLEEP":
			shelter = node
	if shelter == null:
		errors.append("abri introuvable")
	else:
		clock.call("set_hour", 14.0)
		(shelter as Interactable).interact(player)
		if absf(float(clock.get("hour")) - 14.0) > 0.01:
			errors.append("on ne dort pas en plein jour")
		clock.call("set_hour", 23.0)
		(shelter as Interactable).interact(player)
		if absf(float(clock.get("hour")) - 7.0) > 0.01:
			errors.append("dormir la nuit doit ramener à 7 h (heure : %f)" % float(clock.get("hour")))

	# Repères de carte : feu de camp et campements dans les groupes dessinés.
	if get_nodes_in_group("campfire").is_empty():
		errors.append("le feu de camp doit être dans le groupe « campfire »")

	world.free()
	if errors.is_empty():
		print("TEST_STRUCTURES: PASS")
		quit(0)
	else:
		for e in errors:
			printerr("TEST_STRUCTURES FAIL: ", e)
		quit(1)
