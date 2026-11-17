extends SceneTree
## Sons : chaque enregistrement CC0 se charge, les ambiances bouclent, les voix synthétisées
## existent pour les animaux sans enregistrement libre, les sons placés dans le monde
## passent par un lecteur 3D, la rivière s'entend du point d'eau le plus proche.

func _init() -> void:
	await process_frame
	var errors: Array[String] = []

	for event_name in SoundBank.FILES:
		var expected: int = (SoundBank.FILES[event_name] as Array).size()
		var found := SoundBank.recording_count(event_name)
		if found != expected:
			errors.append("%s : %d enregistrement(s) sur %d" % [event_name, found, expected])
		if SoundBank.pick(event_name) == null:
			errors.append("%s : aucun son" % event_name)
	for loop_name in SoundBank.LOOPS:
		var stream := SoundBank.loop(loop_name)
		if not (stream is AudioStreamOggVorbis) or not (stream as AudioStreamOggVorbis).loop:
			errors.append("ambiance %s : doit boucler" % loop_name)
		elif stream.get_length() < 4.0:
			errors.append("ambiance %s : trop courte (%.1f s)" % [loop_name, stream.get_length()])

	# Voix de synthèse : vache, cheval, loup, poule ; durées crédibles.
	var durations := {"moo": [0.9, 2.0], "neigh": [0.8, 1.6], "howl": [2.0, 3.5], "cluck": [0.08, 0.4]}
	for event_name in durations:
		var voice := SoundBank.synth(event_name) as AudioStreamWAV
		if voice == null:
			errors.append("voix %s absente" % event_name)
			continue
		var length := voice.get_length()
		if length < float(durations[event_name][0]) or length > float(durations[event_name][1]):
			errors.append("voix %s : %.2f s" % [event_name, length])
		var peak := 0
		for i in range(0, voice.data.size() - 1, 64):
			peak = maxi(peak, absi(voice.data.decode_s16(i)))
		if peak < 3000:
			errors.append("voix %s : silencieuse" % event_name)

	# Chaque espèce domestique a un cri, avec un son disponible.
	var domestic := load("res://scripts/world/domestic_animal.gd") as GDScript
	var voices: Dictionary = domestic.get_script_constant_map()["VOICES"]
	for kind in ["cow", "sheep", "goat", "chicken", "horse", "dog"]:
		if not voices.has(kind) or SoundBank.pick(String(voices[kind][0])) == null:
			errors.append("cri manquant : %s" % kind)

	# Son placé : passe par un lecteur 3D positionné.
	var sfx := root.get_node_or_null("Sfx")
	if sfx == null:
		sfx = (load("res://scripts/autoload/sfx.gd") as GDScript).new()
		sfx.name = "Sfx"
		root.add_child(sfx)
	sfx.set("_audible", true)
	sfx.call("play_event_at", "baa", Vector3(10.0, 1.0, -4.0), -3.0, 1.0)
	var spatial: Array = sfx.get("_spatial")
	if spatial.is_empty() or not ((spatial[0] as AudioStreamPlayer3D).global_position - Vector3(10.0, 1.0, -4.0)).is_zero_approx():
		errors.append("un cri d'animal se place dans l'espace")
	sfx.call("stop_all")
	sfx.set("_audible", false)

	# Rivière : le point d'eau le plus proche est bien dans l'eau, et proche.
	var landscape := (load("res://scripts/world/landscape_manager.gd") as GDScript).new() as Node3D
	root.add_child(landscape)
	await process_frame
	for p in [Vector3(40.0, 0.0, -30.0), Vector3(-60.0, 0.0, 120.0), Vector3(-200.0, 0.0, 40.0), Vector3(120.0, 0.0, 10.0)]:
		var w: Vector3 = landscape.call("nearest_water_point", p)
		if not bool(landscape.call("is_water", w.x, w.z, 0.5)):
			errors.append("le point d'eau le plus proche de %s doit être dans l'eau (%s)" % [p, w])
		var direct: float = landscape.call("river_distance", p.x, p.z)
		var found := Vector2(w.x - p.x, w.z - p.z).length()
		if found > direct + 6.0:
			errors.append("point d'eau trop loin pour %s : %.1f m au lieu de ~%.1f m" % [p, found, direct])
	landscape.free()

	# Crédits des sons.
	if not FileAccess.file_exists("res://assets/audio/CREDITS.md"):
		errors.append("assets/audio/CREDITS.md manquant")

	if errors.is_empty():
		print("TEST_SOUND_BANK: PASS")
		quit(0)
	else:
		for e in errors:
			print("TEST_SOUND_BANK FAIL: " + e)
		quit(1)
