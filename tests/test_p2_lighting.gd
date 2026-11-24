extends SceneTree
## P2 : rim light (prop_atmosphere.rim_light) sur rochers/troncs, backlight du feuillage,
## teinte par instance sur les MultiMesh (use_colors + COLOR dans les shaders de props).

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _init() -> void:
	await process_frame

	# Rim light dans l'include + branchée dans rochers et troncs.
	var inc := FileAccess.get_file_as_string("res://assets/landscapes/shaders/prop_atmosphere.gdshaderinc")
	_check(inc.contains("global uniform vec3 sun_dir"), "prop_atmosphere : global sun_dir")
	_check(inc.contains("vec3 rim_light("), "prop_atmosphere : helper rim_light()")
	for p in ["res://assets/landscapes/shaders/prop_rock.gdshader", "res://assets/landscapes/shaders/prop_trunk.gdshader"]:
		var code := FileAccess.get_file_as_string(p)
		_check(code.contains("prop_atmosphere.gdshaderinc"), "%s inclut prop_atmosphere" % p.get_file())
		_check(code.contains("rim_light("), "%s applique le rim light" % p.get_file())
		_check(code.contains("v_inst = COLOR.rgb"), "%s lit la teinte d'instance (COLOR)" % p.get_file())

	# Backlight du feuillage + teinte d'instance.
	var fol := FileAccess.get_file_as_string("res://assets/landscapes/shaders/prop_foliage.gdshader")
	_check(fol.contains("global uniform vec3 sun_dir"), "prop_foliage : global sun_dir (backlight)")
	_check(fol.contains("back") and fol.contains("sun_amount"), "prop_foliage : backlight contre le soleil")
	_check(fol.contains("v_inst = COLOR.rgb"), "prop_foliage lit la teinte d'instance (COLOR)")

	# Les MultiMesh du monde ont use_colors activé (les couleurs par instance vivent dans le
	# RenderingServer : illisibles en headless, on vérifie le flag + la fonction de teinte).
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 12:
		await process_frame
	var found_colors := false
	for node in world.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm != null and mm.use_colors and mm.instance_count > 1:
			found_colors = true
			break
	_check(found_colors, "MultiMesh avec use_colors trouvé")
	var lm := load("res://scripts/world/landscape_manager.gd")
	var c_a: Color = lm._instance_tint(Vector3(1.3, 0.0, 7.9))
	var c_b: Color = lm._instance_tint(Vector3(100.2, 0.0, 55.5))
	_check(c_a != c_b, "teinte d'instance variable selon la position (%s vs %s)" % [c_a, c_b])
	_check(c_a.r >= 0.8 and c_a.r <= 1.2 and c_a.g >= 0.8 and c_a.b >= 0.8, "teinte proche du blanc (subtile), got %s" % c_a)

	print("TEST_P2_LIGHTING: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
