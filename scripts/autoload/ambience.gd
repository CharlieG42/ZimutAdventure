extends Node
## Ambiance sonore : pluie et vent selon la météo, chants d'oiseaux le jour, grillons la nuit,
## et une musique douce qui change avec l'heure. Tout est synthétisé (aucun fichier audio).
## Désactivée en headless ; la musique se coupe avec `music_enabled`.

const Synth := preload("res://scripts/audio/synth.gd")
const FADE_SPEED := 18.0
const RAIN_DB := -14.0
const WIND_DB := -26.0
const MUSIC_DB := -24.0
const SILENT_DB := -60.0

## Notes (Hz) de la musique par phase de la journée.
const SCALES := {
	"day": [[262.0, 330.0, 392.0], [294.0, 370.0, 440.0], [349.0, 440.0, 523.0]],
	"dawn": [[220.0, 277.0, 330.0], [247.0, 311.0, 370.0]],
	"dusk": [[196.0, 247.0, 294.0], [220.0, 262.0, 330.0]],
	"night": [[110.0, 131.0, 165.0], [123.0, 147.0, 185.0]],
}

var enabled: bool = DisplayServer.get_name() != "headless"
var music_enabled: bool = true
var _rain: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _music: AudioStreamPlayer
var _birds: AudioStreamPlayer
var _crickets: AudioStreamPlayer
var _bird_timer: float = 3.0
var _cricket_timer: float = 2.0
var _music_timer: float = 4.0
var _rng := RandomNumberGenerator.new()
var _bird_sounds: Array = []
var _cricket_sound: AudioStream
var _chords: Dictionary = {}

func _ready() -> void:
	_rng.randomize()
	if not enabled:
		set_process(false)
		return
	_rain = _loop_player(Synth.noise(2.5, 0.35, 0.9), SILENT_DB)
	_wind = _loop_player(Synth.noise(3.5, 0.93, 2.2), SILENT_DB)
	_music = _one_shot_player()
	_birds = _one_shot_player()
	_crickets = _one_shot_player()

func _loop_player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = db
	add_child(player)
	player.play()
	return player

func _one_shot_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	return player

func _process(delta: float) -> void:
	var weather := InteractionManager.get_weather()
	var clock := InteractionManager.get_day_night()
	var phase := String(clock.call("get_phase")) if clock != null else "day"
	var raining := weather != null and bool(weather.call("is_raining"))
	var snowing := weather != null and bool(weather.call("effects_active")) and String(weather.call("get_weather")) == "snow"
	_fade(_rain, RAIN_DB if raining else SILENT_DB, delta)
	_fade(_wind, WIND_DB if (raining or snowing or phase == "night") else SILENT_DB, delta)
	_bird_timer -= delta
	if _bird_timer <= 0.0:
		_bird_timer = _rng.randf_range(3.0, 9.0)
		if (phase == "day" or phase == "dawn") and not raining and not snowing:
			_chirp()
	_cricket_timer -= delta
	if _cricket_timer <= 0.0:
		_cricket_timer = _rng.randf_range(3.5, 8.0)
		if phase == "night" and not raining and not snowing:
			_cricket()
	_music_timer -= delta
	if _music_timer <= 0.0:
		_music_timer = _rng.randf_range(9.0, 14.0)
		if music_enabled:
			_play_chord(phase)

func _fade(player: AudioStreamPlayer, target_db: float, delta: float) -> void:
	player.volume_db = move_toward(player.volume_db, target_db, FADE_SPEED * delta)

func _chirp() -> void:
	if _bird_sounds.is_empty():
		for freq in [2400.0, 3000.0, 2700.0]:
			_bird_sounds.append(Synth.tone(freq, 0.18, 0.004, 10.0, 0.5, 700.0))
	_birds.stream = _bird_sounds[_rng.randi() % _bird_sounds.size()]
	_birds.volume_db = _rng.randf_range(-24.0, -17.0)
	_birds.pitch_scale = _rng.randf_range(0.9, 1.15)
	_birds.play()

func _cricket() -> void:
	if _cricket_sound == null:
		_cricket_sound = Synth.trill(4200.0, 1.6, 22.0, 0.35)
	_crickets.stream = _cricket_sound
	_crickets.volume_db = -26.0
	_crickets.pitch_scale = _rng.randf_range(0.9, 1.08)
	_crickets.play()

func _play_chord(phase: String) -> void:
	var options: Array = SCALES.get(phase, SCALES["day"])
	var index := _rng.randi() % options.size()
	var key := "%s_%d" % [phase, index]
	if not _chords.has(key):
		_chords[key] = Synth.chord(options[index], 9.0, 0.8)
	_music.stream = _chords[key]
	_music.volume_db = MUSIC_DB
	_music.play()

func set_music_enabled(value: bool) -> void:
	music_enabled = value
	if not value and _music != null:
		_music.stop()
