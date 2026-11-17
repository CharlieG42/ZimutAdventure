extends SceneTree
## Baisse de qualité : les ombres du soleil sont allégées, jamais coupées (un soleil sans
## ombre assombrit toute la scène en rendu Compatibility), puis restaurées à l'identique.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var guard := root.get_node_or_null("PerformanceGuard")
	if guard == null:
		guard = (load("res://scripts/autoload/performance_guard.gd") as GDScript).new()
		guard.name = "PerformanceGuard"
		root.add_child(guard)
	guard.set_process(false)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_blend_splits = true
	root.add_child(sun)
	await process_frame

	guard.call("set_level", 2)
	if not sun.shadow_enabled:
		errors.append("qualité basse : les ombres restent actives")
	if sun.directional_shadow_mode != DirectionalLight3D.SHADOW_ORTHOGONAL or sun.directional_shadow_max_distance > 45.0 \
			or sun.directional_shadow_blend_splits:
		errors.append("qualité basse : une seule cascade, portée courte")
	guard.call("set_level", 2)
	guard.call("set_level", 0)
	if sun.directional_shadow_mode != DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS or absf(sun.directional_shadow_max_distance - 120.0) > 0.01 \
			or not sun.directional_shadow_blend_splits:
		errors.append("retour en qualité haute : réglages d'origine restaurés")
	if not is_equal_approx(root.scaling_3d_scale, 1.0):
		errors.append("retour en qualité haute : rendu 3D à pleine résolution")

	sun.free()
	if errors.is_empty():
		print("TEST_QUALITY_SHADOWS: PASS")
		quit(0)
	else:
		for e in errors:
			print("TEST_QUALITY_SHADOWS FAIL: " + e)
		quit(1)
