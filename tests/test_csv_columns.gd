extends SceneTree
## Chaque ligne des fichiers de traduction a exactement 2 colonnes (clé, texte) :
## une virgule non protégée par des guillemets fait planter l'import de Godot.

func _initialize() -> void:
	var failures := 0
	for lang in ["fr", "en"]:
		var file := FileAccess.open("res://locales/translations.%s.csv" % lang, FileAccess.READ)
		var line_number := 0
		while not file.eof_reached():
			var row := file.get_csv_line()
			line_number += 1
			if row.size() == 1 and row[0] == "":
				continue
			if row.size() != 2:
				failures += 1
				print("  FAIL - %s ligne %d : %d colonnes (%s)" % [lang, line_number, row.size(), row[0]])
	print("TEST_CSV_COLUMNS: ", "PASS" if failures == 0 else "FAIL")
	quit(1 if failures > 0 else 0)
