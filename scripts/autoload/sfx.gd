extends Node

const MAX_PLAYERS: int = 8

var _pool: Array[AudioStreamPlayer] = []

func play(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null:
		return
	var player := _acquire_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()

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
