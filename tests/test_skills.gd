extends SceneTree
## Compétences (GDD §4.7) : paliers d'XP (SKILL_XP = 4, 8, 14, 22, 32), facteurs
## d'effet (orientation/survie/chasse/équitation), intégration brouillard de carte,
## carte « Compétences » dans le journal, locales FR/EN.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _init() -> void:
	await process_frame
	var progression := root.get_node_or_null("Progression")
	if progression == null:
		progression = load("res://scripts/autoload/progression.gd").new()
		progression.name = "Progression"
		root.add_child(progression)
		await process_frame
	progression.call("clear_for_test")

	# --- Paliers d'XP ---
	_check(int(progression.call("get_skill_level", "orientation")) == 0, "niveau 0 au départ")
	progression.call("add_skill_xp", "orientation", 3)
	_check(int(progression.call("get_skill_level", "orientation")) == 0, "3 XP < 4 : toujours niveau 0")
	progression.call("add_skill_xp", "orientation", 1)
	_check(int(progression.call("get_skill_level", "orientation")) == 1, "4 XP = niveau 1")
	progression.call("add_skill_xp", "orientation", 8)
	_check(int(progression.call("get_skill_level", "orientation")) == 2, "12 XP = niveau 2")
	progression.call("add_skill_xp", "orientation", 1000)
	_check(int(progression.call("get_skill_level", "orientation")) == 5, "plafonné à SKILL_MAX=5")
	_check(absf(float(progression.call("skill_fraction", "orientation")) - 1.0) < 0.001, "fraction 1.0 au max")
	progression.call("add_skill_xp", "vol", 10)
	_check(int(progression.call("get_skill_level", "vol")) == 0, "compétence inconnue ignorée")

	var skill_events: Array = []
	progression.connect("skill_changed", func(s, l): skill_events.append([s, l]))
	progression.call("clear_for_test")
	progression.call("add_skill_xp", "chasse", 4)
	_check(skill_events.size() == 1 and String(skill_events[0][0]) == "chasse" and int(skill_events[0][1]) == 1,
		"signal skill_changed émis au passage de niveau")

	# --- Facteurs d'effet ---
	progression.call("clear_for_test")
	progression.call("add_skill_xp", "survie", 80)
	_check(absf(float(progression.call("survie_drain_factor")) - 0.6) < 0.001, "survie niv. 5 : drain ×0.6")
	progression.call("clear_for_test")
	progression.call("add_skill_xp", "orientation", 12)
	_check(absf(float(progression.call("orientation_reveal_bonus")) - 1.4) < 0.001, "orientation niv. 2 : révélation ×1.4")
	progression.call("clear_for_test")
	progression.call("add_skill_xp", "chasse", 80)
	_check(absf(float(progression.call("chasse_spread_factor")) - 0.4) < 0.001, "chasse niv. 5 : dispersion ×0.4")
	progression.call("clear_for_test")
	progression.call("add_skill_xp", "equitation", 26)
	_check(absf(float(progression.call("equitation_speed_factor")) - 1.15) < 0.001, "équitation niv. 3 : monture ×1.15")

	# --- Intégration : la révélation de carte tient compte d'Orientation ---
	var exploration := root.get_node_or_null("Exploration")
	if exploration == null:
		_check(false, "autoload Exploration présent")
	else:
		if exploration.has_method("clear_for_test"):
			exploration.call("clear_for_test")
		progression.call("clear_for_test")
		exploration.call("reveal", 0.0, 0.0, 10.0)
		var count_lvl0: int = int(exploration.call("revealed_count"))
		if exploration.has_method("clear_for_test"):
			exploration.call("clear_for_test")
		progression.call("add_skill_xp", "orientation", 12)  # niveau 2 -> x1.4
		exploration.call("reveal", 0.0, 0.0, 10.0)
		var count_lvl2: int = int(exploration.call("revealed_count"))
		_check(count_lvl2 > count_lvl0, "orientation niv. 2 révèle plus de cases (%d -> %d)" % [count_lvl0, count_lvl2])

	# --- Câblages ---
	var survival_text := FileAccess.get_file_as_string("res://scripts/autoload/survival_manager.gd")
	_check(survival_text.contains("survie_drain_factor"), "survie : drain câblé dans survival_manager.gd")
	_check(survival_text.contains('add_skill_xp", "survie"'), "survie : XP sur eat/drink")
	var player_text := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_check(player_text.contains("chasse_spread_factor"), "chasse : dispersion de l'arc câblée")
	_check(player_text.contains("equitation_speed_factor"), "équitation : vitesse de monture câblée")
	_check(player_text.contains('add_skill_xp", "equitation"'), "équitation : XP à cheval")
	var journal_text := FileAccess.get_file_as_string("res://scripts/ui/journal_panel.gd")
	_check(journal_text.contains("_add_skills_card") and journal_text.contains("skill_changed"), "journal : carte Compétences + mise à jour en direct")

	for lang in ["fr", "en"]:
		var csv := FileAccess.get_file_as_string("res://locales/translations.%s.csv" % lang)
		for key in ["SKILLS_TITLE", "SKILL_ORIENTATION", "SKILL_SURVIE", "SKILL_CHASSE", "SKILL_EQUITATION",
				"SKILL_DESC_ORIENTATION", "SKILL_DESC_SURVIE", "SKILL_DESC_CHASSE", "SKILL_DESC_EQUITATION", "TOAST_SKILL_UP"]:
			if not csv.contains(key + ","):
				_failures += 1
				print("  FAIL - %s : clé %s manquante" % [lang, key])

	print("TEST_SKILLS: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
