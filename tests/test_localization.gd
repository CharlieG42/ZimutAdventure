extends SceneTree

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	TranslationServer.set_locale("fr")
	if tr("STATUS_THIRST") != "Soif":
		errors.append("fr STATUS_THIRST: got '%s'" % tr("STATUS_THIRST"))
	if tr("REGION_AMERICAN_WEST") != "Ouest américain":
		errors.append("fr REGION_AMERICAN_WEST: got '%s'" % tr("REGION_AMERICAN_WEST"))

	TranslationServer.set_locale("en")
	if tr("STATUS_THIRST") != "Thirst":
		errors.append("en STATUS_THIRST: got '%s'" % tr("STATUS_THIRST"))
	if tr("BIOME_CANYON") != "Canyon":
		errors.append("en BIOME_CANYON: got '%s'" % tr("BIOME_CANYON"))

	var exit_code := 0
	if errors.is_empty():
		print("TEST_LOCALIZATION: PASS")
	else:
		exit_code = 1
		for e in errors:
			printerr("TEST_LOCALIZATION FAIL: " + e)
	quit(exit_code)
