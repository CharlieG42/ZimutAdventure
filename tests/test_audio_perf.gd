extends SceneTree
## Sons de synthèse, ambiance et garde de performance.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	await process_frame
	var synth = load("res://scripts/audio/synth.gd")
	var rain: AudioStreamWAV = synth.noise(1.0, 0.35, 0.9)
	_check(rain.data.size() == 22050 * 2, "bruit d'une seconde : 16 bits mono")
	_check(rain.loop_mode == AudioStreamWAV.LOOP_FORWARD, "la pluie boucle")
	var note: AudioStreamWAV = synth.tone(440.0, 0.5)
	_check(note.data.size() == 11025 * 2 and note.loop_mode == AudioStreamWAV.LOOP_DISABLED, "note brève, sans boucle")
	var peak := 0
	for i in range(0, note.data.size(), 2):
		peak = maxi(peak, absi(note.data.decode_s16(i)))
	_check(peak > 1000 and peak < 32768, "amplitude audible sans saturation (%d)" % peak)
	var chord: AudioStreamWAV = synth.chord([262.0, 330.0, 392.0], 1.0)
	_check(chord.data.size() == 22050 * 2, "accord généré")
	_check((synth.trill(4200.0, 0.5, 22.0) as AudioStreamWAV).data.size() > 0, "trille généré")

	var sfx := root.get_node("Sfx")
	sfx.call("play_event", "splash")
	_check(true, "play_event silencieux en headless")
	var ambience := root.get_node("Ambience")
	_check(not bool(ambience.get("enabled")), "ambiance désactivée en headless")
	ambience.call("set_music_enabled", false)
	_check(not bool(ambience.get("music_enabled")), "musique coupable")

	var guard_script = load("res://scripts/autoload/performance_guard.gd")
	_check(bool(guard_script.should_degrade(25.0, 0)), "25 FPS : qualité réduite")
	_check(not bool(guard_script.should_degrade(55.0, 0)), "55 FPS : on ne touche à rien")
	_check(not bool(guard_script.should_degrade(25.0, 2)), "qualité déjà au plus bas")
	var guard := root.get_node("PerformanceGuard")
	_check(not bool(guard.get("enabled")), "garde inactive en headless")
	guard.call("set_level", 1)
	_check(bool(root.get_node("Weather").get("low_quality")), "niveau 1 : précipitations allégées")
	guard.call("set_level", 0)
	_check(not bool(root.get_node("Weather").get("low_quality")), "retour qualité normale")
	_check(String(guard.call("report")).contains("FPS"), "rapport de mesure")

	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
