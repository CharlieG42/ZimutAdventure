extends SceneTree
## Feu de camp P1-6 : halo émissif additif (bloom) + flicker de la couleur de lumière,
## braises (SparkVfx) présentes, halo visible seulement quand le feu est allumé.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _init() -> void:
	await process_frame

	var fire := (load("res://scenes/interaction/campfire.tscn") as PackedScene).instantiate()
	root.add_child(fire)
	for i in 6:
		await process_frame

	# Halo émissif additif branché sur flare_01.png.
	var halo := fire.get_node_or_null("FireHalo") as MeshInstance3D
	_check(halo != null, "nœud FireHalo présent")
	if halo != null:
		var m := halo.get_active_material(0) as StandardMaterial3D
		_check(m != null, "matériau du halo présent")
		if m != null:
			_check(m.blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "halo en blend additif")
			_check(m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "halo unshaded")
			_check(m.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED, "halo en billboard")
			_check(m.emission_enabled and m.emission_energy_multiplier >= 3.0, "halo émissif fort (bloom)")
			_check(m.albedo_texture != null, "halo texturé (flare)")

	# Braises + flammes + fumée : 3 émetteurs de particules.
	var emitters := 0
	for c in fire.get_children():
		if c is GPUParticles3D:
			emitters += 1
	_check(emitters >= 3, "flammes/fumée/braises présents (%d émetteurs)" % emitters)

	var light := fire.get_node("FireLight") as OmniLight3D

	# Feu éteint : rien de visible.
	fire.call("apply_state", {"stage": 0})
	await process_frame
	_check(not halo.visible and not light.visible, "feu éteint : halo et lumière cachés")

	# Feu au max : halo visible, lumière allumée, flicker actif.
	fire.call("apply_state", {"stage": 4})
	for i in 8:
		await process_frame
	_check(halo.visible and light.visible, "feu allumé : halo et lumière visibles")
	_check(light.light_energy > 1.0, "lumière allumée (énergie %f)" % light.light_energy)
	_check(halo.scale.x > 0.3, "halo pulsé (scale %f)" % halo.scale.x)
	var col: Color = light.light_color
	_check(col.r > 0.9 and col.g < 0.7, "teinte orangée (flicker), got %s" % col)

	print("TEST_CAMPFIRE_HALO: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
