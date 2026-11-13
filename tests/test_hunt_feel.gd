extends SceneTree
## Confort de chasse et d'élevage : arc que l'on bande, cible verrouillée, tir qui compense
## la chute, flèches récupérées, gibier qui revient, animaux qui se laissent approcher.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	await process_frame
	var inventory := root.get_node("Inventory")
	var progression := root.get_node("Progression")
	inventory.call("clear_for_test")
	progression.call("clear_for_test", true)
	progression.call("add_xp", 100000)
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var player := world.get_node("Player") as CharacterBody3D
	var player_script: GDScript = load("res://scripts/player/player.gd")

	# --- Messages : le HUD doit être joignable par tout le jeu (groupe « hud ») ----------------------
	var hud := root.get_tree().get_first_node_in_group("hud")
	_check(hud != null and hud.has_method("show_toast"), "le HUD reçoit les messages du jeu (groupe hud)")
	if hud != null:
		hud.call("set_gauge", "test", 0.5)
		_check((hud.get("_gauge") as Control).visible, "jauge d'action affichée")
		hud.call("clear_gauge")
		_check(not (hud.get("_gauge") as Control).visible, "jauge d'action masquée")

	# --- Balistique : la direction calculée atteint bien le point visé -----------------------------
	var g := 9.8
	for case in [[Vector3(20, 0, 0), 30.0], [Vector3(0, 3, -35), 38.0], [Vector3(-12, -2, 9), 26.0]]:
		var target: Vector3 = case[0]
		var speed: float = case[1]
		var dir: Vector3 = player_script.call("ballistic_direction", Vector3.ZERO, target, speed, g)
		var flat := Vector2(target.x, target.z).length()
		var t := flat / (Vector2(dir.x, dir.z).length() * speed)
		var y := dir.y * speed * t - 0.5 * g * t * t
		_check(absf(y - target.y) < 0.05, "tir compensé vers %s (écart %.3f m)" % [str(target), absf(y - target.y)])
	var lob: Vector3 = player_script.call("ballistic_direction", Vector3.ZERO, Vector3(400, 0, 0), 26.0, g)
	_check(lob.y > 0.5, "hors de portée : tir en cloche")

	# --- Arc : maintenir pour bander, relâcher pour tirer ---------------------------------------------
	inventory.call("add_item", "tool_hunting_bow", 1)
	inventory.call("equip", "tool_hunting_bow")
	player.call("begin_attack")
	_check(not bool(player.get("_drawing")), "sans flèche, l'arc ne se bande pas")
	inventory.call("add_item", "arrow", 5)
	player.call("begin_attack")
	_check(bool(player.get("_drawing")), "appui : l'arc se bande")
	for i in 60:
		await physics_frame
	_check(float(player.call("get_draw_charge")) >= 0.99, "pleine tension après un instant")
	_check(bool(player.get("_aiming")), "le zoom de visée accompagne la tension")
	var state: Dictionary = player.call("get_bow_state")
	_check(bool(state["equipped"]) and bool(state["drawing"]) and int(state["arrows"]) == 5, "état de l'arc pour l'affichage")
	player.call("end_attack")
	_check(not bool(player.get("_drawing")) and inventory.call("count_of", "arrow") == 4, "relâchement : une flèche part")
	var arrow := _last_arrow(world)
	_check(arrow != null and absf((arrow as RigidBody3D).linear_velocity.length() - 38.0) < 0.6, "flèche à pleine vitesse")
	for i in 5:
		await physics_frame
	_check(not bool(player.get("_aiming")), "le zoom s'arrête après le tir")
	player.call("end_attack")
	_check(inventory.call("count_of", "arrow") == 4, "relâcher sans avoir bandé ne tire rien")

	# --- Verrouillage : le gibier devant le joueur est ciblé et touché de loin -----------------------
	var camera := player.get_node("CameraPivot/Camera3D") as Camera3D
	var prey: CharacterBody3D = null
	for animal in world.get_node("Animals").get_children():
		prey = animal
		break
	_check(prey != null and prey.is_in_group("huntable"), "le gibier est une cible pour l'arc")
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var ground := player.global_position
	prey.global_position = ground + forward * 16.0 + Vector3(0.0, 0.3, 0.0)
	prey.velocity = Vector3.ZERO
	# Le joueur lève le regard vers l'animal (viseur à l'horizontale).
	player.set("_pitch", 0.0)
	for i in 30:
		await physics_frame
		prey.velocity = Vector3.ZERO
	_check(player.get("_bow_target") == prey, "cible verrouillée à 16 m")
	var meat_before: int = inventory.call("count_of", "item_raw_meat")
	player.call("shoot_arrow", 1.0)
	var hit := false
	for i in 120:
		await physics_frame
		if prey.get("_dead") == true:
			hit = true
			break
	_check(hit, "la flèche atteint la cible verrouillée à 16 m")
	_check(inventory.call("count_of", "item_raw_meat") > meat_before, "viande récoltée")
	_check(not prey.is_in_group("huntable"), "l'animal abattu n'est plus une cible")
	for i in 4:
		await physics_frame
	_check(player.get("_bow_target") != prey, "le verrou se libère")
	# Le gibier revient plus tard sur son territoire.
	prey.call("_vanish")
	_check(not prey.visible, "l'animal abattu disparaît")
	prey.call("_respawn")
	_check(prey.visible and prey.get("_dead") == false and prey.is_in_group("huntable"), "un animal revient sur le territoire")

	# --- Animaux domestiques : jamais ciblés --------------------------------------------------------
	var animal_scene := load("res://scenes/world/domestic_animal.tscn") as PackedScene
	var cow = animal_scene.instantiate()
	cow.species = "cow"
	cow.position = ground + forward * 3.0 + Vector3(0.0, 0.5, 0.0)
	world.add_child(cow)
	await physics_frame
	_check(not cow.is_in_group("huntable"), "une vache n'est pas une cible")

	# --- Flèche plantée : ramassée en passant --------------------------------------------------------
	var arrows_before: int = inventory.call("count_of", "arrow")
	var stuck := (load("res://scenes/interaction/arrow.tscn") as PackedScene).instantiate() as RigidBody3D
	world.add_child(stuck)
	stuck.global_position = player.global_position + Vector3(0.6, 0.2, 0.0)
	stuck.set("_stuck", true)
	stuck.freeze = true
	stuck.set_process(true)
	for i in 30:
		await process_frame
	_check(inventory.call("count_of", "arrow") == arrows_before + 1, "flèche plantée ramassée automatiquement")

	# --- Approche des animaux à apprivoiser ----------------------------------------------------------
	inventory.call("clear_for_test")
	cow.global_position = player.global_position + Vector3(0.8, 0.0, 0.0)
	_check(cow.call("_scare_direction") == Vector3.ZERO, "au pas, la vache ne fuit pas")
	inventory.call("add_item", "item_wheat", 3)
	cow.call("_update_curiosity")
	_check(bool(cow.get("_curious")), "avec de la nourriture, elle attend le joueur")
	_check(cow.get_prompt_key() == "ACTION_TAME_WITH_FOOD", "invite : donner à manger")
	cow.interact_with(player)
	_check(cow.trust == 1 and not cow.can_interact_now(), "elle mange : pas de second repas dans la foulée")
	cow.set("_eat_left", 0.0)
	_check(cow.can_interact_now(), "puis elle en redemande")
	var pips: Array = cow.get("_pips")
	_check(pips.size() == 3 and (pips[0] as MeshInstance3D).material_override == cow.get("_pip_full") and (pips[1] as MeshInstance3D).material_override == cow.get("_pip_empty"), "pastilles de confiance : 1 sur 3")
	# Niveau insuffisant : dit clairement dans l'invite.
	progression.call("clear_for_test", true)
	var horse = animal_scene.instantiate()
	horse.species = "horse"
	horse.position = ground + Vector3(4.0, 0.5, 4.0)
	world.add_child(horse)
	await physics_frame
	_check(horse.get_prompt_key() == "ACTION_TAME_LEVEL" and horse.get_prompt_args() == [5], "cheval : niveau requis annoncé dans l'invite")
	_check(String(cow.call("format_wait", 45.0)) == "45 s" and String(cow.call("format_wait", 130.0)) == "2 min 10", "délai lisible")

	# --- Traductions --------------------------------------------------------------------------------
	for key in ["HUD_ARROWS", "ACTION_PET", "ACTION_TAME_LEVEL", "ACTION_FISH_PULL", "HUD_FISH_REEL", "TOAST_FISH_BIG",
			"TOAST_FISH_LEFT", "TOAST_PRODUCT_WAIT", "ANIMAL_DEER", "ANIMAL_RABBIT", "HINT_TAMED_COW", "HINT_TAMED_GOAT",
			"HINT_TAMED_SHEEP", "HINT_TAMED_CHICKEN", "HINT_TAMED_HORSE", "HINT_TAMED_DOG"]:
		for locale in ["fr", "en"]:
			TranslationServer.set_locale(locale)
			_check(tr(key) != key, "traduction %s (%s)" % [key, locale])
	TranslationServer.set_locale("fr")

	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures > 0 else 0)

func _last_arrow(world: Node) -> Node:
	var last: Node = null
	for child in world.get_children():
		if child is RigidBody3D and child.get_script() != null and String(child.get_script().resource_path).ends_with("arrow.gd"):
			last = child
	return last
