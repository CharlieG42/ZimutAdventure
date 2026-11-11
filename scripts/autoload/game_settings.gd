extends Node
## Réglages du joueur (user://settings.cfg) : musique, volume général, qualité graphique,
## compteur d'images. Appliqués au démarrage et à chaque changement.

signal changed

const SAVE_PATH := "user://settings.cfg"
const QUALITIES := ["auto", "high", "low"]

var music: bool = true
var volume: float = 1.0
var quality: String = "auto"
var show_fps: bool = false
var _persist: bool = DisplayServer.get_name() != "headless"

func _ready() -> void:
	_load()
	apply.call_deferred()

func set_music(value: bool) -> void:
	music = value
	_commit()

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	_commit()

func set_quality(value: String) -> void:
	quality = value if QUALITIES.has(value) else "auto"
	_commit()

func set_show_fps(value: bool) -> void:
	show_fps = value
	_commit()

func _commit() -> void:
	apply()
	_save()
	changed.emit()

func apply() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, volume <= 0.001)
		AudioServer.set_bus_volume_db(master, linear_to_db(maxf(volume, 0.001)))
	var root := get_tree().root if get_tree() != null else null
	if root == null:
		return
	var ambience := root.get_node_or_null("Ambience")
	if ambience != null:
		ambience.call("set_music_enabled", music)
	var guard := root.get_node_or_null("PerformanceGuard")
	if guard != null:
		guard.call("set_mode", quality)
		guard.call("set_overlay_visible", show_fps)

func _load() -> void:
	if not _persist:
		return
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	music = bool(config.get_value("audio", "music", true))
	volume = clampf(float(config.get_value("audio", "volume", 1.0)), 0.0, 1.0)
	quality = String(config.get_value("video", "quality", "auto"))
	if not QUALITIES.has(quality):
		quality = "auto"
	show_fps = bool(config.get_value("video", "show_fps", false))

func _save() -> void:
	if not _persist:
		return
	var config := ConfigFile.new()
	config.set_value("audio", "music", music)
	config.set_value("audio", "volume", volume)
	config.set_value("video", "quality", quality)
	config.set_value("video", "show_fps", show_fps)
	config.save(SAVE_PATH)
