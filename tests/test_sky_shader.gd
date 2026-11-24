extends SceneTree
## Ciel custom (P1) : sky.gdshader branché dans la scène, DayNightCycle pilote les
## uniforms (day_factor, star_amount la nuit, sun/moon direction, cloud_cover).

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _init() -> void:
	await process_frame

	# Le shader existe et se charge.
	var shader := load("res://assets/vfx/sky/sky.gdshader") as Shader
	_check(shader != null, "sky.gdshader charge comme Shader")

	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var env_node := world.get_node("WorldEnvironment") as WorldEnvironment
	var mat: ShaderMaterial = env_node.environment.sky.sky_material as ShaderMaterial
	_check(mat != null and mat.shader == shader, "la scène utilise sky.gdshader (ShaderMaterial)")
	_check(mat.get_shader_parameter("cloud_texture") != null, "cloud_texture branchée")

	var clock := root.get_node_or_null("DayNightCycle")
	_check(clock != null, "DayNightCycle présent")
	if clock == null or mat == null:
		quit(1)

	# Midi : jour, pas d'étoiles.
	clock.call("set_hour", 12.0)
	await process_frame
	var day_factor: float = mat.get_shader_parameter("day_factor")
	var stars: float = mat.get_shader_parameter("star_amount")
	_check(day_factor > 0.99, "midi : day_factor ~1, got %f" % day_factor)
	_check(stars <= 0.001, "midi : pas d'étoiles, got %f" % stars)
	var sun_dir: Vector3 = mat.get_shader_parameter("sun_direction")
	_check(absf(sun_dir.length() - 1.0) < 0.01, "sun_direction normalisé")

	# 23 h : nuit, étoiles visibles, soleil sous l'horizon.
	clock.call("set_hour", 23.0)
	await process_frame
	day_factor = mat.get_shader_parameter("day_factor")
	stars = mat.get_shader_parameter("star_amount")
	_check(day_factor <= 0.001, "23 h : day_factor ~0, got %f" % day_factor)
	_check(stars > 0.9, "23 h : étoiles visibles (star_amount ~1), got %f" % stars)
	var moon_dir: Vector3 = mat.get_shader_parameter("moon_direction")
	_check(absf(moon_dir.length() - 1.0) < 0.01, "moon_direction normalisé")

	# La couverture nuageuse suit la météo.
	clock.set("weather_dim", 0.8)
	clock.call("set_hour", 12.0)
	await process_frame
	_check(absf(float(mat.get_shader_parameter("cloud_cover")) - 0.8) < 0.01, "cloud_cover suit weather_dim, got %f" % float(mat.get_shader_parameter("cloud_cover")))

	print("TEST_SKY_SHADER: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
