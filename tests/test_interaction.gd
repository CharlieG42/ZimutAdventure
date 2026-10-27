extends SceneTree

var inventory_script: GDScript = load("res://scripts/autoload/inventory.gd")
var sfx_script: GDScript = load("res://scripts/autoload/sfx.gd")

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	var inventory := inventory_script.new() as Node
	root.add_child(inventory)
	var sfx := sfx_script.new() as Node
	root.add_child(sfx)
	await process_frame
	inventory.call("clear_for_test")

	inventory.call("add_item", "item_test", 2)
	if inventory.call("count_of", "item_test") != 2:
		errors.append("add_item should add 2x item_test, got %s" % inventory.call("count_of", "item_test"))
	if not inventory.call("has_item", "item_test", 2):
		errors.append("has_item(2) should be true after adding 2")
	if inventory.call("has_item", "item_test", 3):
		errors.append("has_item(3) should be false after adding 2")
	if not inventory.call("remove_item", "item_test", 1):
		errors.append("remove_item(1) should succeed")
	if inventory.call("count_of", "item_test") != 1:
		errors.append("count should be 1 after removing 1, got %s" % inventory.call("count_of", "item_test"))
	if inventory.call("remove_item", "item_test", 5):
		errors.append("remove_item(5) should fail with only 1 left")
	if not inventory.call("remove_item", "item_test", 1):
		errors.append("remove_item(1) should succeed for the last one")
	if inventory.call("count_of", "item_test") != 0:
		errors.append("count should be 0 after removing all")
	if inventory.call("has_item", "item_test"):
		errors.append("has_item should be false when count is 0")

	var added: Array = []
	inventory.connect("item_added", func(id, amt): added.append([id, amt]))
	inventory.call("add_item", "item_sig", 3)
	if added.size() != 1 or added[0] != ["item_sig", 3]:
		errors.append("item_added signal should fire with (item_sig, 3), got %s" % added)

	var item_scene := load("res://scenes/interaction/collectible_item.tscn") as PackedScene
	if item_scene == null:
		errors.append("collectible_item.tscn missing")
	else:
		var item := item_scene.instantiate() as Node3D
		if item == null:
			errors.append("collectible_item.tscn should instantiate")
		else:
			item.set("item_id", "item_scene_test")
			item.set("amount", 2)
			root.add_child(item)
			await process_frame
			if item.get("pickup_sound") == null:
				errors.append("collectible should have a pickup sound")
			inventory.call("add_item", item.get("item_id"), int(item.get("amount")))
			if inventory.call("count_of", "item_scene_test") != 2:
				errors.append("pickup should add 2x item_scene_test, got %s" % inventory.call("count_of", "item_scene_test"))
			item.free()

	var defaults_scene := load("res://scenes/interaction/collectible_item.tscn") as PackedScene
	if defaults_scene != null:
		var inst := defaults_scene.instantiate() as Node3D
		if inst.get("item_id") != "item_stone":
			errors.append("default item_id should be item_stone, got %s" % inst.get("item_id"))
		inst.free()

	if load("res://scripts/interaction/interactable.gd") == null:
		errors.append("interactable.gd should load")
	if load("res://scripts/interaction/collectible_item.gd") == null:
		errors.append("collectible_item.gd should load")

	inventory.free()
	sfx.free()

	var exit_code := 0
	if errors.is_empty():
		print("TEST_INTERACTION: PASS")
	else:
		exit_code = 1
		for e in errors:
			printerr("TEST_INTERACTION FAIL: " + e)
	quit(exit_code)
