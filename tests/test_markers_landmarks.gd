extends SceneTree
## Orientation : repères posés par le joueur (cap, limite, suivi), lieux à atteindre et
## chaîne de quêtes d'exploration. Les azimuts cités dans les quêtes sont vérifiés sur le
## relief réel, et le plateau des mesas doit être accessible à pied depuis le départ.

const SIGN := Vector2(35.0, -26.0)

func _ensure(node_name: String, script_path: String) -> Node:
	var node := root.get_node_or_null(node_name)
	if node == null:
		node = (load(script_path) as GDScript).new()
		node.name = node_name
		root.add_child(node)
	return node

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var inventory := _ensure("Inventory", "res://scripts/autoload/inventory.gd")
	_ensure("Sfx", "res://scripts/autoload/sfx.gd")
	await process_frame
	inventory.call("clear_for_test")
	var progression := _ensure("Progression", "res://scripts/autoload/progression.gd")
	var quests := _ensure("QuestManager", "res://scripts/autoload/quest_manager.gd")
	var exploration := _ensure("Exploration", "res://scripts/autoload/exploration_manager.gd")
	await process_frame
	progression.call("clear_for_test")
	quests.call("clear_for_test")
	# Les récompenses relancent l'évaluation : une quête déjà remplie se termine en s'ouvrant.
	quests.call("enable_rewards_for_test")
	quests.call("_unlock_available")
	exploration.call("clear_for_test")
	exploration.set_process(false)
	var landscape := (load("res://scripts/world/landscape_manager.gd") as GDScript).new() as Node3D
	root.add_child(landscape)
	await process_frame

	# --- Cap : 0 = Nord (-Z), sens horaire.
	var cases := [[Vector2(0, -10), 0.0], [Vector2(10, 0), 90.0], [Vector2(0, 10), 180.0], [Vector2(-10, 0), 270.0]]
	for c in cases:
		var got: float = exploration.call("bearing", Vector2.ZERO, c[0])
		if absf(got - float(c[1])) > 0.01:
			errors.append("cap vers %s : %.1f au lieu de %.1f" % [c[0], got, c[1]])

	# --- Repères : limite, suivi du dernier posé, retrait.
	var limit: int = exploration.get("MAX_MARKERS")
	for i in limit:
		if int(exploration.call("add_marker", 10.0 * i, -50.0)) != i:
			errors.append("le repère %d doit se poser" % i)
	if int(exploration.call("add_marker", 0.0, 0.0)) != -1 or bool(exploration.call("can_add_marker")):
		errors.append("pas plus de %d repères" % limit)
	if int(progression.call("get_stat", "stat_markers")) != limit:
		errors.append("chaque repère posé compte pour les quêtes")
	if int(exploration.call("get_tracked_index")) != limit - 1:
		errors.append("le dernier repère posé est suivi")
	var heading: float = exploration.call("tracked_bearing", Vector3(10.0 * (limit - 1), 0.0, 0.0))
	if absf(heading) > 0.01:
		errors.append("le repère plein nord doit être au cap 0 (%.1f)" % heading)
	if absf(float(exploration.call("tracked_distance", Vector3(10.0 * (limit - 1), 0.0, 0.0))) - 50.0) > 0.01:
		errors.append("distance au repère suivi incorrecte")
	if int(exploration.call("marker_near", 21.0, -50.0, 3.0)) != 2 or int(exploration.call("marker_near", 25.0, -50.0, 3.0)) != -1:
		errors.append("sélection du repère le plus proche incorrecte")
	exploration.call("remove_marker", 0)
	if int(exploration.call("get_tracked_index")) != limit - 2 or (exploration.call("get_markers") as Array).size() != limit - 1:
		errors.append("retirer un repère garde le suivi sur le bon repère")
	exploration.call("remove_marker", limit - 2)
	if bool(exploration.call("has_tracked")) or float(exploration.call("tracked_bearing", Vector3.ZERO)) >= 0.0:
		errors.append("retirer le repère suivi arrête le suivi")

	# --- Carte : toucher un point vide propose un repère, toucher un repère le sélectionne.
	var map := (load("res://scripts/ui/map_panel.gd") as GDScript).new() as Control
	root.add_child(map)
	await process_frame
	map.call("touch_world_point", Vector2(120.0, 40.0), 8.0)
	if map.get("_pending_point") != Vector2(120.0, 40.0) or not (map.get("_marker_button") as Button).visible:
		errors.append("toucher la carte doit proposer de poser un repère")
	var before := (exploration.call("get_markers") as Array).size()
	map.call("_on_marker_pressed")
	if (exploration.call("get_markers") as Array).size() != before + 1:
		errors.append("le bouton doit poser le repère")
	map.call("touch_world_point", Vector2(121.0, 41.0), 8.0)
	if int(map.get("_selected_marker")) != before:
		errors.append("toucher un repère doit le sélectionner")
	map.call("_on_marker_pressed")
	if (exploration.call("get_markers") as Array).size() != before:
		errors.append("le bouton doit retirer le repère sélectionné")
	map.free()

	# --- Lieux : rien au départ ; chaque lieu se reconnaît sur le relief.
	var start := Vector3(40.0, 0.0, -30.0)
	if not (exploration.call("check_landmarks", landscape, start) as Array).is_empty():
		errors.append("aucun lieu n'est atteint au départ")
	var lake_x: float = landscape.get("RIVER_X_MIN")
	var spots := {
		"river": Vector3(35.0, 0.0, float(landscape.call("river_center_z", 35.0))),
		"forest": Vector3(-100.0, 0.0, -125.0),
		"mesa": Vector3(130.0, 0.0, 135.0),
		"source": Vector3(lake_x, 0.0, float(landscape.call("river_center_z", lake_x))),
	}
	var landmarks: Dictionary = exploration.get("LANDMARKS")
	for id in spots:
		if not bool(exploration.call("at_landmark", id, landscape, spots[id])):
			errors.append("lieu non reconnu : %s" % id)

	# --- Azimuts et distances annoncés dans les quêtes (depuis le panneau de départ).
	var targets := {"river": Vector2(spots["river"].x, spots["river"].z), "forest": Vector2(-100.0, -125.0),
			"source": Vector2(spots["source"].x, spots["source"].z)}
	# Mesas : le point du plateau le plus proche du départ, et un chemin praticable jusqu'à lui.
	var reach := _reachable(landscape, exploration)
	if reach.is_empty():
		errors.append("le plateau des mesas doit être accessible à pied depuis le départ")
	else:
		targets["mesa"] = reach[0]
	for id in targets:
		var azimuth: float = exploration.call("bearing", SIGN, targets[id])
		var declared := float(landmarks[id]["azimuth"])
		if absf(wrapf(azimuth - declared, -180.0, 180.0)) > 8.0:
			errors.append("azimut annoncé pour %s : %d°, réel %.0f°" % [id, int(declared), azimuth])
		var distance := SIGN.distance_to(targets[id])
		if absf(distance - float(landmarks[id]["distance"])) > 30.0:
			errors.append("distance annoncée pour %s : %d m, réelle %.0f m" % [id, int(landmarks[id]["distance"]), distance])

	# --- Chaîne de quêtes : rivière -> repère -> pinède -> mesas -> source.
	inventory.call("add_item", "item_stone", 3)
	if int(quests.call("state_of", "quest_river")) != 1:
		errors.append("« Cap au sud » doit s'ouvrir après les premières pierres")
	if int(quests.call("state_of", "quest_pinewood")) != 0:
		errors.append("la pinède reste verrouillée avant la rivière")
	var gained: Array = exploration.call("check_landmarks", landscape, spots["river"])
	if gained != ["river"] or not bool(exploration.call("is_landmark_reached", "river")):
		errors.append("atteindre la rivière doit valider le lieu (%s)" % str(gained))
	if not (exploration.call("check_landmarks", landscape, spots["river"]) as Array).is_empty():
		errors.append("un lieu ne se valide qu'une fois")
	if int(quests.call("state_of", "quest_river")) != 2 or int(quests.call("state_of", "quest_marker")) != 2:
		errors.append("rivière atteinte + repère déjà posé : les deux quêtes sont terminées")
	if int(quests.call("state_of", "quest_pinewood")) != 1:
		errors.append("la pinède s'ouvre ensuite")
	for id in ["forest", "mesa", "source"]:
		exploration.call("check_landmarks", landscape, spots[id])
	for quest_id in ["quest_pinewood", "quest_mesa", "quest_source"]:
		if int(quests.call("state_of", quest_id)) != 2:
			errors.append("%s doit être terminée une fois le lieu atteint" % quest_id)

	# --- Textes : chaque quête et chaque lieu a son titre dans les deux langues.
	for lang in ["fr", "en"]:
		var csv := FileAccess.get_file_as_string("res://locales/translations.%s.csv" % lang)
		for key in ["QUEST_RIVER_TITLE", "QUEST_MARKER_DESC", "QUEST_PINEWOOD_DESC", "QUEST_MESA_DESC", "QUEST_SOURCE_DESC",
				"LANDMARK_MESA", "LANDMARK_SOURCE", "TOAST_LANDMARK", "MAP_MARKER_ADD", "MAP_MARKER_REMOVE", "MAP_MARKER_INFO",
				"TOAST_MARKERS_FULL", "SETTING_MINIMAP"]:
			if not csv.contains("\n" + key + ","):
				errors.append("clé de traduction manquante (%s) : %s" % [lang, key])

	landscape.free()
	if errors.is_empty():
		print("TEST_MARKERS_LANDMARKS: PASS")
		quit(0)
	else:
		for e in errors:
			print("TEST_MARKERS_LANDMARKS FAIL: " + e)
		quit(1)

## Parcours en largeur sur une grille de 3 m depuis le départ, en ne franchissant que des pentes
## praticables (< 40°). Retourne [point du plateau le plus proche du panneau] ou [] si aucun.
func _reachable(landscape: Node3D, exploration: Node) -> Array:
	var step := 3.0
	var max_rise := step * tan(deg_to_rad(40.0))
	var half := 78
	var start := Vector2i(int(round(40.0 / step)), int(round(-30.0 / step)))
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var best := Vector2.INF
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var x := cell.x * step
		var z := cell.y * step
		var h: float = landscape.call("terrain_height_at", x, z)
		if bool(exploration.call("at_landmark", "mesa", landscape, Vector3(x, h, z))):
			if best == Vector2.INF or SIGN.distance_to(Vector2(x, z)) < SIGN.distance_to(best):
				best = Vector2(x, z)
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + offset
			if seen.has(next) or absi(next.x) > half or absi(next.y) > half:
				continue
			var nh: float = landscape.call("terrain_height_at", next.x * step, next.y * step)
			if absf(nh - h) > max_rise:
				continue
			seen[next] = true
			queue.append(next)
	return [] if best == Vector2.INF else [best]
