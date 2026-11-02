extends Node

const MAX_PLAYERS: int = 8
const Synth := preload("res://scripts/audio/synth.gd")

var _pool: Array[AudioStreamPlayer] = []
var _events: Dictionary = {}
## Désactivé en headless : pas de génération de sons dans les tests.
var _audible: bool = DisplayServer.get_name() != "headless"

func play(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null:
		return
	var player := _acquire_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()

## Joue un son nommé : splash, bite, harvest, chime, treasure, cluck, moo, bark, hit.
func play_event(event_name: String, volume_db: float = -6.0, pitch_scale: float = 1.0) -> void:
	if not _audible:
		return
	var stream := _event_stream(event_name)
	if stream != null:
		play(stream, volume_db, pitch_scale)

func _event_stream(event_name: String) -> AudioStream:
	if _events.has(event_name):
		return _events[event_name]
	var stream: AudioStream = null
	match event_name:
		"splash": stream = Synth.splash()
		"bite": stream = Synth.tone(520.0, 0.25, 0.005, 9.0, 0.6, -240.0)
		"harvest": stream = Synth.splash(0.18, 0.45)
		"chime": stream = Synth.tone(880.0, 0.9, 0.005, 3.5, 0.5)
		"treasure": stream = Synth.chord([523.0, 659.0, 784.0, 1046.0], 1.4, 1.2)
		"cluck": stream = Synth.tone(620.0, 0.14, 0.004, 14.0, 0.6, 180.0)
		"moo": stream = Synth.tone(150.0, 0.8, 0.08, 2.2, 0.7, -30.0)
		"bark": stream = Synth.tone(300.0, 0.16, 0.004, 12.0, 0.7, -120.0)
		"hit": stream = Synth.splash(0.12, 0.8)
	_events[event_name] = stream
	return stream

func stop_all() -> void:
	for player in _pool:
		player.stop()

func _acquire_player() -> AudioStreamPlayer:
	for player in _pool:
		if not player.playing:
			return player
	if _pool.size() >= MAX_PLAYERS:
		return _pool[0]
	var player := AudioStreamPlayer.new()
	add_child(player)
	_pool.append(player)
	return player
