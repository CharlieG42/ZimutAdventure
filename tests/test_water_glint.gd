extends SceneTree
## Eau P1 : Fresnel teinté ciel + reflet de soleil (glint) dans water_surface/river_surface.
## DayNightCycle publie les paramètres globaux sun_dir / sun_tint / sun_amount / sky_reflect.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _init() -> void:
	await process_frame

	# Les deux shaders d'eau déclarent les paramètres globaux de reflet.
	for path in ["res://assets/landscapes/shaders/water_surface.gdshader", "res://assets/landscapes/shaders/river_surface.gdshader"]:
		var sh := load(path) as Shader
		_check(sh != null, "%s charge" % path.get_file())
		if sh != null:
			var code := sh.code
			_check(code.contains("global uniform vec3 sun_dir"), "%s : global sun_dir" % path.get_file())
			_check(code.contains("global uniform vec4 sky_reflect"), "%s : global sky_reflect" % path.get_file())
			_check(code.contains("glint"), "%s : reflet de soleil (glint)" % path.get_file())

	# La source d'eau de la scène utilise water_surface.gdshader.
	var ws := (load("res://scenes/interaction/water_source.tscn") as PackedScene).instantiate()
	root.add_child(ws)
	for i in 4:
		await process_frame
	var pool := ws.get_node("Pool") as MeshInstance3D
	var wmat := pool.get_active_material(0) as ShaderMaterial
	_check(wmat != null and wmat.shader != null and wmat.shader.resource_path.ends_with("water_surface.gdshader"), "WaterSource.Pool utilise water_surface.gdshader")

	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var clock := root.get_node_or_null("DayNightCycle")
	_check(clock != null, "DayNightCycle présent")
	if clock == null:
		quit(1)

	# Midi : soleil haut, reflet actif, direction normalisée.
	# (global_shader_parameter_get renvoie null en headless : on lit les valeurs publiées par DayNightCycle.)
	clock.call("set_hour", 12.0)
	await process_frame
	var sun_dir: Vector3 = clock.last_sun_dir
	var sun_amount: float = clock.last_sun_amount
	var sky_reflect: Color = clock.last_sky_reflect
	_check(absf(sun_dir.length() - 1.0) < 0.01, "midi : sun_dir normalisé, got %s" % sun_dir)
	_check(sun_amount > 0.9, "midi : sun_amount ~1 (reflet actif), got %f" % sun_amount)
	_check(sky_reflect.get_luminance() > 0.05, "midi : sky_reflect non noir, got %s" % sky_reflect)

	# 23 h : soleil éteint, plus de reflet solaire (pas de NaN si non initialisé).
	clock.call("set_hour", 23.0)
	await process_frame
	sun_amount = clock.last_sun_amount
	sun_dir = clock.last_sun_dir
	_check(sun_amount <= 0.01, "23 h : sun_amount ~0 (pas de reflet), got %f" % sun_amount)
	_check(absf(sun_dir.length() - 1.0) < 0.01, "23 h : sun_dir toujours normalisé, got %s" % sun_dir)

	print("TEST_WATER_GLINT: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
