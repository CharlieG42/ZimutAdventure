extends SceneTree
## P3 ciel de nuit : aurores boréales (région Canada) + étoiles filantes dans sky.gdshader,
## lucioles (world_setup, la nuit), et P2-10 : SSAO renforcé en qualité haute sur PC.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _init() -> void:
	await process_frame
	var rm := root.get_node_or_null("RegionManager")
	_check(rm != null, "RegionManager présent")
	rm.call("clear_for_test")
	rm.set("change_scene_enabled", false)

	# --- Shader : aurores + météores présents ---
	var sky_code := FileAccess.get_file_as_string("res://assets/landscapes/../vfx/sky/sky.gdshader")
	sky_code = FileAccess.get_file_as_string("res://assets/vfx/sky/sky.gdshader")
	_check(sky_code.contains("uniform float aurora_amount"), "sky.gdshader : uniform aurora_amount")
	_check(sky_code.contains("curtain"), "sky.gdshader : rideaux d'aurore")
	_check(sky_code.contains("mslot"), "sky.gdshader : étoiles filantes (météores)")

	# --- Aurores : Canada la nuit, pas l'Ouest ---
	rm.set("current_region", "canada")
	var world := (load("res://scenes/world/canada_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 12:
		await process_frame
	var clock := root.get_node_or_null("DayNightCycle")
	var env_node := world.get_node("WorldEnvironment") as WorldEnvironment
	var sky_mat: ShaderMaterial = env_node.environment.sky.sky_material as ShaderMaterial
	clock.call("set_hour", 23.0)
	await process_frame
	var aurora_night: float = sky_mat.get_shader_parameter("aurora_amount")
	_check(aurora_night > 0.9, "canada 23 h : aurora_amount ~1, got %f" % aurora_night)
	clock.call("set_hour", 12.0)
	await process_frame
	var aurora_day: float = sky_mat.get_shader_parameter("aurora_amount")
	_check(aurora_day < 0.01, "canada midi : pas d'aurore, got %f" % aurora_day)

	rm.call("clear_for_test")
	rm.set("change_scene_enabled", false)
	var world2 := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world2)
	for i in 12:
		await process_frame
	clock.call("set_hour", 23.0)
	await process_frame
	var env2 := world2.get_node("WorldEnvironment") as WorldEnvironment
	var aurora_west: float = (env2.environment.sky.sky_material as ShaderMaterial).get_shader_parameter("aurora_amount")
	_check(aurora_west < 0.01, "ouest 23 h : pas d'aurore (région sans), got %f" % aurora_west)

	# --- Lucioles : code présent, activées la nuit ---
	var ws_code := FileAccess.get_file_as_string("res://scripts/world/world_setup.gd")
	_check(ws_code.contains("_add_fireflies") and ws_code.contains("Fireflies"), "world_setup : nœud Fireflies")
	_check(ws_code.contains('"night"'), "world_setup : lucioles actives la nuit (phase)")

	# --- P2-10 : SSAO renforcé en niveau 0 (headless = PC) ---
	# Le garde ne touche que le PREMIER WorldEnvironment de l'arbre : on le retrouve comme lui.
	var guard := root.get_node_or_null("PerformanceGuard")
	_check(guard != null, "PerformanceGuard présent")
	var first_envs := root.find_children("*", "WorldEnvironment", true, false)
	var env: Environment = (first_envs[0] as WorldEnvironment).environment
	guard.call("set_level", 0)
	await process_frame
	_check(env.ssao_enabled and absf(env.ssao_radius - 2.4) < 0.01 and absf(env.ssao_intensity - 1.7) < 0.01,
		"niveau 0 PC : SSAO radius 2.4 / intensity 1.7 (got %f / %f)" % [env.ssao_radius, env.ssao_intensity])
	guard.call("set_level", 1)
	await process_frame
	_check(not env.ssao_enabled and absf(env.ssao_radius - 1.5) < 0.01, "niveau 1 : SSAO coupé, radius restauré (got %f)" % env.ssao_radius)
	guard.call("set_level", 0)
	await process_frame
	_check(env.ssao_enabled and absf(env.ssao_radius - 2.4) < 0.01, "retour niveau 0 : SSAO haut restauré")

	print("TEST_NIGHT_SKY_FX: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
