extends SceneTree
## Chaque « global uniform » utilisé par un shader du projet doit être déclaré dans
## [shader_globals] de project.godot (sinon le shader se compile mal, sans erreur en headless).

func _scan(dir: String, found: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gdshader"):
			var text := FileAccess.get_file_as_string(dir.path_join(f))
			for line in text.split("\n"):
				var t := line.strip_edges()
				if t.begins_with("global uniform"):
					var parts := t.replace(";", "").split(" ", false)
					# « global uniform <type> <nom> [: hint] ; » : le nom est le 4e mot.
					var name := String(parts[3]) if parts.size() > 3 else ""
					if name == "":
						continue
					found.append([dir.path_join(f), name])
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_scan(dir.path_join(d), found)

func _initialize() -> void:
	var found: Array = []
	_scan("res://assets", found)
	_scan("res://scripts", found)
	var failures := 0
	for entry in found:
		var declared := ProjectSettings.has_setting("shader_globals/" + String(entry[1]))
		print("  %s - %s dans %s" % ["ok" if declared else "FAIL", entry[1], entry[0]])
		if not declared:
			failures += 1
	if found.is_empty():
		failures += 1
		print("  FAIL - aucun global uniform trouvé (scan cassé ?)")
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
