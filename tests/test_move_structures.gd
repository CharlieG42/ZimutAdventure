extends SceneTree
## Déplacer une construction : fantôme sans collision, validité (eau, pente, voisins),
## rotation, pose, annulation, enclos non déplaçable.

var _errors: Array[String] = []

func _check(ok: bool, message: String) -> void:
	if not ok:
		_errors.append(message)

func _init() -> void:
	await process_frame
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
	spawner.call("disable_saving_for_test")
	var player := world.get_node("Player") as CharacterBody3D
	var base := Vector3(player.global_position.x + 8.0, 0.0, player.global_position.z)

	_check(spawner.call("place", "building_shelter", base, 0.0) == "", "abri posé")
	_check(spawner.call("place", "building_pen", base + Vector3(0, 0, 20), 0.0) == "", "enclos posé")
	await process_frame
	var shelter: Node3D = null
	var pen: Node3D = null
	for node in get_nodes_in_group("structures"):
		if node.get("kind") == "shelter":
			shelter = node as Node3D
	for child in spawner.get_children():
		if child is Pen:
			pen = child
	_check(shelter != null, "abri trouvé")
	_check(spawner.call("movable_for", shelter) == shelter, "l'abri est déplaçable")
	var interact_area := shelter as Area3D
	_check(spawner.call("movable_for", interact_area) == shelter, "la cible d'interaction mène à l'abri")
	_check(pen != null and spawner.call("movable_for", pen) == null, "l'enclos n'est pas déplaçable")

	# Soulever : les collisions sont neutralisées, la couche d'interaction aussi.
	var solid := shelter.find_children("*", "StaticBody3D", false, false)[0] as StaticBody3D
	_check(solid.collision_layer == 1, "collision pleine au départ")
	_check(bool(spawner.call("begin_move", shelter)), "début du déplacement")
	_check(spawner.call("is_moving"), "déplacement actif")
	_check(solid.collision_layer == 0 and interact_area.collision_layer == 0, "fantôme sans collision")
	_check(spawner.call("movable_for", shelter) == null, "rien d'autre ne se déplace pendant ce temps")
	var overlays := 0
	for mesh in shelter.find_children("*", "MeshInstance3D", true, false):
		if (mesh as MeshInstance3D).material_overlay != null:
			overlays += 1
	_check(overlays > 0, "le fantôme est teinté")

	# Sur le terrain plat, loin des autres : valide ; tourner change le cap.
	var target := base + Vector3(10.0, 0.0, 0.0)
	spawner.call("update_move", target, player.global_position)
	_check(bool(spawner.call("is_move_valid")), "emplacement plat valide")
	var yaw_before := shelter.rotation.y
	spawner.call("rotate_move", 90.0)
	_check(absf(angle_difference(yaw_before, shelter.rotation.y) - deg_to_rad(90.0)) < 0.01, "rotation de 90°")

	# Collé à une autre construction : refusé, et la pose échoue.
	spawner.call("update_move", pen.global_position, player.global_position)
	_check(not bool(spawner.call("is_move_valid")), "posé sur un autre ouvrage : invalide")
	_check(spawner.call("confirm_move") == "TOAST_CANNOT_PLACE" and spawner.call("is_moving"), "pose refusée, reste soulevée")
	# Sur le joueur : invalide.
	spawner.call("update_move", player.global_position + Vector3(0.5, 0, 0), player.global_position)
	_check(not bool(spawner.call("is_move_valid")), "sur le joueur : invalide")

	# Pose valide : position enregistrée, collisions rendues.
	spawner.call("update_move", target, player.global_position)
	_check(spawner.call("confirm_move") == "", "pose réussie")
	_check(not spawner.call("is_moving"), "déplacement terminé")
	_check(solid.collision_layer == 1 and interact_area.collision_layer == 4, "collisions rétablies")
	_check(shelter.global_position.distance_to(target) < 0.3, "l'abri est au nouvel endroit")
	for mesh in shelter.find_children("*", "MeshInstance3D", true, false):
		_check((mesh as MeshInstance3D).material_overlay == null, "teinte retirée")
		break

	# Annulation : retour à l'emplacement précédent.
	var saved_position := shelter.position
	spawner.call("begin_move", shelter)
	spawner.call("update_move", target + Vector3(0, 0, 12), player.global_position)
	spawner.call("cancel_move")
	_check(shelter.position.distance_to(saved_position) < 0.01, "annulation : retour au départ")

	# Panneau : « Déplacer » apparaît sur la cible, puis Tourner / Poser / Annuler.
	var panel := world.get_node_or_null("HUD/Overlay/BuildPanel")
	_check(panel != null, "panneau de construction présent dans le HUD")
	if panel != null:
		_check(not panel.visible, "panneau masqué sans cible")
		panel.call("_on_focus_changed", shelter)
		_check(panel.visible and panel.get("_grab").visible, "« Déplacer » visible sur un abri visé")
		panel.call("_on_grab")
		_check(spawner.call("is_moving") and panel.get("_drop").visible and not panel.get("_grab").visible, "mode déplacement : Poser visible")
		panel.call("_process", 0.1)
		_check(shelter.global_position.distance_to(player.global_position) > 3.0, "le fantôme suit le joueur à distance")
		panel.call("_on_drop")
		_check(not spawner.call("is_moving") or not spawner.call("is_move_valid"), "Poser valide ou refuse proprement")
		if spawner.call("is_moving"):
			spawner.call("cancel_move")

	if _errors.is_empty():
		print("TEST_MOVE_STRUCTURES: PASS")
		quit(0)
	else:
		for e in _errors:
			printerr("TEST_MOVE_STRUCTURES FAIL: " + e)
		quit(1)
