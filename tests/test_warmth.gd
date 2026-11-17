extends SceneTree
## Chaleur corporelle : température de l'air (saison, heure, météo, altitude), ressenti
## (feu, abri, cape, mouillé), refroidissement, réchauffement, dégâts du froid, chaleur.

func _ensure(node_name: String, script_path: String) -> Node:
	var node := root.get_node_or_null(node_name)
	if node == null:
		node = (load(script_path) as GDScript).new()
		node.name = node_name
		root.add_child(node)
	return node

func _init() -> void:
	await process_frame
	var errors: Array[String] = []
	var inventory := _ensure("Inventory", "res://scripts/autoload/inventory.gd")
	await process_frame
	inventory.call("clear_for_test")
	var survival := _ensure("SurvivalManager", "res://scripts/autoload/survival_manager.gd")
	await process_frame
	survival.set_process(false)
	survival.call("clear_for_test")
	var script := survival.get_script() as GDScript

	# --- Air : l'après-midi est plus chaud que la nuit, l'été que l'hiver, la plaine que le plateau.
	var summer_day: float = script.call("air_temperature", "summer", 15.0, "clear", 0.0)
	var winter_night: float = script.call("air_temperature", "winter", 3.0, "clear", 0.0)
	var spring_day: float = script.call("air_temperature", "spring", 12.0, "clear", 0.0)
	if not (summer_day > 32.0):
		errors.append("après-midi d'été au-delà de 32 °C (%.1f)" % summer_day)
	if not (winter_night < -5.0):
		errors.append("nuit d'hiver sous -5 °C (%.1f)" % winter_night)
	if spring_day < 12.0 or spring_day > 25.0:
		errors.append("journée de printemps agréable (%.1f)" % spring_day)
	if float(script.call("air_temperature", "autumn", 14.0, "rain", 0.0)) >= float(script.call("air_temperature", "autumn", 14.0, "clear", 0.0)):
		errors.append("la pluie rafraîchit")
	if float(script.call("air_temperature", "spring", 12.0, "clear", 16.0)) >= spring_day:
		errors.append("il fait plus frais sur le plateau")
	# Une nuit de printemps n'est pas dangereuse : on joue sans souci les premiers jours.
	if float(script.call("air_temperature", "spring", 3.0, "clear", 0.0)) < 6.0:
		errors.append("une nuit de printemps ne refroidit pas")

	# --- Ressenti : le feu, l'abri et la cape réchauffent, être mouillé refroidit.
	var night := {"season": "winter", "hour": 3.0, "weather": "clear"}
	var bare: float = survival.call("felt_temperature", night)
	var by_fire := night.duplicate()
	by_fire["fire_distance"] = 2.0
	var cloaked := night.duplicate()
	cloaked["cloak"] = true
	var sheltered := night.duplicate()
	sheltered["sheltered"] = true
	if float(survival.call("felt_temperature", by_fire)) < 6.0:
		errors.append("au coin du feu on n'a plus froid même en hiver")
	if float(survival.call("felt_temperature", cloaked)) <= bare or float(survival.call("felt_temperature", sheltered)) <= bare:
		errors.append("cape et abri réchauffent")
	var far_fire := night.duplicate()
	far_fire["fire_distance"] = 30.0
	if not is_equal_approx(float(survival.call("felt_temperature", far_fire)), bare):
		errors.append("un feu lointain ne chauffe pas")

	# --- Refroidissement : nuit d'hiver dehors -> jauge vide en quelques minutes, puis dégâts.
	for i in 120:
		survival.call("update_temperature", 1.0, night)
	var after_two_minutes: float = survival.call("get_warmth")
	if after_two_minutes >= 0.9 or after_two_minutes <= 0.0:
		errors.append("le froid agit progressivement (%.2f après 2 min)" % after_two_minutes)
	if not bool(survival.get("_cold_hint_shown")):
		errors.append("un conseil s'affiche quand on commence à avoir froid")
	for i in 300:
		survival.call("update_temperature", 1.0, night)
	if float(survival.call("get_warmth")) > 0.0:
		errors.append("au bout de 7 min d'hiver sans protection la chaleur est épuisée")
	if float(survival.call("stamina_regen_factor")) >= 1.0:
		errors.append("avoir froid fatigue")
	# Le feu réchauffe vite.
	for i in 20:
		survival.call("update_temperature", 1.0, by_fire)
	if float(survival.call("get_warmth")) < 0.99:
		errors.append("20 s au coin du feu suffisent à se réchauffer (%.2f)" % float(survival.call("get_warmth")))

	# --- Mouillé : la rivière trempe, on sèche ensuite (plus vite au feu).
	var wading := {"season": "summer", "hour": 12.0, "weather": "clear", "in_water": true}
	survival.call("update_temperature", 1.0, wading)
	if not is_equal_approx(float(survival.call("get_wetness")), 1.0):
		errors.append("marcher dans la rivière mouille")
	var dry_out := {"season": "summer", "hour": 12.0, "weather": "clear"}
	var dry_felt: float = script.call("air_temperature", "summer", 12.0, "clear", 0.0)
	survival.call("update_temperature", 30.0, dry_out)
	var half := float(survival.call("get_wetness"))
	if half <= 0.0 or half >= 1.0:
		errors.append("on sèche en une minute environ (%.2f après 30 s)" % half)
	if absf(float(survival.call("felt_temperature", dry_out)) - (dry_felt - 6.0 * half)) > 0.01 or half < 0.3:
		errors.append("mouillé, on a plus froid")
	survival.call("update_temperature", 40.0, dry_out)
	if float(survival.call("get_wetness")) > 0.0:
		errors.append("on finit par sécher")

	# --- Chaleur : l'été en plein après-midi donne soif.
	survival.call("update_temperature", 1.0, {"season": "summer", "hour": 15.0, "weather": "clear"})
	if not bool(survival.call("is_hot")):
		errors.append("l'après-midi d'été, il fait chaud")

	# --- Dégâts du froid et relève : la chaleur revient en partie.
	survival.call("clear_for_test")
	for i in 600:
		survival.call("update_temperature", 1.0, night)
	survival.call("revive")
	if float(survival.call("get_warmth")) < 0.6 or float(survival.call("get_wetness")) > 0.0:
		errors.append("après une défaite on se relève réchauffé et sec")

	# --- Traductions.
	for lang in ["fr", "en"]:
		var csv := FileAccess.get_file_as_string("res://locales/translations.%s.csv" % lang)
		for key in ["VITAL_WARMTH", "TOAST_COLD_HINT"]:
			if not csv.contains("\n" + key + ","):
				errors.append("clé de traduction manquante (%s) : %s" % [lang, key])

	if errors.is_empty():
		print("TEST_WARMTH: PASS")
		quit(0)
	else:
		for e in errors:
			print("TEST_WARMTH FAIL: " + e)
		quit(1)
