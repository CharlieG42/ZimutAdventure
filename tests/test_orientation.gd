extends SceneTree

# L'orientation du jeu doit suivre la position du téléphone : aucun verrou,
# paysage (deux mains) ET portrait (une main) autorisés tous les deux.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	# Projet : orientation capteur (6 = sensor) sur mobile, aucun verrou.
	var orientation := int(ProjectSettings.get_setting("display/window/size/orientation", -1))
	if orientation != 6:
		errors.append("display/window/size/orientation devrait être 6 (sensor), got %d" % orientation)

	# Preset d'export Android : paysage ET portrait supportés (manifeste fullSensor).
	var text := FileAccess.get_file_as_string("res://export_presets.cfg")
	if text == "":
		errors.append("export_presets.cfg illisible")
	else:
		if not text.contains("screen/support_landscape=true"):
			errors.append("preset Android : screen/support_landscape devrait être true")
		if not text.contains("screen/support_portrait=true"):
			errors.append("preset Android : screen/support_portrait devrait être true (rotation automatique)")

	# Le HUD doit posséder un mode portrait (une main) déclenché par l'aspect.
	var hud_script := load("res://scripts/ui/hud.gd") as GDScript
	var hud_text := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	if hud_script == null or not hud_text.contains("vp.x < vp.y"):
		errors.append("hud.gd devrait choisir le mode portrait via l'aspect (vp.x < vp.y)")

	# Le joueur élargit le FOV en portrait (champ horizontal rétréci).
	var player_text := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	if not player_text.contains("portrait_fov_boost"):
		errors.append("player.gd devrait déclarer portrait_fov_boost")

	if errors.is_empty():
		print("TEST_ORIENTATION: PASS")
		quit(0)
	else:
		for e in errors: printerr("TEST_ORIENTATION FAIL: " + e)
		quit(1)
