extends SceneTree
## Props GLB : couleurs corrigées (palette du canyon), matériaux mats et non métalliques.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	await process_frame
	var library = load("res://scripts/world/glb_prop_library.gd")
	var raw := StandardMaterial3D.new()
	raw.resource_name = "leafsDark"
	raw.albedo_color = Color(0.83, 0.83, 0.84)
	raw.metallic = 1.0
	var fixed: StandardMaterial3D = library.adapt_material(raw)
	_check(fixed.metallic == 0.0, "métal retiré")
	_check(fixed != raw, "le matériau d'origine n'est pas modifié")
	_check(fixed.albedo_color.g > fixed.albedo_color.b and fixed.albedo_color.v < 0.5, "feuillage olive, pas bleuté")
	var other := StandardMaterial3D.new()
	other.resource_name = "inconnu"
	other.albedo_color = Color(0.8, 0.8, 0.8)
	var other_fixed: StandardMaterial3D = library.adapt_material(other)
	_check(other_fixed.albedo_color.v < 0.7, "couleur inconnue relue en sRGB (plus sombre)")
	for prop_id in ["pine", "boulder", "cactus"]:
		for mesh in library.get_variant_meshes(prop_id):
			var ok := true
			for i in (mesh as Mesh).get_surface_count():
				var mat := (mesh as Mesh).surface_get_material(i) as StandardMaterial3D
				if mat != null and mat.metallic > 0.01:
					ok = false
			if not ok:
				_failures += 1
				print("  FAIL - variante métallique dans ", prop_id)
	var rocks: Array = library.get_variant_meshes("sandstone")
	_check(rocks.size() == 6, "six rochers de grès chargés (%d)" % rocks.size())
	if not rocks.is_empty():
		var rock := rocks[0] as Mesh
		var mat := rock.surface_get_material(0) as StandardMaterial3D
		_check(mat != null and mat.vertex_color_use_as_albedo, "rocher de grès : couleurs de sommets actives")
		var arrays := rock.surface_get_arrays(0)
		_check(arrays[Mesh.ARRAY_COLOR] != null, "rocher de grès : couleurs conservées à la fusion")
		_check(rock.get_aabb().position.y > -0.01 and rock.get_aabb().size.y > 1.0, "rocher posé au sol")
		var triangles := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		_check(triangles <= 1500, "budget triangles mobile (%d)" % triangles)
	var arches: Array = library.get_variant_meshes("arch")
	_check(arches.size() == 3, "trois arches chargées (%d)" % arches.size())
	if not arches.is_empty():
		var box: AABB = (arches[0] as Mesh).get_aabb()
		_check(box.size.x > 10.0 and box.size.y > 5.0, "arche : %.0f m de large, %.0f m de haut" % [box.size.x, box.size.y])
		_check(box.position.y < 0.0, "pieds de l'arche enfoncés dans le sol")
	var pebbles: Array = library.get_variant_meshes("pebble")
	_check(pebbles.size() == 4, "quatre cailloux chargés (%d)" % pebbles.size())
	if not pebbles.is_empty():
		var tri := ((pebbles[0] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		_check(tri <= 100, "caillou léger (%d triangles)" % tri)
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
