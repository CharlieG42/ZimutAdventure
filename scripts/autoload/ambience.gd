extends Node
## Ambiance sonore : pluie et vent selon la météo, chants d'oiseaux le jour, grillons la nuit,
## et une musique douce qui change avec l'heure. Tout est synthétisé (aucun fichier audio).
## Désactivée en headless ; la musique se coupe avec `music_enabled`.

const Synth := preload("res://scripts/audio/synth.gd")
const FADE_SPEED := 18.0
const RAIN_DB := -12.0
## Vent : léger en permanence, plus fort la nuit, par mauvais temps et en hauteur.
const WIND_CALM_DB := -30.0
const WIND_DB := -21.0
const WIND_HIGH_ALTITUDE := 8.0
## Rivière : un son placé au point de la rivière le plus proche du joueur.
const RIVER_DB := -4.0
const RIVER_MAX_DISTANCE := 55.0
const RIVER_CHECK_SECONDS := 0.25
## Hurlements nocturnes : d'un prédateur assez loin, de temps en temps.
const HOWL_MIN_DISTANCE := 25.0
const HOWL_MAX_DISTANCE := 140.0
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
var _river: AudioStreamPlayer3D
var _river_timer: float = 0.0
var _howl_timer: float = 20.0
var _phrase_left: int = 0
var _bird_timer: float = 3.0
var _cricket_timer: float = 2.0
var _music_timer: float = 4.0
var _rng := RandomNumberGenerator.new()
var _cricket_sound: AudioStream
var _chords: Dictionary = {}

func _ready() -> void:
	_rng.randomize()
	if not enabled:
		set_process(false)
		return
	# Enregistrements (CC0) si présents, sinon bruits de synthèse.
	var rain_stream: AudioStream = SoundBank.loop("rain")
	var wind_stream: AudioStream = SoundBank.loop("wind")
	_rain = _loop_player(rain_stream if rain_stream != null else Synth.noise(2.5, 0.35, 0.9), SILENT_DB)
	_wind = _loop_player(wind_stream if wind_stream != null else Synth.noise(3.5, 0.93, 2.2), SILENT_DB)
	var river_stream: AudioStream = SoundBank.loop("river")
	if river_stream != null:
		_river = AudioStreamPlayer3D.new()
		_river.stream = river_stream
		_river.volume_db = RIVER_DB
		_river.unit_size = 8.0
		_river.max_distance = RIVER_MAX_DISTANCE
		add_child(_river)
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
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var high := player != null and player.global_position.y > WIND_HIGH_ALTITUDE
	_fade(_rain, RAIN_DB if raining else SILENT_DB, delta)
	var windy := raining or snowing or phase == "night" or high
	_fade(_wind, WIND_DB if windy else WIND_CALM_DB, delta)
	_update_river(player, delta)
	_bird_timer -= delta
	if _bird_timer <= 0.0:
		# Les oiseaux chantent par petites phrases de 2 à 4 notes.
		if _phrase_left > 0:
			_phrase_left -= 1
			_bird_timer = _rng.randf_range(0.12, 0.3)
			_chirp()
		else:
			_bird_timer = _rng.randf_range(3.0, 9.0)
			if (phase == "day" or phase == "dawn") and not raining and not snowing:
				_phrase_left = _rng.randi_range(1, 3)
				_chirp()
	if phase == "night":
		_howl_timer -= delta
		if _howl_timer <= 0.0:
			_howl_timer = _rng.randf_range(25.0, 55.0)
			_howl(player)
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
	var stream := SoundBank.pick("bird")
	if stream == null:
		return
	_birds.stream = stream
	_birds.volume_db = _rng.randf_range(-22.0, -15.0)
	_birds.pitch_scale = _rng.randf_range(0.85, 1.25)
	_birds.play()

## Place le son de la rivière au point de l'eau le plus proche du joueur.
func _update_river(player: Node3D, delta: float) -> void:
	if _river == null or player == null:
		return
	_river_timer -= delta
	if _river_timer > 0.0:
		return
	_river_timer = RIVER_CHECK_SECONDS
	var landscape := get_tree().get_first_node_in_group("landscape")
	if landscape == null or not landscape.has_method("nearest_water_point"):
		return
	var point: Vector3 = landscape.call("nearest_water_point", player.global_position)
	var near := point.distance_to(player.global_position) < RIVER_MAX_DISTANCE
	if near:
		_river.global_position = point
		if not _river.playing:
			_river.play()
	elif _river.playing:
		_river.stop()

## Un loup ou un coyote hurle au loin (pas trop près : on l'entend venir).
func _howl(player: Node3D) -> void:
	if player == null:
		return
	var sfx := InteractionManager.get_sfx()
	if sfx == null or not sfx.has_method("play_event_at"):
		return
	for predator in get_tree().get_nodes_in_group("predators"):
		if not (predator is Node3D):
			continue
		var distance := (predator as Node3D).global_position.distance_to(player.global_position)
		if distance > HOWL_MIN_DISTANCE and distance < HOWL_MAX_DISTANCE:
			var coyote := str(predator.get("species")) == "coyote"
			sfx.call("play_event_at", "howl", (predator as Node3D).global_position + Vector3(0.0, 1.0, 0.0),
					8.0, _rng.randf_range(1.15, 1.3) if coyote else _rng.randf_range(0.92, 1.02), 220.0)
			return

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
