extends SceneTree
## Réglage d'orientation (auto / paysage / portrait) : valeurs possibles, validation,
## application mobile sans crash en headless, clés de traduction FR/EN présentes.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	var settings := root.get_node_or_null("GameSettings")
	if settings == null:
		settings = load("res://scripts/autoload/game_settings.gd").new()
		settings.name = "GameSettings"
		root.add_child(settings)
		await process_frame

	var orientations: Array = settings.get("ORIENTATIONS")
	if not (orientations.has("auto") and orientations.has("landscape") and orientations.has("portrait")):
		errors.append("ORIENTATIONS devrait contenir auto/landscape/portrait, got %s" % str(orientations))
	settings.call("set_orientation", "portrait")
	if String(settings.get("orientation")) != "portrait":
		errors.append("set_orientation(portrait) non retenu, got %s" % String(settings.get("orientation")))
	settings.call("set_orientation", "bidon")
	if String(settings.get("orientation")) != "auto":
		errors.append("valeur invalide devrait retomber sur auto, got %s" % String(settings.get("orientation")))
	settings.call("set_orientation", "landscape")
	if String(settings.get("orientation")) != "landscape":
		errors.append("set_orientation(landscape) non retenu, got %s" % String(settings.get("orientation")))
	# apply() ne touche à l'orientation que sur mobile : aucun effet/crash en headless.
	settings.call("apply")

	for lang in ["fr", "en"]:
		var csv := FileAccess.get_file_as_string("res://locales/translations.%s.csv" % lang)
		for key in ["SETTING_ORIENTATION", "SETTING_ORIENTATION_AUTO", "SETTING_ORIENTATION_LANDSCAPE", "SETTING_ORIENTATION_PORTRAIT"]:
			if not csv.contains(key + ","):
				errors.append("%s : clé %s manquante" % [lang, key])

	var journal_text := FileAccess.get_file_as_string("res://scripts/ui/journal_panel.gd")
	if not journal_text.contains("set_orientation"):
		errors.append("journal_panel.gd devrait contenir le sélecteur set_orientation")

	if errors.is_empty():
		print("TEST_ORIENTATION_SETTING: PASS")
		quit(0)
	else:
		for e in errors: printerr("TEST_ORIENTATION_SETTING FAIL: " + e)
		quit(1)
