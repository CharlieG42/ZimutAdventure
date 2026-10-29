extends SceneTree
## Rochers cassables : interaction, casse, drops de pierres, collision solide.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	var inventory_node := root.get_node_or_null("Inventory")
	if inventory_node == null:
		inventory_node = (load("res://scripts/autoload/inventory.gd") as GDScript).new()
		inventory_node.name = "Inventory"
		root.add_child(inventory_node)
		await process_frame
	inventory_node.call("clear_for_test")
	var sfx_node := root.get_node_or_null("Sfx")
	if sfx_node == null:
		sfx_node = (load("res://scripts/autoload/sfx.gd") as GDScript).new()
		sfx_node.name = "Sfx"
		root.add_child(sfx_node)
		await process_frame

	var stub := Node3D.new()
	root.add_child(stub)
	await process_frame

	# --- Scène cassable --------------------------------------------------------------
	var rock_scene := load("res://scenes/interaction/breakable_rock.tscn") as PackedScene
	if rock_scene == null:
		errors.append("breakable_rock.tscn missing")
	else:
		var rock := rock_scene.instantiate()
		if rock == null:
			errors.append("breakable_rock.tscn should instantiate")
		else:
			var holder := Node3D.new()
			holder.name = "RockHolder"
			root.add_child(holder)
			holder.add_child(rock)
			rock.position = Vector3(10, 0, 10)
			await process_frame
			if rock.get_prompt() != "ACTION_BREAK_ROCK":
				errors.append("rock prompt should be ACTION_BREAK_ROCK, got %s" % rock.get_prompt())
			if not rock.can_interact():
				errors.append("rock should be interactable before breaking")
			var body := rock.get_node("Body") as StaticBody3D
			if body == null or body.collision_layer != 1:
				errors.append("rock should have a solid StaticBody3D on layer 1")
			# Casser le rocher : il disparaît et lâche des pierres ramassables
			rock.call("interact", stub)
			await process_frame
			if is_instance_valid(rock):
				errors.append("rock should be freed after breaking")
			var collectibles := 0
			for child in holder.get_children():
				if child != null and child.get("item_id") != null and child.get("item_id") != "" and child.has_method("interact"):
					collectibles += 1
			if collectibles < 2:
				errors.append("breaking should drop at least 2 collectible stones, got %d" % collectibles)
			# Ramasser un des drops incrémente l'inventaire
			var picked := 0
			for child in holder.get_children():
				if child != null and child.get("item_id") != null and child.get("item_id") != "" and child.has_method("interact"):
					child.call("interact", stub)
					picked += 1
					await process_frame
					break
			if picked > 0 and inventory_node.call("count_of", "item_stone") < 1:
				errors.append("picking a drop should add item_stone to inventory")
			holder.free()

	# --- Scène canyon : placement + collision ----------------------------------------
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var spawner := world.get_node_or_null("BreakableRocks")
	if spawner == null or spawner.get_child_count() < 10:
		errors.append("canyon should spawn breakable rocks, got %d" % (spawner.get_child_count() if spawner != null else -1))
	else:
		var landscape := world.get_node("Landscape")
		var ok := 0
		var solid := 0
		for rock_node in spawner.get_children():
			var ground: float = landscape.terrain_height_at(rock_node.global_position.x, rock_node.global_position.z)
			if absf(rock_node.global_position.y - ground) > 0.05:
				errors.append("rocher cassable flottant/enterré : y=%f sol=%f" % [rock_node.global_position.y, ground])
				break
			ok += 1
			if rock_node.get_node_or_null("Body") is StaticBody3D:
				solid += 1
		if ok < 10:
			errors.append("trop peu de rochers vérifiés (%d)" % ok)
		if solid != ok:
			errors.append("tous les rochers doivent avoir un corps solide (%d/%d)" % [solid, ok])
	world.free()

	var exit_code := 0
	if errors.is_empty():
		print("TEST_BREAKABLE_ROCKS: PASS")
	else:
		exit_code = 1
		for e in errors:
			printerr("TEST_BREAKABLE_ROCKS FAIL: " + e)
	quit(exit_code)
