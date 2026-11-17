extends Node

const MAX_PLAYERS: int = 8
## Sons placés dans le monde (voix des animaux, pas lointains) : volume et panoramique
## selon la distance au joueur.
const MAX_SPATIAL: int = 6

var _pool: Array[AudioStreamPlayer] = []
var _spatial: Array[AudioStreamPlayer3D] = []
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

## Joue un son nommé (voir SoundBank) : pas, hache, coups, eau, voix d'animaux, carillons…
func play_event(event_name: String, volume_db: float = -6.0, pitch_scale: float = 1.0) -> void:
	if not _audible:
		return
	var stream := SoundBank.pick(event_name)
	if stream != null:
		play(stream, volume_db, pitch_scale)

## Joue un son nommé à un endroit du monde (s'atténue avec la distance).
func play_event_at(event_name: String, position: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0,
		max_distance: float = 60.0) -> void:
	if not _audible:
		return
	var stream := SoundBank.pick(event_name)
	if stream == null:
		return
	var player := _acquire_spatial()
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.max_distance = max_distance
	player.play()

func _acquire_spatial() -> AudioStreamPlayer3D:
	for player in _spatial:
		if not player.playing:
			return player
	if _spatial.size() >= MAX_SPATIAL:
		return _spatial[0]
	var player := AudioStreamPlayer3D.new()
	player.unit_size = 6.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(player)
	_spatial.append(player)
	return player

func stop_all() -> void:
	for player in _pool:
		player.stop()
	for player in _spatial:
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
