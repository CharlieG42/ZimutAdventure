extends SceneTree

var cycle_script: GDScript = load("res://scripts/autoload/day_night_cycle.gd")

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	var cycle: Node = cycle_script.new()
	root.add_child(cycle)
	await process_frame

	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.background_mode = Environment.BG_SKY

	var phases: Array[String] = []
	cycle.phase_changed.connect(func(p): phases.append(p))

	cycle.bind_world(sun, env)

	cycle.set_hour(12.0)
	if abs(sun.light_energy - 1.4) > 0.01:
		errors.append("at noon sun energy should be max, got %.2f" % sun.light_energy)
	if cycle.get_phase() != "day":
		errors.append("at noon phase should be day, got %s" % cycle.get_phase())

	cycle.set_hour(23.0)
	if sun.light_energy > 0.01:
		errors.append("at 23h sun energy should be ~0, got %.2f" % sun.light_energy)
	if cycle.get_phase() != "night":
		errors.append("at 23h phase should be night, got %s" % cycle.get_phase())
	if env.ambient_light_energy > 0.15:
		errors.append("at night ambient energy should be low, got %.2f" % env.ambient_light_energy)

	cycle.set_hour(18.0)
	if cycle.get_phase() != "dusk":
		errors.append("at 18h phase should be dusk, got %s" % cycle.get_phase())

	cycle.set_hour(5.5)
	if cycle.get_phase() != "dawn":
		errors.append("at 5:30 phase should be dawn, got %s" % cycle.get_phase())

	if phases.is_empty():
		errors.append("phase_changed should have fired")

	cycle.day_length = 24.0
	cycle.set_hour(10.0)
	var sun_rot_before := sun.rotation.x
	await create_timer(0.1).timeout
	if sun.rotation.x == sun_rot_before:
		errors.append("sun should rotate over time when enabled")

	cycle.enabled = false
	var hour_before: float = cycle.hour
	await create_timer(0.1).timeout
	if cycle.hour != hour_before:
		errors.append("hour should not advance when cycle disabled")

	sun.free()
	cycle.free()

	var exit_code := 0
	if errors.is_empty():
		print("TEST_DAY_NIGHT: PASS")
	else:
		exit_code = 1
		for e in errors:
			printerr("TEST_DAY_NIGHT FAIL: " + e)
	quit(exit_code)
