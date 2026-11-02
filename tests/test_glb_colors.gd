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
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
