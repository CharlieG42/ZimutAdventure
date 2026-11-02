extends SceneTree
## Saisons et météo : calendrier, météo déterministe, effets sur cultures et survie, jours qui passent.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	await process_frame
	var weather := root.get_node("Weather")
	var clock := root.get_node("DayNightCycle")
	var inventory := root.get_node("Inventory")
	var progression := root.get_node("Progression")
	var survival := root.get_node("SurvivalManager")
	inventory.call("clear_for_test")
	progression.call("clear_for_test", true)
	survival.call("clear_for_test")

	# --- Calendrier ------------------------------------------------------------------------
	var seasons: Array = []
	for day in [0, 5, 6, 12, 18, 23, 24]:
		seasons.append(weather.call("season_for", day))
	_check(seasons == ["spring", "spring", "summer", "autumn", "winter", "winter", "spring"], "quatre saisons de 6 jours, en boucle")
	# --- Météo déterministe ------------------------------------------------------------------
	var same := true
	for day in 30:
		for slot in 4:
			if weather.call("weather_for", day, slot) != weather.call("weather_for", day, slot):
				same = false
	_check(same, "même jour et créneau : même temps")
	var counts := {"clear": 0, "cloudy": 0, "rain": 0, "snow": 0}
	for day in 240:
		for slot in 4:
			counts[weather.call("weather_for", day, slot)] += 1
	_check(counts["rain"] > 0 and counts["snow"] > 0 and counts["clear"] > counts["rain"], "temps variés : %s" % str(counts))
	var snow_in_winter := true
	var rain_in_winter := false
	for day in range(18, 24):
		for slot in 4:
			var w: String = weather.call("weather_for", day, slot)
			if w == "rain":
				rain_in_winter = true
	_check(snow_in_winter and not rain_in_winter, "l'hiver neige au lieu de pleuvoir")

	# --- Sans effets (tests headless) ---------------------------------------------------------------
	_check(is_equal_approx(float(weather.call("crop_factor")), 1.0) and not bool(weather.call("is_raining")), "headless : aucun effet par défaut")

	# --- Effets ----------------------------------------------------------------------------------------
	weather.call("enable_effects_for_test", 18)
	_check(weather.call("get_season") == "winter", "jour 18 : hiver")
	_check(float(weather.call("crop_factor")) < 1.0, "hiver : cultures plus lentes")
	_check(float(weather.call("hunger_factor")) > 1.0, "hiver : faim plus vive")
	weather.call("enable_effects_for_test", 6)
	_check(float(weather.call("thirst_factor")) > 1.0 or weather.call("get_weather") == "rain", "été : soif plus vive")
	weather.call("enable_effects_for_test", 0)
	_check(float(weather.call("crop_factor")) > 1.0, "printemps : cultures plus rapides")

	# --- Aspect des surfaces (neige, feuillage, humidité) -------------------------------------
	weather.call("enable_effects_for_test", 18)
	weather.call("snap_surfaces")
	_check(float(weather.call("get_snow_amount")) >= 0.8, "hiver : sol enneigé")
	weather.call("enable_effects_for_test", 12)
	weather.call("snap_surfaces")
	_check(float(weather.call("get_snow_amount")) == 0.0 and float(weather.call("get_foliage_tint_amount")) > 0.5, "automne : pas de neige, feuillage roussi")
	weather.call("enable_effects_for_test", 6)
	weather.call("snap_surfaces")
	_check(float(weather.call("get_foliage_tint_amount")) == 0.0, "été : feuillage naturel")
	_check(load("res://assets/landscapes/shaders/water_surface.gdshader") is Shader, "shader de l'eau chargé")

	weather.call("enable_effects_for_test", 0)

	# --- Jours qui passent --------------------------------------------------------------------------------
	clock.set("day", 0)
	clock.call("set_hour", 22.0)
	clock.call("set_hour", 6.0)
	_check(int(clock.get("day")) == 1, "dormir jusqu'au matin passe un jour")
	clock.call("set_hour", 8.0)
	_check(int(clock.get("day")) == 1, "avancer dans la journée ne change pas de jour")
	weather.call("enable_effects_for_test", 5)
	clock.emit_signal("day_changed", 6)
	_check(weather.call("get_season") == "summer", "le jour 6 ouvre l'été")
	_check(int(progression.call("get_stat", "stat_seasons")) == 1, "compteur de saisons")

	# --- La pluie arrose les cultures ----------------------------------------------------------------------------
	var rain_day := -1
	for day in range(0, 40):
		if weather.call("season_for", day) != "winter":
			for slot in 4:
				if weather.call("weather_for", day, slot) == "rain":
					rain_day = day * 10 + slot
					break
		if rain_day >= 0:
			break
	_check(rain_day >= 0, "un jour de pluie existe")
	var day_r := rain_day / 10
	var slot_r := rain_day % 10
	clock.call("set_hour", 12.0)
	weather.call("enable_effects_for_test", day_r)
	clock.call("set_hour", float(slot_r) * 6.0 + 1.0)
	weather.call("enable_effects_for_test", day_r)
	_check(weather.call("get_weather") == "rain" and bool(weather.call("is_raining")), "il pleut au créneau choisi")
	var plot: Node3D = load("res://scripts/world/farm_plot.gd").create()
	root.add_child(plot)
	await process_frame
	plot.set("planted_at", plot.call("_now") - 10.0)
	await process_frame
	await process_frame
	_check(bool(plot.get("watered")), "la pluie arrose la culture")
	_check(int(progression.call("get_stat", "stat_watered")) == 0, "arrosage naturel : pas compté comme celui du joueur")

	# --- Le joueur est bien dans le groupe « player » (animaux, HUD, météo s'en servent) ----------
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 5:
		await process_frame
	_check(get_first_node_in_group("player") == world.get_node("Player"), "le joueur est dans le groupe player")

	weather.call("clear_for_test")
	print("TEST_WEATHER: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
