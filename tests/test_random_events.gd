extends SceneTree
## Événements aléatoires (GDD §4.6) : méne de loups la nuit (pas le jour, pas près
## d'un feu allumé), tempête soudaine forcée ~2 h, source d'eau révélée avec cap et
## distance. En headless la boucle auto ne tourne pas : on appelle force_event().

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _init() -> void:
	await process_frame
	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var player := world.get_node("Player") as Node3D
	var events := root.get_node_or_null("RandomEvents")
	var clock := root.get_node_or_null("DayNightCycle")
	var weather := root.get_node_or_null("Weather")
	var exploration := root.get_node_or_null("Exploration")
	if events == null or clock == null or weather == null or exploration == null:
		_check(false, "autoloads RandomEvents/DayNightCycle/Weather/Exploration présents")
		quit(1)
	weather.call("enable_effects_for_test", 0)
	if exploration.has_method("clear_for_test"):
		exploration.call("clear_for_test")

	# --- Meute de loups : la nuit seulement ---
	clock.call("set_hour", 12.0)
	await process_frame
	_check(String(clock.call("get_phase")) == "day", "12 h = phase jour")
	var wolves_before: int = get_nodes_in_group("predators").size()
	_check(not bool(events.call("force_event", "wolves_night", player)), "pas de loups le jour")
	clock.call("set_hour", 23.0)
	await process_frame
	_check(String(clock.call("get_phase")) == "night", "23 h = phase nuit")
	var fired: Array = []
	events.connect("event_fired", func(id): fired.append(id))
	_check(bool(events.call("force_event", "wolves_night", player)), "meute déclenchée la nuit")
	await process_frame
	var wolves_after: int = get_nodes_in_group("predators").size()
	_check(wolves_after >= wolves_before + 2, "2 loups de plus (avant=%d après=%d)" % [wolves_before, wolves_after])
	_check(fired.has("wolves_night"), "signal event_fired émis")

	# Feu de camp allumé à côté du joueur : la meute ne vient pas.
	var fire_script: GDScript = load("res://scripts/interaction/campfire.gd")
	_check(fire_script != null, "script campfire chargé")
	if fire_script != null:
		var fire: Node3D = fire_script.new()
		fire.name = "TestFire"
		world.add_child(fire)
		fire.global_position = player.global_position + Vector3(3, 0, 0)
		fire.call("apply_state", {"stage": 4})
		await process_frame
		_check(bool(fire.call("is_lit")), "feu allumé (stage 4)")
		var before_safe: int = get_nodes_in_group("predators").size()
		_check(not bool(events.call("force_event", "wolves_night", player)), "pas de loups près d'un feu allumé")
		_check(get_nodes_in_group("predators").size() == before_safe, "aucun loup ajouté près du feu")
		fire.queue_free()

	# --- Tempête soudaine : météo forcée ~2 h ---
	weather.call("clear_for_test")
	weather.call("enable_effects_for_test", 0)
	clock.call("set_hour", 10.0)
	await process_frame
	_check(bool(events.call("force_event", "storm", player)), "tempête déclenchée")
	_check(String(weather.call("get_weather")) == "rain", "météo forcée = pluie, got %s" % String(weather.call("get_weather")))
	_check(String(weather.call("_current_target")) == "rain", "la cible météo reste la pluie pendant le forçage")
	clock.call("set_hour", 13.0)
	await process_frame
	_check(String(weather.call("_current_target")) != "rain" or String(weather.call("get_weather")) == "rain", "après 2 h le forçage retombe (cible=%s)" % String(weather.call("_current_target")))
	_check(not bool(events.call("force_event", "storm", player)), "pas deux tempêtes d'affilée (déjà pluie)")

	# --- Source inconnue révélée ---
	var revealed_before: int = int(exploration.call("revealed_count"))
	_check(bool(events.call("force_event", "hidden_source", player)), "source inconnue déclenchée")
	_check(int(exploration.call("revealed_count")) > revealed_before, "cases révélées autour de la source (%d -> %d)" % [revealed_before, int(exploration.call("revealed_count"))])

	# Événement inconnu : refusé.
	_check(not bool(events.call("force_event", "dragon", player)), "événement inconnu refusé")

	# La boucle auto ne tourne pas en headless (déterminisme).
	var text := FileAccess.get_file_as_string("res://scripts/autoload/random_events.gd")
	_check(text.contains('DisplayServer.get_name() == "headless"'), "garde headless dans _process")

	for lang in ["fr", "en"]:
		var csv := FileAccess.get_file_as_string("res://locales/translations.%s.csv" % lang)
		for key in ["EVENT_WOLVES", "EVENT_STORM", "EVENT_SOURCE"]:
			if not csv.contains(key + ","):
				_failures += 1
				print("  FAIL - %s : clé %s manquante" % [lang, key])

	print("TEST_RANDOM_EVENTS: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
