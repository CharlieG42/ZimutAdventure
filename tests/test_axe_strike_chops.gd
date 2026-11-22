extends SceneTree
## Le bouton « Frapper » (hache équipée) doit abattre l'arbre devant le joueur,
## comme le bouton Action ; sans hache ou arbre trop loin : rien.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var inventory: Node = root.get_node("Inventory")
	inventory.call("clear_for_test") if inventory.has_method("clear_for_test") else null
	inventory.call("add_item", "tool_stone_axe", 1)
	var host := Node3D.new()
	root.add_child(host)
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	host.add_child(player)
	player.global_position = Vector3.ZERO
	var tree_node: Node3D = (load("res://scenes/interaction/choppable_tree.tscn") as PackedScene).instantiate()
	host.add_child(tree_node)
	tree_node.global_position = Vector3(0.0, 0.0, -2.2)
	await process_frame
	await process_frame
	inventory.call("equip", "tool_stone_axe")
	for i in 4:
		player.set("_melee_cooldown", 0.0)
		player.call("begin_attack")
	if not bool(tree_node.get("felled")):
		errors.append("4 coups de hache devant l'arbre devraient l'abattre (hits=%d)" % int(tree_node.get("hits")))
	# Arbre loin : aucun effet.
	var far: Node3D = (load("res://scenes/interaction/choppable_tree.tscn") as PackedScene).instantiate()
	host.add_child(far)
	far.global_position = Vector3(0.0, 0.0, -12.0)
	await process_frame
	player.set("_melee_cooldown", 0.0)
	player.call("begin_attack")
	if int(far.get("hits")) != 0:
		errors.append("un arbre hors de portée ne doit pas être touché")
	if errors.is_empty():
		print("TEST_AXE_STRIKE_CHOPS: PASS")
		quit(0)
	else:
		for e in errors: printerr("TEST_AXE_STRIKE_CHOPS FAIL: " + e)
		quit(1)
