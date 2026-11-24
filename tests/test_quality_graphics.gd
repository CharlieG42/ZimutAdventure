extends SceneTree
## P0 graphiques : MSAA 2x activé dans le projet, et PerformanceGuard coupe les
## passes chères par niveau (SSAO au niveau 1 ; glow + MSAA au niveau 2, palier de
## rendu 0.9 puis 0.8), avec restauration au niveau 0. Le label de poids du sac est
## aussi positionné en mode portrait.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _init() -> void:
	await process_frame

	# MSAA 2x dans les réglages du projet (1 = MSAA_2X).
	var msaa := int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0))
	_check(msaa == 1, "project.godot : msaa_3d = 1 (MSAA 2x), got %d" % msaa)

	# Environnement de test avec SSAO et glow actifs.
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env := Environment.new()
	env.ssao_enabled = true
	env.glow_enabled = true
	env_node.environment = env
	root.add_child(env_node)

	var guard := root.get_node_or_null("PerformanceGuard")
	if guard == null:
		guard = load("res://scripts/autoload/performance_guard.gd").new()
		guard.name = "PerformanceGuard"
		root.add_child(guard)
	await process_frame
	var vp := root.get_visible_rect().size

	guard.call("set_level", 0)
	_check(env.ssao_enabled and env.glow_enabled, "niveau 0 : SSAO et glow actifs")
	_check(absf(root.scaling_3d_scale - 1.0) < 0.001, "niveau 0 : rendu pleine résolution")
	_check(int(root.msaa_3d) == 1, "niveau 0 : MSAA 2x actif, got %d" % int(root.msaa_3d))

	guard.call("set_level", 1)
	_check(not env.ssao_enabled, "niveau 1 : SSAO coupé")
	_check(env.glow_enabled, "niveau 1 : glow encore actif")
	_check(absf(root.scaling_3d_scale - 0.9) < 0.001, "niveau 1 : rendu x0.9, got %f" % root.scaling_3d_scale)
	_check(int(root.msaa_3d) == 1, "niveau 1 : MSAA toujours actif")

	guard.call("set_level", 2)
	_check(not env.ssao_enabled and not env.glow_enabled, "niveau 2 : SSAO et glow coupés")
	_check(int(root.msaa_3d) == 0, "niveau 2 : MSAA coupé, got %d" % int(root.msaa_3d))
	_check(absf(root.scaling_3d_scale - 0.8) < 0.001, "niveau 2 : rendu x0.8")

	guard.call("set_level", 0)
	_check(env.ssao_enabled and env.glow_enabled, "retour niveau 0 : SSAO et glow restaurés")
	_check(int(root.msaa_3d) == 1, "retour niveau 0 : MSAA restauré")
	_check(absf(root.scaling_3d_scale - 1.0) < 0.001, "retour niveau 0 : pleine résolution")

	# Label de poids du sac positionné en mode portrait (fusion #88 + #91).
	var hud_scene := load("res://scenes/ui/hud.tscn") as PackedScene
	var hud := hud_scene.instantiate() as CanvasLayer
	root.add_child(hud)
	await process_frame
	await process_frame
	hud._fit_to_viewport(Vector2(390, 844))
	await process_frame
	var wl: Control = hud.get_node("Overlay/WeightLabel")
	var wr := wl.get_global_rect()
	_check(wr.position.x >= 0.0 and wr.end.x <= 390.0 and wr.position.y > 300.0 and wr.end.y <= 844.0,
		"portrait 390x844 : weight_label dans l'écran et sous les jauges, got %s" % str(wr))
	var vitals: Control = hud.get_node("Overlay/Vitals")
	_check(wr.position.y >= vitals.get_global_rect().end.y - 1.0, "weight_label sous les jauges en portrait")

	print("TEST_QUALITY_GRAPHICS: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
