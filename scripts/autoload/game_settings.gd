extends Node
## Réglages du joueur (user://settings.cfg) : musique, volume général, qualité graphique,
## compteur d'images, mini-carte. Appliqués au démarrage et à chaque changement.

signal changed

const SAVE_PATH := "user://settings.cfg"
const QUALITIES := ["auto", "high", "low"]
## auto = capteur (paysage et portrait selon la position du téléphone), sinon verrou.
const ORIENTATIONS := ["auto", "landscape", "portrait"]
const LOOK_SENSITIVITY_MIN := 0.4
const LOOK_SENSITIVITY_MAX := 2.5

var music: bool = true
var volume: float = 1.0
var quality: String = "auto"
var show_fps: bool = false
## Mini-carte du HUD. Désactivée = mode explorateur : on s'oriente à la boussole et à la carte.
var minimap: bool = true
## Orientation de l'écran sur mobile : "auto" (capteur), "landscape" ou "portrait".
var orientation: String = "auto"
## Multiplicateur de la vitesse de rotation de la caméra (glisser tactile et stick caméra).
var look_sensitivity: float = 1.0
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

func set_look_sensitivity(value: float) -> void:
	look_sensitivity = clampf(value, LOOK_SENSITIVITY_MIN, LOOK_SENSITIVITY_MAX)
	_commit()

func set_minimap(value: bool) -> void:
	minimap = value
	_commit()

func set_orientation(value: String) -> void:
	orientation = value if ORIENTATIONS.has(value) else "auto"
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
	# Le verrou d'orientation ne s'applique que sur mobile (les fenêtres PC tournent librement).
	if OS.has_feature("android") or OS.has_feature("ios"):
		var screen_orientation := DisplayServer.SCREEN_SENSOR
		if orientation == "landscape":
			screen_orientation = DisplayServer.SCREEN_SENSOR_LANDSCAPE
		elif orientation == "portrait":
			screen_orientation = DisplayServer.SCREEN_SENSOR_PORTRAIT
		DisplayServer.screen_set_orientation(screen_orientation)

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
	minimap = bool(config.get_value("hud", "minimap", true))
	look_sensitivity = clampf(float(config.get_value("controls", "look_sensitivity", 1.0)), LOOK_SENSITIVITY_MIN, LOOK_SENSITIVITY_MAX)
	orientation = String(config.get_value("display", "orientation", "auto"))
	if not ORIENTATIONS.has(orientation):
		orientation = "auto"

func _save() -> void:
	if not _persist:
		return
	var config := ConfigFile.new()
	config.set_value("audio", "music", music)
	config.set_value("audio", "volume", volume)
	config.set_value("video", "quality", quality)
	config.set_value("video", "show_fps", show_fps)
	config.set_value("hud", "minimap", minimap)
	config.set_value("controls", "look_sensitivity", look_sensitivity)
	config.set_value("display", "orientation", orientation)
	config.save(SAVE_PATH)
